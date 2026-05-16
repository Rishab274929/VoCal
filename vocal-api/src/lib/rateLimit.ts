// KV-backed sliding-minute token bucket.
//
// Why a per-minute fixed window vs. a true sliding window: KV writes cost a
// round-trip and there's no atomic increment, so a fully-precise sliding
// window would need either a Durable Object or RMW with optimistic retries.
// At our limits (10–60/min) a minute-bucket is the right trade-off: a busy
// caller can briefly exceed the limit at a window boundary, but never by
// more than ~2x in a 60-second window, and we cap abuse to "expensive but
// not catastrophic" without paying for stronger consistency.
//
// Identity: prefer the JWT `sub` so a single anon user can't multiplex
// across IPs (mobile carrier NAT, VPNs). Falls back to the CF-Connecting-IP
// header for unauthenticated traffic (anonymous auth endpoint, mostly).
//
// Failure mode: if KV is unbound or a read/write throws we FAIL OPEN. A
// rate limiter that breaks the whole API on a KV blip would be worse than
// no rate limiter at all.

import { authIdentity } from "./auth";

export interface RateLimitResult {
  allowed: boolean;
  /** Seconds the caller should wait before retrying. 0 when allowed. */
  retryAfterSec: number;
  /** Diagnostic — what we keyed on. */
  identifier: string;
}

interface RateLimitEnv {
  FOOD_KV?: KVNamespace;
  JWT_SECRET?: string;
}

/**
 * Check + increment the bucket. Atomically? No — see file header. Designed
 * for cheap protection against abuse at hackathon scale.
 *
 * @param env     worker bindings (needs FOOD_KV and JWT_SECRET)
 * @param request inbound Request; used for identity + IP fallback
 * @param endpoint short label like "photo/parse" — keeps buckets per-route
 * @param limit   max requests per minute
 */
export async function checkRateLimit(
  env: RateLimitEnv,
  request: Request,
  endpoint: string,
  limit: number
): Promise<RateLimitResult> {
  // No KV bound → can't track state. Fail open so local `wrangler pages dev`
  // (which doesn't always have KV attached) doesn't lock people out.
  if (!env.FOOD_KV) {
    return { allowed: true, retryAfterSec: 0, identifier: "no-kv" };
  }

  const identifier = await resolveIdentifier(request, env);
  const minuteBucket = Math.floor(Date.now() / 60_000);
  const key = `rl:${endpoint}:${identifier}:${minuteBucket}`;

  let count = 0;
  try {
    const raw = await env.FOOD_KV.get(key);
    count = raw ? parseInt(raw, 10) || 0 : 0;
  } catch {
    // KV read blip → fail open. Don't punish callers for our infra hiccup.
    return { allowed: true, retryAfterSec: 0, identifier };
  }

  if (count >= limit) {
    // Compute seconds until the next minute boundary so the client knows
    // when the bucket resets. Cap at the bucket size to avoid weird >60s
    // values from clock drift.
    const nowMs = Date.now();
    const nextBoundary = (minuteBucket + 1) * 60_000;
    const retryAfterSec = Math.min(60, Math.max(1, Math.ceil((nextBoundary - nowMs) / 1000)));
    return { allowed: false, retryAfterSec, identifier };
  }

  // Increment. TTL 90s so the key is gone well before its 2nd minute. The
  // RMW race here is acceptable — see file header.
  try {
    await env.FOOD_KV.put(key, String(count + 1), { expirationTtl: 90 });
  } catch {
    // Write blip → still allow the request. We logged it for observability.
    console.warn("rateLimit: KV put failed", { endpoint, identifier });
  }

  return { allowed: true, retryAfterSec: 0, identifier };
}

/**
 * Build a 429 Response with the standard Retry-After header. Use this when
 * `checkRateLimit` returns `allowed: false`.
 */
export function rateLimitedResponse(result: RateLimitResult, corsHeaders?: Record<string, string>): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limited",
      retry_after_sec: result.retryAfterSec
    }),
    {
      status: 429,
      headers: {
        "Content-Type": "application/json",
        "Retry-After": String(result.retryAfterSec),
        ...(corsHeaders ?? {})
      }
    }
  );
}

/**
 * Identity resolution: JWT sub → CF-Connecting-IP → "unknown". We sanitize
 * the value so it can't break the KV key format ('rl:photo/parse:<id>:42').
 */
async function resolveIdentifier(request: Request, env: RateLimitEnv): Promise<string> {
  // Cheap path: only try JWT if there's a bearer header at all.
  const authHeader = request.headers.get("authorization") || request.headers.get("Authorization");
  if (authHeader && /^Bearer\s+/i.test(authHeader)) {
    try {
      const identity = await authIdentity(request, env);
      if (identity.userId) {
        return `u:${sanitize(identity.userId)}`;
      }
    } catch {
      // Fall through to IP — auth verification failures shouldn't break rate
      // limiting (auth endpoints will reject the request itself anyway).
    }
  }
  const ip = request.headers.get("CF-Connecting-IP")
    || request.headers.get("cf-connecting-ip")
    || "unknown";
  return `ip:${sanitize(ip)}`;
}

function sanitize(s: string): string {
  // KV keys are byte-strings up to 512B; ours stay tiny but we strip colons
  // so the segment can't ambiguate the key format.
  return s.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 64);
}

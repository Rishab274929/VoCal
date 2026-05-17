// Authentication helper for protected endpoints.
//
// The iOS app and Flutter app already obtain a JWT from /api/auth/anonymous
// or /api/auth/google. This helper extracts and verifies the bearer token,
// returning a stable user identity to the caller.
//
// We deliberately keep the behavior soft: many existing endpoints accept a
// body field `user_id` for backwards-compatibility with older clients (and
// the hackathon-era "demo-user" path). The recommended flow is:
//
//   const identity = await authIdentity(request, env);
//   const userId = identity.userId
//     ?? body.user_id?.trim()
//     ?? "demo-user";
//   if (identity.userId && body.user_id && identity.userId !== body.user_id) {
//     // Mismatch — log it; trust the JWT.
//   }
//
// When ALL clients have shipped with bearer-token auth we can flip this to
// hard-required and return 401 on missing/invalid tokens.

import { signJWT, verifyJWT } from "./jwt";

export interface AuthIdentity {
  /** Stable user identifier from a verified JWT. Null if no/invalid token. */
  userId: string | null;
  /** Auth provider that minted the token. */
  provider: "anonymous" | "google" | "apple" | null;
  /** Raw claims (advisory only — caller should not trust unverified fields). */
  claims: Record<string, unknown> | null;
}

export async function authIdentity(
  request: Request,
  env: { JWT_SECRET?: string }
): Promise<AuthIdentity> {
  const header = request.headers.get("Authorization") || request.headers.get("authorization");
  if (!header) return { userId: null, provider: null, claims: null };
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return { userId: null, provider: null, claims: null };
  const token = m[1].trim();
  // Refuse to verify against the public dev default in production. Without
  // this, an attacker who knows the source could mint tokens.
  let secret = env.JWT_SECRET;
  if (!secret || secret.length < 16) {
    // No real secret configured — there's no way to safely verify the token.
    // Treat as unauthenticated rather than accepting it.
    return { userId: null, provider: null, claims: null };
  }
  const claims = await verifyJWT(token, secret);
  if (!claims) return { userId: null, provider: null, claims: null };
  const sub = typeof claims.sub === "string" ? claims.sub : null;
  let provider: AuthIdentity["provider"] = null;
  if (claims.provider === "google") provider = "google";
  else if (claims.provider === "apple") provider = "apple";
  else if (claims.anon === true) provider = "anonymous";
  return { userId: sub, provider, claims };
}

/**
 * Resolve a user identity to use for a write, preferring a verified JWT.
 *
 * @param identity result of authIdentity()
 * @param bodyUserId user_id supplied in the request body (legacy clients)
 * @returns { userId, mismatch } — `mismatch` is true when both are set and disagree.
 */
export function resolveUserId(
  identity: AuthIdentity,
  bodyUserId: string | null | undefined
): { userId: string; mismatch: boolean; source: "jwt" | "body" | "default" } {
  const sanitize = (s: string): string =>
    s.replace(/[^A-Za-z0-9_.:-]/g, "").slice(0, 96);
  if (identity.userId) {
    const body = bodyUserId?.trim();
    const mismatch = !!body && body !== identity.userId;
    return { userId: sanitize(identity.userId), mismatch, source: "jwt" };
  }
  if (bodyUserId?.trim()) {
    return { userId: sanitize(bodyUserId.trim()), mismatch: false, source: "body" };
  }
  return { userId: "demo-user", mismatch: false, source: "default" };
}

/** Thrown by requireUserId when no valid JWT is present. Catch in handlers
 *  and return the bundled Response (already has CORS-safe shape). */
export class AuthRequiredError extends Error {
  constructor(public readonly reason: "missing" | "invalid") {
    super(reason === "missing" ? "missing bearer token" : "invalid bearer token");
  }
}

/**
 * Hard-required identity. Throws AuthRequiredError if no valid JWT is
 * present in the Authorization header. Use this on protected endpoints
 * where we explicitly do NOT want a body.user_id fallback.
 *
 * The optional `bodyUserId` is accepted only for mismatch logging — the
 * JWT sub always wins.
 */
export async function requireUserId(
  env: { JWT_SECRET?: string },
  request: Request,
  bodyUserId?: string | null
): Promise<{ userId: string; identity: AuthIdentity }> {
  const header = request.headers.get("Authorization") || request.headers.get("authorization");
  if (!header || !/^Bearer\s+/i.test(header)) {
    throw new AuthRequiredError("missing");
  }
  const identity = await authIdentity(request, env);
  if (!identity.userId) {
    // Header was present but verification failed (bad secret, expired, malformed).
    throw new AuthRequiredError("invalid");
  }
  const sanitize = (s: string): string =>
    s.replace(/[^A-Za-z0-9_.:-]/g, "").slice(0, 96);
  const body = bodyUserId?.trim();
  if (body && body !== identity.userId) {
    console.warn("requireUserId: rejecting client user_id, using JWT sub", {
      jwt: identity.userId,
      claimed: body
    });
  }
  return { userId: sanitize(identity.userId), identity };
}

export interface MintedSession {
  userId: string;
  token: string;
  expiresAt: number;
}

/**
 * Soft variant of requireUserId: if the request has NO Authorization header
 * at all, mints a fresh anonymous JWT (mirrors /api/auth/anonymous) so the
 * caller proceeds with a temp identity. If a Bearer header IS present but
 * invalid (expired/wrong-secret/malformed), still 401s — that's a real
 * client error, and silently downgrading would mask post-deploy token
 * mismatches.
 *
 * Use on feature endpoints where first-touch friction is worse than the
 * cost of granting a free anon session (coach/voice, photo/parse, etc.).
 * Do NOT use on user-scoped data endpoints where stable identity matters
 * (meals, profile) — those should hard-require auth.
 *
 * When `mintedSession` is returned, attach `mintedSessionHeaders(...)` to
 * the response so the client can persist the new token.
 */
export async function requireUserIdOrMint(
  env: { JWT_SECRET?: string; DB?: D1Database },
  request: Request
): Promise<{ userId: string; identity: AuthIdentity; mintedSession?: MintedSession }> {
  const header = request.headers.get("Authorization") || request.headers.get("authorization");
  if (header) {
    const identity = await authIdentity(request, env);
    if (identity.userId) return { userId: identity.userId, identity };
    throw new AuthRequiredError("invalid");
  }
  let secret = env.JWT_SECRET;
  if (!secret || secret.length < 16) {
    if (env.DB) throw new AuthRequiredError("invalid");
    secret = "vocal-dev-secret-rotate-in-prod";
  }
  const deviceId = crypto.randomUUID();
  const userId = `anon_${deviceId.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32)}`;
  const now = Date.now();
  const expiresAt = now + 60 * 60 * 1000;
  try {
    await env.DB?.prepare(
      `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4)`
    ).bind(userId, "Anonymous", now, now).run();
  } catch {
    // DB miss non-fatal; token is still valid.
  }
  const token = await signJWT({ sub: userId, anon: true }, secret, expiresAt);
  return {
    userId,
    identity: { userId, provider: "anonymous", claims: { sub: userId, anon: true } },
    mintedSession: { userId, token, expiresAt }
  };
}

export function mintedSessionHeaders(minted: MintedSession): Record<string, string> {
  return {
    "X-Vocal-Anon-User-Id": minted.userId,
    "X-Vocal-Anon-Token": minted.token,
    "X-Vocal-Anon-Expires-At": String(minted.expiresAt)
  };
}

/** Helper to build a uniform 401 response from an AuthRequiredError.
 *  Caller passes the CORS headers it would otherwise set on a success. */
export function authErrorResponse(
  err: AuthRequiredError,
  corsHeaders: Record<string, string> = {}
): Response {
  const code = err.reason === "missing" ? "auth_required" : "auth_invalid";
  return new Response(
    JSON.stringify({ error: code, detail: err.message }),
    {
      status: 401,
      headers: {
        "Content-Type": "application/json",
        "WWW-Authenticate": 'Bearer realm="vocal-api"',
        ...corsHeaders
      }
    }
  );
}

// ---------------------------------------------------------------------------
// Pro entitlement gating
// ---------------------------------------------------------------------------

/** User-visible entitlement snapshot from the `user_entitlements` D1 table. */
export interface ProEntitlement {
  isPro: boolean;
  expiresAt?: number;
  productId?: string;
}

/**
 * Thrown by requirePro when the caller is authenticated but does NOT have an
 * active Pro entitlement. Maps to a 402 Payment Required so the iOS client
 * can route to the paywall.
 *
 * Reasons:
 *   "no_row"  — we have no entitlement record for this user.
 *   "expired" — row exists, was Pro, but `expires_at` is in the past.
 *   "not_pro" — row exists with is_pro = 0 (subscription cancelled / refunded).
 */
export class EntitlementRequiredError extends Error {
  constructor(public readonly reason: "no_row" | "expired" | "not_pro") {
    super(
      reason === "no_row"
        ? "no entitlement on file"
        : reason === "expired"
        ? "entitlement expired"
        : "no active Pro entitlement"
    );
  }
}

/**
 * Hard-required Pro check.
 *
 * 1. Verifies the bearer JWT via `requireUserId` — anonymous tokens count as
 *    valid identity but anon users will not have a Pro row, so this still
 *    yields the right 402 below.
 * 2. Looks up the user's row in `user_entitlements`.
 * 3. Returns the user id + entitlement snapshot when active; otherwise throws
 *    `EntitlementRequiredError`.
 *
 * Why we don't accept `requireUserIdOrMint` here: the soft-mint pattern is
 * designed for "first-touch friction is worse than letting an anon user
 * proceed" flows. A paywalled feature has the opposite trade-off — the
 * client MUST already have logged in / paid before this call, so a missing
 * bearer is a real client error and should 401.
 *
 * If `env.DB` is unbound, we cannot verify entitlement → throw `no_row` so
 * the caller returns 402 (fail closed; never grant Pro just because the DB
 * is missing).
 */
export async function requirePro(
  env: { DB?: D1Database; JWT_SECRET?: string },
  request: Request
): Promise<{ userId: string; entitlement: ProEntitlement }> {
  // 1. Hard-required identity. Bubbles AuthRequiredError to the handler.
  const { userId } = await requireUserId(env, request);

  // 2. Without a DB binding we can't verify — fail closed.
  if (!env.DB) {
    throw new EntitlementRequiredError("no_row");
  }

  // 3. Look up the entitlement.
  let row:
    | { is_pro: number; expires_at: number | null; product_id: string | null }
    | null = null;
  try {
    row = await env.DB.prepare(
      `SELECT is_pro, expires_at, product_id
       FROM user_entitlements
       WHERE user_id = ?1`
    )
      .bind(userId)
      .first<{ is_pro: number; expires_at: number | null; product_id: string | null }>();
  } catch (err) {
    // Schema missing or transient D1 outage. Fail closed — these are not the
    // moments to grant a paid feature for free. Log for observability.
    console.error("requirePro: D1 lookup failed", (err as Error).message);
    throw new EntitlementRequiredError("no_row");
  }

  if (!row) throw new EntitlementRequiredError("no_row");
  if (row.is_pro !== 1) throw new EntitlementRequiredError("not_pro");
  if (row.expires_at != null && row.expires_at <= Date.now()) {
    throw new EntitlementRequiredError("expired");
  }

  return {
    userId,
    entitlement: {
      isPro: true,
      expiresAt: row.expires_at ?? undefined,
      productId: row.product_id ?? undefined
    }
  };
}

/** Helper to build a uniform 402 response from an EntitlementRequiredError.
 *  Mirrors `authErrorResponse` — caller passes its CORS headers. */
export function proRequiredResponse(
  err: EntitlementRequiredError,
  corsHeaders: Record<string, string> = {}
): Response {
  return new Response(
    JSON.stringify({
      error: "pro_required",
      detail: err.message,
      reason: err.reason
    }),
    {
      status: 402,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders
      }
    }
  );
}

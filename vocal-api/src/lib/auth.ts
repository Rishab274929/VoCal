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

import { verifyJWT } from "./jwt";

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

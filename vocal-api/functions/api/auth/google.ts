// POST /api/auth/google
//
// Body: { id_token: string }
// Returns: { user_id, token, expires_at, email?, name?, picture?, is_new_user }
//
// Verifies a Google ID token by hitting Google's tokeninfo endpoint (the
// quick path — no JWKS handling needed). On success, upserts the user
// into D1 keyed by Google `sub`, then issues our own JWT just like
// /api/auth/anonymous.

import { signJWT } from "../../../src/lib/jwt";

interface GoogleAuthBody {
  id_token?: string;
}

interface GoogleTokenInfo {
  iss: string;        // accounts.google.com or https://accounts.google.com
  sub: string;        // unique Google user ID — never reused
  aud: string;        // your Google OAuth client ID
  exp: string;        // token expiry, unix seconds
  email?: string;
  email_verified?: string;
  name?: string;
  picture?: string;
  given_name?: string;
  family_name?: string;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const ALLOWED_ISSUERS = new Set([
  "accounts.google.com",
  "https://accounts.google.com"
]);

const json = (data: unknown, status = 200): Response =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });

interface Env {
  DB?: D1Database;
  JWT_SECRET?: string;
  GOOGLE_CLIENT_ID_IOS?: string;
  GOOGLE_CLIENT_ID_ANDROID?: string;
  GOOGLE_CLIENT_ID_WEB?: string;
}

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: GoogleAuthBody;
  try {
    body = (await request.json()) as GoogleAuthBody;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const idToken = body.id_token?.trim();
  if (!idToken) return json({ error: "id_token required" }, 400);

  // --- Verify with Google ---
  // tokeninfo handles signature verification, expiry, audience, issuer for us.
  // For high-volume prod, switch to JWKS caching — but tokeninfo is fine at
  // moderate scale and is the recommended path for "first integration."
  let info: GoogleTokenInfo;
  try {
    const res = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`
    );
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      return json({ error: `Google rejected the id_token: ${txt.slice(0, 200)}` }, 401);
    }
    info = (await res.json()) as GoogleTokenInfo;
  } catch (err) {
    return json({ error: `Token verification failed: ${(err as Error).message}` }, 502);
  }

  if (!ALLOWED_ISSUERS.has(info.iss)) {
    return json({ error: `Untrusted issuer: ${info.iss}` }, 401);
  }
  if (parseInt(info.exp, 10) * 1000 < Date.now()) {
    return json({ error: "id_token expired" }, 401);
  }

  // Audience must match one of our configured client IDs (iOS, Android, web).
  const allowedAudiences = [
    env.GOOGLE_CLIENT_ID_IOS,
    env.GOOGLE_CLIENT_ID_ANDROID,
    env.GOOGLE_CLIENT_ID_WEB
  ].filter((s): s is string => typeof s === "string" && s.length > 0);
  if (allowedAudiences.length > 0 && !allowedAudiences.includes(info.aud)) {
    return json({ error: `Untrusted audience: ${info.aud}` }, 401);
  }

  // --- Upsert into D1 ---
  const userId = `google_${info.sub}`;
  const now = Date.now();
  let isNewUser = false;
  if (env.DB) {
    try {
      const existing = await env.DB
        .prepare("SELECT id FROM users WHERE id = ?1")
        .bind(userId).first();
      isNewUser = !existing;
      await env.DB
        .prepare(
          `INSERT INTO users (id, display_name, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?3)
           ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, updated_at = ?3`
        )
        .bind(userId, info.name ?? info.given_name ?? "Friend", now)
        .run();
    } catch {
      // DB failure is non-fatal — the JWT we issue is still valid.
    }
  }

  // --- Issue our JWT ---
  // Longer-lived than anonymous (7 days) since the user has a real identity.
  const expiresAt = now + 7 * 24 * 60 * 60 * 1000;
  const secret = env.JWT_SECRET || "vocal-dev-secret-rotate-in-prod";
  const token = await signJWT(
    { sub: userId, provider: "google", email: info.email, google_sub: info.sub },
    secret,
    expiresAt
  );

  return json({
    user_id: userId,
    token,
    expires_at: expiresAt,
    email: info.email,
    name: info.name,
    picture: info.picture,
    is_new_user: isNewUser
  });
};

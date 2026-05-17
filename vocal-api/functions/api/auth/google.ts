// POST /api/auth/google
//
// Body: { authorization_code, code_verifier, redirect_uri } from the iOS
// OAuth code+PKCE flow. For compatibility with older clients we also accept
// { id_token }, then validate it the same way.
// Returns: { user_id, token, expires_at, email?, name?, picture?, is_new_user }
//
// Verifies a Google ID token by hitting Google's tokeninfo endpoint (the
// quick path — no JWKS handling needed). On success, upserts the user
// into D1 keyed by Google `sub`, then issues our own JWT just like
// /api/auth/anonymous.

import { signJWT } from "../../../src/lib/jwt";
import { mergeAnonymousData } from "../../../src/lib/identityMerge";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

interface GoogleAuthBody {
  id_token?: string;
  authorization_code?: string;
  code_verifier?: string;
  redirect_uri?: string;
  nonce?: string;
  /** Optional: hand off an anonymous session's rows to this new identity. */
  link_anonymous_user_id?: string;
  link_anonymous_token?: string;
}

interface GoogleTokenResponse {
  id_token?: string;
  error?: string;
  error_description?: string;
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

interface GoogleIDPayload {
  nonce?: string;
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
  FOOD_KV?: KVNamespace;
}

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  // Rate limit auth endpoints by IP (the request isn't authenticated yet).
  // 20/min/IP is generous enough that a real user retrying a failed flow
  // never hits it; tight enough to block credential-stuffing volume.
  const rl = await checkRateLimit(env, request, "auth/google", 20);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);
  let body: GoogleAuthBody;
  try {
    body = (await request.json()) as GoogleAuthBody;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  let idToken = body.id_token?.trim();
  const authCode = body.authorization_code?.trim();
  let usedAuthorizationCodeFlow = false;
  if (!idToken) {
    if (!authCode) return json({ error: "authorization_code or id_token required" }, 400);
    const codeVerifier = body.code_verifier?.trim();
    const redirectUri = body.redirect_uri?.trim();
    if (!codeVerifier) return json({ error: "code_verifier required" }, 400);
    if (!redirectUri) return json({ error: "redirect_uri required" }, 400);

    // Native installed-app OAuth code exchange. iOS public clients do not use a
    // client secret; the PKCE verifier is the proof that binds this request to
    // the authorization request the app launched.
    const clientId = env.GOOGLE_CLIENT_ID_IOS?.trim();
    if (!clientId) {
      console.error("google auth: refusing code exchange — GOOGLE_CLIENT_ID_IOS not configured");
      return json({ error: "Server not configured for Google sign-in" }, 503);
    }
    let tokenBody: GoogleTokenResponse;
    try {
      const res = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: clientId,
          code: authCode,
          code_verifier: codeVerifier,
          grant_type: "authorization_code",
          redirect_uri: redirectUri
        })
      });
      tokenBody = (await res.json().catch(() => ({}))) as GoogleTokenResponse;
      if (!res.ok) {
        const detail = tokenBody.error_description || tokenBody.error || `HTTP ${res.status}`;
        return json({ error: `Google rejected authorization_code: ${detail.slice(0, 200)}` }, 401);
      }
    } catch (err) {
      return json({ error: `Google code exchange failed: ${(err as Error).message}` }, 502);
    }
    idToken = tokenBody.id_token?.trim();
    if (!idToken) return json({ error: "Google token response missing id_token" }, 401);
    usedAuthorizationCodeFlow = true;
  }

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

  if (!info.iss || !ALLOWED_ISSUERS.has(info.iss)) {
    return json({ error: "Untrusted issuer" }, 401);
  }
  // Google's tokeninfo returns exp as a numeric string. Parse strictly —
  // an undefined/NaN value previously passed the comparison (`NaN < now`
  // is false), which would let an expired-or-malformed token through.
  const expSec = info.exp ? parseInt(info.exp, 10) : NaN;
  if (!isFinite(expSec) || expSec <= 0 || expSec * 1000 < Date.now()) {
    return json({ error: "id_token expired or missing exp" }, 401);
  }
  if (!info.sub || typeof info.sub !== "string") {
    return json({ error: "id_token missing sub" }, 401);
  }
  const expectedNonce = body.nonce?.trim();
  if (expectedNonce) {
    const payload = decodeIDTokenPayload(idToken);
    if (payload?.nonce && !constantTimeEqual(payload.nonce, expectedNonce)) {
      return json({ error: "nonce mismatch" }, 401);
    }
    // Google's installed-app code+PKCE flow is bound by the verifier and may
    // omit `nonce` from the token endpoint's ID token. Keep requiring nonce
    // only for direct id_token clients, where the app itself received the
    // token from the browser redirect.
    if (!payload?.nonce && !usedAuthorizationCodeFlow) {
      return json({ error: "nonce mismatch" }, 401);
    }
  }
  // Reject unverified emails — without this an attacker can use a fresh
  // Google account with an unverified email to claim someone else's address
  // for the side-channel join (display name etc.).
  if (info.email && info.email_verified !== "true" && info.email_verified !== undefined) {
    // email_verified is "true"/"false" string per Google docs. Only reject
    // when it's explicitly "false".
    if (info.email_verified === "false") {
      return json({ error: "Email not verified by Google" }, 401);
    }
  }

  // Audience must match one of our configured client IDs (iOS, Android, web).
  // SECURITY: if NONE are configured, refuse to issue tokens — otherwise an
  // attacker with any Google ID token (issued for any third-party app) can
  // mint a VoCal session.
  const allowedAudiences = [
    env.GOOGLE_CLIENT_ID_IOS,
    env.GOOGLE_CLIENT_ID_ANDROID,
    env.GOOGLE_CLIENT_ID_WEB
  ].filter((s): s is string => typeof s === "string" && s.length > 0);
  if (allowedAudiences.length === 0) {
    console.error("google auth: refusing to verify — no GOOGLE_CLIENT_ID_* configured");
    return json({ error: "Server not configured for Google sign-in" }, 503);
  }
  if (!info.aud || !allowedAudiences.includes(info.aud)) {
    return json({ error: "Untrusted audience" }, 401);
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
  // SECURITY: refuse to fall back to a hardcoded default in production. If
  // the deploy forgets JWT_SECRET, anyone who has read this source can mint
  // valid tokens for any user. We still keep a recognizable dev default for
  // local `wrangler pages dev` where there's no DB attached.
  let secret = env.JWT_SECRET;
  if (!secret || secret.length < 16) {
    // No DB binding ≈ local dev; allow the default. Otherwise refuse.
    if (env.DB) {
      console.error("auth/google: refusing to sign — JWT_SECRET missing or weak");
      return json({ error: "Server auth misconfigured" }, 503);
    }
    secret = "vocal-dev-secret-rotate-in-prod";
  }
  const token = await signJWT(
    { sub: userId, provider: "google", email: info.email, google_sub: info.sub },
    secret,
    expiresAt
  );

  // --- Optional anonymous-data merge --------------------------------------
  // Mirrors /api/auth/apple. We do this AFTER the upsert so the meals/body_metrics
  // FKs point at a row that actually exists.
  let mergedRows = 0;
  let mergeErrors: string[] = [];
  if (body.link_anonymous_user_id && body.link_anonymous_token) {
    const merge = await mergeAnonymousData(
      { DB: env.DB, JWT_SECRET: env.JWT_SECRET },
      body.link_anonymous_user_id,
      body.link_anonymous_token,
      userId
    );
    mergedRows = merge.merged;
    mergeErrors = merge.errors;
    console.log("[merge] anon=%s -> new=%s rows=%d errors=%s",
      body.link_anonymous_user_id, userId, merge.merged, merge.errors.join(";") || "none");
  }

  return json({
    user_id: userId,
    token,
    expires_at: expiresAt,
    email: info.email,
    name: info.name,
    picture: info.picture,
    is_new_user: isNewUser,
    merged_rows: mergedRows,
    ...(mergeErrors.length ? { merge_errors: mergeErrors } : {})
  });
};

function decodeIDTokenPayload(idToken: string): GoogleIDPayload | null {
  const parts = idToken.split(".");
  if (parts.length < 2) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/") + "===".slice((parts[1].length + 3) % 4);
    return JSON.parse(new TextDecoder().decode(base64Decode(padded))) as GoogleIDPayload;
  } catch {
    return null;
  }
}

function base64Decode(input: string): Uint8Array {
  const raw = atob(input);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

function constantTimeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aa = enc.encode(a);
  const bb = enc.encode(b);
  let diff = aa.length ^ bb.length;
  const len = Math.max(aa.length, bb.length);
  for (let i = 0; i < len; i++) {
    diff |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  }
  return diff === 0;
}

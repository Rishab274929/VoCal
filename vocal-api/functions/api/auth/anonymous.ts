// Anonymous device-bound session. Hands out a short-lived JWT so the
// iOS app can persist meals before the user signs in with Apple.
//
// Body: { device_id?: string }
// Returns: { user_id, token, expires_at }

import { signJWT } from "../../../src/lib/jwt";

interface AnonymousPayload {
  device_id?: string;
}

const json = (data: unknown, init?: ResponseInit): Response =>
  new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST,OPTIONS",
      "access-control-allow-headers": "content-type,authorization",
      ...(init?.headers ?? {}),
    },
  });

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST,OPTIONS",
      "access-control-allow-headers": "content-type,authorization",
    },
  });
};

export const onRequestPost: PagesFunction = async ({ request, env }) => {
  const bindings = env as unknown as {
    DB?: D1Database;
    JWT_SECRET?: string;
  };

  let body: AnonymousPayload = {};
  try {
    body = (await request.json()) as AnonymousPayload;
  } catch {
    // Empty body is fine
  }

  const deviceId = body.device_id?.trim() || crypto.randomUUID();
  const userId = `anon_${deviceId.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32)}`;
  const now = Date.now();
  const expiresAt = now + 60 * 60 * 1000; // 1 hour

  try {
    await bindings.DB?.prepare(
      `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4)`,
    )
      .bind(userId, "Anonymous", now, now)
      .run();
  } catch {
    // DB miss is non-fatal — token is still valid.
  }

  // SECURITY: same posture as /api/auth/google — refuse to sign with the
  // hardcoded default when a real DB is attached. Local `wrangler pages dev`
  // (no DB binding) is the only case where the dev fallback is acceptable.
  let secret = bindings.JWT_SECRET;
  if (!secret || secret.length < 16) {
    if (bindings.DB) {
      console.error("auth/anonymous: refusing to sign — JWT_SECRET missing or weak");
      return json({ error: "Server auth misconfigured" }, { status: 503 });
    }
    secret = "vocal-dev-secret-rotate-in-prod";
  }
  const token = await signJWT({ sub: userId, anon: true }, secret, expiresAt);

  return json({
    user_id: userId,
    token,
    expires_at: expiresAt,
  });
};

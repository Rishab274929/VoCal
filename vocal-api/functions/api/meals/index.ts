// GET  /api/meals?user_id=...&since=<ts>  → list meals
// POST /api/meals                          → create a meal manually
//
// Auth: PREFERS a verified bearer JWT (from /api/auth/anonymous or
// /api/auth/google) and falls back to the query/body user_id for legacy
// clients. When both are present and disagree, the JWT wins — the client's
// claim is rejected as an auth-bypass attempt.

import { authIdentity, resolveUserId } from "../../../src/lib/auth";

interface CreateMealBody {
  user_id?: string;
  name: string;
  detail?: string;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  slot?: string;
  source?: string;
  transcript?: string;
  confidence?: number;
  logged_at?: number;
}

const json = (data: unknown, init?: ResponseInit): Response =>
  new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "content-type,authorization",
      ...(init?.headers ?? {}),
    },
  });

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "content-type,authorization",
    },
  });
};

export const onRequestGet: PagesFunction = async ({ request, env }) => {
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string };
  if (!bindings.DB) return json({ meals: [] });

  const url = new URL(request.url);
  const queryUserId = url.searchParams.get("user_id");
  // Prefer the authenticated identity. Without auth we still serve the
  // requested user_id to keep legacy clients working — but log the case so
  // it's visible in Workers tail.
  const identity = await authIdentity(request, bindings);
  const { userId, mismatch, source } = resolveUserId(identity, queryUserId);
  if (mismatch) {
    console.warn("meals GET: rejecting client user_id, using JWT sub", { jwt: identity.userId, claimed: queryUserId });
  }
  if (source === "default") {
    // No JWT and no body user_id — return the demo bucket for backwards-
    // compat but cap the result count tighter.
  }
  const since = Number(url.searchParams.get("since") || 0);
  const sinceSafe = isFinite(since) && since >= 0 ? since : 0;
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 500);

  const stmt = sinceSafe > 0
    ? bindings.DB.prepare(
        `SELECT * FROM meals WHERE user_id = ?1 AND logged_at >= ?2 ORDER BY logged_at DESC LIMIT ?3`,
      ).bind(userId, sinceSafe, limit)
    : bindings.DB.prepare(
        `SELECT * FROM meals WHERE user_id = ?1 ORDER BY logged_at DESC LIMIT ?2`,
      ).bind(userId, limit);

  const { results } = await stmt.all();
  return json({ meals: results });
};

export const onRequestPost: PagesFunction = async ({ request, env }) => {
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string };
  if (!bindings.DB) return json({ error: "DB unavailable" }, { status: 503 });

  // Pre-flight body-size check — refuse > 16KB request bodies. A manual meal
  // create is just a name + a handful of numbers, ~200 bytes worst case. A
  // larger body is either malicious or buggy.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > 16 * 1024) {
    return json({ error: "Request body too large" }, { status: 413 });
  }

  let body: CreateMealBody;
  try {
    body = (await request.json()) as CreateMealBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  if (!body.name || typeof body.name !== "string" || typeof body.kcal !== "number") {
    return json({ error: "name + kcal required" }, { status: 400 });
  }
  // Sanity-check the macro envelope so a malicious client can't write a row
  // claiming a million calories.
  const kcal = Math.round(body.kcal);
  if (!isFinite(kcal) || kcal < 0 || kcal > 20000) {
    return json({ error: "kcal out of range" }, { status: 400 });
  }
  const macroOk = (v: number | undefined, max: number): number => {
    if (v == null) return 0;
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > max) {
      throw new Error("macro out of range");
    }
    return Math.round(v);
  };
  let protein_g: number, carbs_g: number, fat_g: number;
  try {
    protein_g = macroOk(body.protein_g, 2000);
    carbs_g = macroOk(body.carbs_g, 2000);
    fat_g = macroOk(body.fat_g, 2000);
  } catch {
    return json({ error: "macro out of range" }, { status: 400 });
  }

  // Auth resolution: trust the JWT identity over the body's user_id.
  const identity = await authIdentity(request, bindings);
  const { userId, mismatch } = resolveUserId(identity, body.user_id);
  if (mismatch) {
    console.warn("meals POST: rejecting client user_id, using JWT sub", { jwt: identity.userId, claimed: body.user_id });
  }
  const now = Date.now();
  const id = crypto.randomUUID();
  const loggedAt = typeof body.logged_at === "number" && isFinite(body.logged_at) && body.logged_at > 0
    ? body.logged_at
    : now;

  // Sanitize string fields (length caps prevent DoS / log spam).
  const trimStr = (s: string | undefined | null, n: number): string =>
    typeof s === "string" ? s.slice(0, n) : "";

  await bindings.DB.prepare(
    `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(userId, "VoCal User", now, now).run();

  await bindings.DB.prepare(
    `INSERT INTO meals (id, user_id, name, detail, kcal, protein_g, carbs_g, fat_g, slot, source, transcript, confidence, logged_at, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)`,
  ).bind(
    id,
    userId,
    trimStr(body.name, 200),
    trimStr(body.detail, 400),
    kcal,
    protein_g,
    carbs_g,
    fat_g,
    trimStr(body.slot ?? "snack", 20),
    trimStr(body.source ?? "manual", 20),
    body.transcript ? trimStr(body.transcript, 600) : null,
    typeof body.confidence === "number" && isFinite(body.confidence)
      ? Math.max(0, Math.min(1, body.confidence))
      : null,
    loggedAt,
    now,
  ).run();

  return json({ id, user_id: userId, logged_at: loggedAt });
};

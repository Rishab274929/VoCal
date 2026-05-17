// GET  /api/meals?since=<ts>  → list this user's meals
// POST /api/meals              → create a meal manually
//
// Auth: HARD-REQUIRED bearer JWT. We previously accepted a body/query
// `user_id` as a soft fallback; that path is gone now that the iOS and
// Flutter clients both ship bearer-token auth (see /api/auth/anonymous +
// /api/auth/google). Old clients that send `user_id` will get a 401 — a
// deliberate cutover.

import { AuthRequiredError, authErrorResponse, requireUserId } from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

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
  // Optional micros — persisted to the meals table when present.
  sodium_mg?: number;
  fiber_g?: number;
  sugar_g?: number;
  calcium_mg?: number;
  iron_mg?: number;
  vitamin_c_mg?: number;
  potassium_mg?: number;
}

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type,authorization"
};

const json = (data: unknown, init?: ResponseInit): Response =>
  new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...CORS,
      ...(init?.headers ?? {}),
    },
  });

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, {
    status: 204,
    headers: CORS,
  });
};

export const onRequestGet: PagesFunction = async ({ request, env }) => {
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  const rl = await checkRateLimit(bindings, request, "meals/list", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // No DB → empty list. Don't 503 GETs; an empty meals list is a valid
  // (if uncommon) state for a brand-new user.
  if (!bindings.DB) return json({ meals: [] });

  const url = new URL(request.url);
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
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  const rl = await checkRateLimit(bindings, request, "meals/create", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

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

  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request, body.user_id));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
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

  // Optional micros: same bounds as foodParser.pickMicros. Returns null
  // when missing/out-of-range so we bind a SQL NULL.
  const intMicro = (v: unknown, max: number): number | null => {
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > max) return null;
    return Math.round(v);
  };
  const floatMicro = (v: unknown, max: number): number | null => {
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > max) return null;
    return Math.round(v * 10) / 10;
  };
  const sodium_mg     = intMicro(body.sodium_mg, 10000);
  const fiber_g       = intMicro(body.fiber_g, 100);
  const sugar_g       = intMicro(body.sugar_g, 300);
  const calcium_mg    = intMicro(body.calcium_mg, 3000);
  const iron_mg       = floatMicro(body.iron_mg, 50);
  const vitamin_c_mg  = floatMicro(body.vitamin_c_mg, 2000);
  const potassium_mg  = intMicro(body.potassium_mg, 8000);

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
    `INSERT INTO meals (id, user_id, name, detail, kcal, protein_g, carbs_g, fat_g, slot, source, transcript, confidence, logged_at, created_at,
                        sodium_mg, fiber_g, sugar_g, calcium_mg, iron_mg, vitamin_c_mg, potassium_mg)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14,
             ?15, ?16, ?17, ?18, ?19, ?20, ?21)`,
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
    sodium_mg,
    fiber_g,
    sugar_g,
    calcium_mg,
    iron_mg,
    vitamin_c_mg,
    potassium_mg,
  ).run();

  return json({ id, user_id: userId, logged_at: loggedAt });
};

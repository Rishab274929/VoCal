// PATCH  /api/meals/:id  → partial update of a meal row
// DELETE /api/meals/:id  → delete a meal row
//
// Both REQUIRE a verified Bearer JWT (no body.user_id fallback). The meal
// must belong to the JWT's user_id — we check ownership before any write
// so a guessable UUID can't be used to mutate another user's row.
//
// Rate limit: 30/min/identity, shared label so a malicious caller can't
// stack PATCH + DELETE buckets to double their effective limit.

import { AuthRequiredError, authErrorResponse, requireUserId } from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

interface PatchBody {
  name?: string;
  detail?: string;
  kcal?: number;
  protein_g?: number;
  carbs_g?: number;
  fat_g?: number;
  slot?: string;
  source?: string;
  transcript?: string;
  // Optional micros — additive partial update.
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
  "access-control-allow-methods": "PATCH,DELETE,OPTIONS",
  "access-control-allow-headers": "content-type,authorization"
};

const json = (data: unknown, init?: ResponseInit): Response =>
  new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...CORS,
      ...(init?.headers ?? {})
    }
  });

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, { status: 204, headers: CORS });
};

interface Params { id?: string; }

function readId(params: Params): string | null {
  const id = (params.id ?? "").toString();
  // UUIDs are the only meal IDs we mint, but accept any opaque token
  // up to 64 chars composed of url-safe characters. The DB lookup is
  // parameterized, so this is just defense-in-depth + length cap.
  if (!id || id.length > 64 || !/^[A-Za-z0-9_.:-]+$/.test(id)) return null;
  return id;
}

export const onRequestPatch: PagesFunction = async ({ request, env, params }) => {
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  const rl = await checkRateLimit(bindings, request, "meals/mutate", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  const id = readId(params as Params);
  if (!id) return json({ error: "invalid meal id" }, { status: 400 });

  if (!bindings.DB) return json({ error: "DB unavailable" }, { status: 503 });

  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // Body-size cap — partial update is tiny.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > 16 * 1024) {
    return json({ error: "Request body too large" }, { status: 413 });
  }

  let body: PatchBody;
  try {
    body = (await request.json()) as PatchBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  // Ownership check FIRST — refuse to leak existence with a 404 vs 403
  // distinction. Either it's yours and you can patch it, or you get a 404.
  const existing = await bindings.DB.prepare(
    `SELECT id FROM meals WHERE id = ?1 AND user_id = ?2`
  ).bind(id, userId).first<{ id: string }>();
  if (!existing) return json({ error: "not found" }, { status: 404 });

  // Build a dynamic SET clause from whichever fields the caller supplied.
  // Skip undefined keys so we genuinely do a partial update.
  const sets: string[] = [];
  const binds: unknown[] = [];
  const trimStr = (s: string, n: number): string => s.slice(0, n);

  const pushIfString = (col: string, v: unknown, max: number): void => {
    if (typeof v !== "string") return;
    sets.push(`${col} = ?${sets.length + 1}`);
    binds.push(trimStr(v, max));
  };
  const pushIfIntInRange = (col: string, v: unknown, max: number): boolean => {
    if (v == null) return true; // not supplied — fine
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > max) return false;
    sets.push(`${col} = ?${sets.length + 1}`);
    binds.push(Math.round(v));
    return true;
  };
  const pushIfFloatInRange = (col: string, v: unknown, max: number): boolean => {
    if (v == null) return true;
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > max) return false;
    sets.push(`${col} = ?${sets.length + 1}`);
    binds.push(Math.round(v * 10) / 10);
    return true;
  };

  pushIfString("name", body.name, 200);
  pushIfString("detail", body.detail, 400);
  pushIfString("slot", body.slot, 20);
  pushIfString("source", body.source, 20);
  pushIfString("transcript", body.transcript, 600);

  if (!pushIfIntInRange("kcal", body.kcal, 20000))         return json({ error: "kcal out of range" }, { status: 400 });
  if (!pushIfIntInRange("protein_g", body.protein_g, 2000)) return json({ error: "protein_g out of range" }, { status: 400 });
  if (!pushIfIntInRange("carbs_g",   body.carbs_g,   2000)) return json({ error: "carbs_g out of range" },   { status: 400 });
  if (!pushIfIntInRange("fat_g",     body.fat_g,     2000)) return json({ error: "fat_g out of range" },     { status: 400 });

  if (!pushIfIntInRange("sodium_mg",    body.sodium_mg,    10000)) return json({ error: "sodium_mg out of range" },    { status: 400 });
  if (!pushIfIntInRange("fiber_g",      body.fiber_g,      100))   return json({ error: "fiber_g out of range" },      { status: 400 });
  if (!pushIfIntInRange("sugar_g",      body.sugar_g,      300))   return json({ error: "sugar_g out of range" },      { status: 400 });
  if (!pushIfIntInRange("calcium_mg",   body.calcium_mg,   3000))  return json({ error: "calcium_mg out of range" },   { status: 400 });
  if (!pushIfFloatInRange("iron_mg",      body.iron_mg,      50))    return json({ error: "iron_mg out of range" },      { status: 400 });
  if (!pushIfFloatInRange("vitamin_c_mg", body.vitamin_c_mg, 2000))  return json({ error: "vitamin_c_mg out of range" }, { status: 400 });
  if (!pushIfIntInRange("potassium_mg", body.potassium_mg, 8000))  return json({ error: "potassium_mg out of range" }, { status: 400 });

  if (sets.length === 0) {
    return json({ error: "no fields to update" }, { status: 400 });
  }

  binds.push(id, userId);
  const sql = `UPDATE meals SET ${sets.join(", ")} WHERE id = ?${sets.length + 1} AND user_id = ?${sets.length + 2}`;
  await bindings.DB.prepare(sql).bind(...binds).run();

  return json({ id, updated: sets.length });
};

export const onRequestDelete: PagesFunction = async ({ request, env, params }) => {
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  const rl = await checkRateLimit(bindings, request, "meals/mutate", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  const id = readId(params as Params);
  if (!id) return json({ error: "invalid meal id" }, { status: 400 });

  if (!bindings.DB) return json({ error: "DB unavailable" }, { status: 503 });

  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // Ownership-scoped delete. If the WHERE matches zero rows we report 404
  // — same shape as the PATCH so an attacker can't probe meal IDs.
  const res = await bindings.DB.prepare(
    `DELETE FROM meals WHERE id = ?1 AND user_id = ?2`
  ).bind(id, userId).run();
  // D1's RunResult exposes .meta.changes on a successful mutation.
  const changes = (res as unknown as { meta?: { changes?: number } }).meta?.changes ?? 0;
  if (changes === 0) return json({ error: "not found" }, { status: 404 });
  return json({ id, deleted: true });
};

// POST /api/bodyfat — body-fat estimate.
//
// Body: { user_id, weight_lb, height_in, sex, front_r2_key?, side_r2_key? }
// Returns: { body_fat_pct, confidence, notes }
//
// Heuristic today (BMI-derived with sex offset). Swaps to a vision LLM
// call against R2-stored photos once a vision provider is set.
//
// Auth: PREFERS a verified bearer JWT and falls back to body.user_id for
// legacy clients. Same pattern as /api/meals.

import { authIdentity, resolveUserId } from "../../../src/lib/auth";

interface BFBody {
  user_id?: string;
  weight_lb: number;
  height_in: number;
  sex?: string;
  front_r2_key?: string;
  side_r2_key?: string;
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
  const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string };

  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > 16 * 1024) {
    return json({ error: "Request body too large" }, { status: 413 });
  }

  let body: BFBody;
  try {
    body = (await request.json()) as BFBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  // Validate numeric inputs: a malicious client could send negative or NaN
  // values to skew the heuristic into nonsense.
  const weight_lb = Number(body.weight_lb);
  const height_in = Number(body.height_in);
  if (!isFinite(weight_lb) || weight_lb <= 0 || weight_lb > 2000) {
    return json({ error: "weight_lb out of range" }, { status: 400 });
  }
  if (!isFinite(height_in) || height_in <= 0 || height_in > 120) {
    return json({ error: "height_in out of range" }, { status: 400 });
  }

  // BMI in metric
  const kg = weight_lb * 0.4536;
  const m = height_in * 0.0254;
  const bmi = m > 0 ? kg / (m * m) : 22;

  // Heuristic baseline: female ~22, male ~16, plus BMI slope.
  const baseline = body.sex === "f" ? 22.0 : 16.0;
  let pct = baseline + (bmi - 22) * 1.6;
  pct = Math.max(7.5, Math.min(40, pct));
  const confidence = body.front_r2_key && body.side_r2_key ? 0.78 : 0.62;

  // Persist as a body_metrics row if we have a user
  try {
    const identity = await authIdentity(request, bindings);
    const { userId, mismatch } = resolveUserId(identity, body.user_id);
    if (mismatch) {
      console.warn("bodyfat: rejecting client user_id, using JWT sub", { jwt: identity.userId, claimed: body.user_id });
    }
    const now = Date.now();
    if (bindings.DB) {
      await bindings.DB.prepare(
        `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`,
      ).bind(userId, "VoCal User", now, now).run();

      await bindings.DB.prepare(
        `INSERT INTO body_metrics (id, user_id, weight_lb, body_fat_pct, bf_confidence, front_r2_key, side_r2_key, measured_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
      ).bind(
        crypto.randomUUID(),
        userId,
        weight_lb,
        pct,
        confidence,
        body.front_r2_key ? body.front_r2_key.slice(0, 200) : null,
        body.side_r2_key ? body.side_r2_key.slice(0, 200) : null,
        now,
      ).run();
    }
  } catch (err) {
    console.error("bodyfat: DB write failed", (err as Error).message);
    // continue — return result anyway
  }

  return json({
    body_fat_pct: Number(pct.toFixed(1)),
    confidence,
    notes: "Heuristic estimate from BMI + sex; vision model lands when provider key is set.",
  });
};

// POST /api/bodyfat — body-fat estimate.
//
// Body: { user_id, weight_lb, height_in, sex, front_r2_key?, side_r2_key? }
// Returns: { body_fat_pct, confidence, notes }
//
// Heuristic today (BMI-derived with sex offset). Swaps to a vision LLM
// call against R2-stored photos once a vision provider is set.

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
  const bindings = env as unknown as { DB?: D1Database };
  let body: BFBody;
  try {
    body = (await request.json()) as BFBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  if (!body.weight_lb || !body.height_in) {
    return json({ error: "weight_lb + height_in required" }, { status: 400 });
  }

  // BMI in metric
  const kg = body.weight_lb * 0.4536;
  const m = body.height_in * 0.0254;
  const bmi = m > 0 ? kg / (m * m) : 22;

  // Heuristic baseline: female ~22, male ~16, plus BMI slope.
  const baseline = body.sex === "f" ? 22.0 : 16.0;
  let pct = baseline + (bmi - 22) * 1.6;
  pct = Math.max(7.5, Math.min(40, pct));
  const confidence = body.front_r2_key && body.side_r2_key ? 0.78 : 0.62;

  // Persist as a body_metrics row if we have a user
  try {
    const userId = body.user_id?.trim() || "demo-user";
    const now = Date.now();
    if (bindings.DB) {
      await bindings.DB.prepare(
        `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`,
      ).bind(userId, "Demo User", now, now).run();

      await bindings.DB.prepare(
        `INSERT INTO body_metrics (id, user_id, weight_lb, body_fat_pct, bf_confidence, front_r2_key, side_r2_key, measured_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
      ).bind(
        crypto.randomUUID(),
        userId,
        body.weight_lb,
        pct,
        confidence,
        body.front_r2_key ?? null,
        body.side_r2_key ?? null,
        now,
      ).run();
    }
  } catch {
    // ignore — return result anyway
  }

  return json({
    body_fat_pct: Number(pct.toFixed(1)),
    confidence,
    notes: "Heuristic estimate from BMI + sex; vision model lands when provider key is set.",
  });
};

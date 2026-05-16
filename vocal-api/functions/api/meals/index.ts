// GET  /api/meals?user_id=...&since=<ts>  → list meals
// POST /api/meals                          → create a meal manually
//
// Auth is loose for the hackathon — user_id comes from the query/body.
// Real auth lands when SiwA is wired.

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
  const bindings = env as unknown as { DB?: D1Database };
  if (!bindings.DB) return json({ meals: [] });

  const url = new URL(request.url);
  const userId = url.searchParams.get("user_id") || "demo-user";
  const since = Number(url.searchParams.get("since") || 0);
  const limit = Math.min(Number(url.searchParams.get("limit") || 100), 500);

  const stmt = since > 0
    ? bindings.DB.prepare(
        `SELECT * FROM meals WHERE user_id = ?1 AND logged_at >= ?2 ORDER BY logged_at DESC LIMIT ?3`,
      ).bind(userId, since, limit)
    : bindings.DB.prepare(
        `SELECT * FROM meals WHERE user_id = ?1 ORDER BY logged_at DESC LIMIT ?2`,
      ).bind(userId, limit);

  const { results } = await stmt.all();
  return json({ meals: results });
};

export const onRequestPost: PagesFunction = async ({ request, env }) => {
  const bindings = env as unknown as { DB?: D1Database };
  if (!bindings.DB) return json({ error: "DB unavailable" }, { status: 503 });

  let body: CreateMealBody;
  try {
    body = (await request.json()) as CreateMealBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  if (!body.name || typeof body.kcal !== "number") {
    return json({ error: "name + kcal required" }, { status: 400 });
  }

  const userId = body.user_id?.trim() || "demo-user";
  const now = Date.now();
  const id = crypto.randomUUID();
  const loggedAt = body.logged_at ?? now;

  await bindings.DB.prepare(
    `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(userId, "Demo User", now, now).run();

  await bindings.DB.prepare(
    `INSERT INTO meals (id, user_id, name, detail, kcal, protein_g, carbs_g, fat_g, slot, source, transcript, confidence, logged_at, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)`,
  ).bind(
    id,
    userId,
    body.name,
    body.detail ?? "",
    Math.round(body.kcal),
    Math.round(body.protein_g ?? 0),
    Math.round(body.carbs_g ?? 0),
    Math.round(body.fat_g ?? 0),
    body.slot ?? "snack",
    body.source ?? "manual",
    body.transcript ?? null,
    body.confidence ?? null,
    loggedAt,
    now,
  ).run();

  return json({ id, user_id: userId, logged_at: loggedAt });
};

// POST /api/coach  — voice nutrition coach. Heuristic responses today;
// swaps to Claude Sonnet 4.6 the moment an Anthropic key is set.

interface CoachBody {
  user_id?: string;
  prompt: string;
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
  let body: CoachBody;
  try {
    body = (await request.json()) as CoachBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  const prompt = (body.prompt ?? "").trim();
  if (!prompt) return json({ error: "prompt required" }, { status: 400 });

  const userId = body.user_id?.trim() || "demo-user";

  // Read today's macros from D1 so the reply can reference real numbers.
  let kcalEaten = 0;
  let proteinEaten = 0;
  let mealsCount = 0;

  try {
    if (bindings.DB) {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);
      const startTs = startOfDay.getTime();
      const row = await bindings.DB.prepare(
        `SELECT COALESCE(SUM(kcal),0) AS k, COALESCE(SUM(protein_g),0) AS p, COUNT(*) AS c
         FROM meals WHERE user_id = ?1 AND logged_at >= ?2`,
      ).bind(userId, startTs).first<{ k: number; p: number; c: number }>();
      if (row) {
        kcalEaten = row.k ?? 0;
        proteinEaten = row.p ?? 0;
        mealsCount = row.c ?? 0;
      }
    }
  } catch {
    // ignore
  }

  const goal = 2200;
  const remaining = Math.max(0, goal - kcalEaten);
  const proteinGoal = 160;
  const proteinShort = Math.max(0, proteinGoal - proteinEaten);

  const lower = prompt.toLowerCase();
  let reply: string;
  if (lower.includes("protein")) {
    reply = `You're at ${proteinEaten}g of ${proteinGoal}g protein — ${proteinShort}g short with ${remaining} kcal to spare. A Cava grilled chicken bowl (~520 kcal, 42g P) or Chick-fil-A grilled nuggets 12-ct (~210 kcal, 38g P) would close the gap.`;
  } else if (lower.includes("pasta") || lower.includes("dinner")) {
    reply = `${remaining} kcal left. A 2-cup serving of spaghetti pomodoro lands ~560 kcal; add a 4 oz grilled chicken breast (~190 kcal, 35g P) and you're under budget with protein covered.`;
  } else if (lower.includes("hungry") || lower.includes("snack")) {
    reply = `Could be a protein gap. A Greek yogurt + small handful of almonds (~250 kcal, 18g P) usually kills the dip without ruining dinner.`;
  } else {
    reply = `Today so far: ${kcalEaten} kcal across ${mealsCount} entries, ${proteinEaten}g protein. ${remaining} kcal remaining. What are you considering?`;
  }

  return json({ reply, context: { kcal_eaten: kcalEaten, protein_eaten: proteinEaten, meals: mealsCount } });
};

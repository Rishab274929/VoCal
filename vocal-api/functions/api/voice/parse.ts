// POST /api/voice/parse
//
// Body: { transcript: string, follow_up_answer?: string | null }
// Response: VoiceParseResponse (see ../../../src/types.ts)
//
// Resolution flow lives in src/ai/foodParser.ts. This handler is intentionally
// thin: it validates input, calls the parser, optionally writes to D1, and
// returns JSON with appropriate CORS headers for the iOS client.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env, VoiceParsePayload } from "../../../src/types";
import { parseTranscript } from "../../../src/ai/foodParser";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let payload: VoiceParsePayload;
  try {
    payload = (await request.json()) as VoiceParsePayload;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!payload || typeof payload.transcript !== "string") {
    return json({ error: "Missing transcript" }, 400);
  }
  if (payload.transcript.length > 600) {
    return json({ error: "Transcript too long (max 600 chars)" }, 413);
  }

  const result = await parseTranscript(
    payload.transcript,
    payload.follow_up_answer ?? null,
    env
  );

  // Optional: persist meal log to D1. Failures here must not break the parse
  // response — logging is best-effort and offline-tolerant.
  if (env.DB && result.meal) {
    try {
      await env.DB
        .prepare(
          "INSERT INTO meals (id, name, detail, kcal, protein_g, carbs_g, fat_g, slot, source, confidence, transcript, logged_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(
          crypto.randomUUID(),
          result.meal.name,
          result.meal.detail,
          result.meal.kcal,
          result.meal.protein_g,
          result.meal.carbs_g,
          result.meal.fat_g,
          result.meal.slot,
          result.meal.source,
          result.meal.confidence,
          payload.transcript,
          new Date().toISOString()
        )
        .run();
    } catch {
      // swallow — schema may not be migrated yet
    }
  }

  return json(result, 200);
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS }
  });
}

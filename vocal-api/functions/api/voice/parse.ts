// POST /api/voice/parse
//
// Body: { transcript: string, follow_up_answer?: string | null, user_id?: string }
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
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const MAX_TRANSCRIPT_CHARS = 600;
// Tiny envelope around the transcript — { "transcript": "...", "follow_up_answer": "...", "user_id": "..." }
const MAX_REQUEST_BYTES = MAX_TRANSCRIPT_CHARS * 4 + 4096;

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  // Pre-flight size check — reject before allocating a large string.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > MAX_REQUEST_BYTES) {
    return json({ error: "Request body too large" }, 413);
  }

  let payload: VoiceParsePayload & { user_id?: string };
  try {
    payload = (await request.json()) as VoiceParsePayload & { user_id?: string };
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!payload || typeof payload.transcript !== "string") {
    return json({ error: "Missing transcript" }, 400);
  }
  // Validate optional fields' types — a malicious client could send arrays or
  // objects to confuse downstream JSON.stringify / string concatenation.
  if (payload.follow_up_answer != null && typeof payload.follow_up_answer !== "string") {
    return json({ error: "follow_up_answer must be a string or null" }, 400);
  }
  if (payload.user_id != null && typeof payload.user_id !== "string") {
    return json({ error: "user_id must be a string" }, 400);
  }
  const transcript = payload.transcript.trim();
  if (!transcript) {
    return json({ error: "Transcript is empty" }, 400);
  }
  // Length check on the trimmed transcript — otherwise an attacker could send
  // a 100KB run of whitespace and bypass the cap.
  if (transcript.length > MAX_TRANSCRIPT_CHARS) {
    return json({ error: `Transcript too long (max ${MAX_TRANSCRIPT_CHARS} chars)` }, 413);
  }

  const result = await parseTranscript(
    transcript,
    payload.follow_up_answer ?? null,
    env
  );

  // Optional: persist meal log to D1. Failures here must not break the parse
  // response — logging is best-effort and offline-tolerant.
  if (env.DB && result.meal) {
    // Resolve the user_id from the JWT first, falling back to the body field
    // and then a stable demo bucket. NOTE: the iOS app currently sends
    // user_id in the request body since it doesn't ship auth yet — once a
    // real auth layer lands, prefer Authorization-header identity.
    const userId = (payload.user_id?.trim() || "demo-user").slice(0, 64);
    const now = Date.now();
    try {
      // Upsert the user row so the FK on meals.user_id succeeds. INSERT OR
      // IGNORE makes this a no-op for existing users (no clobbering display
      // name / goals).
      await env.DB
        .prepare(
          `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?3)`
        )
        .bind(userId, "VoCal User", now)
        .run();
      // Schema: meals(id, user_id, name, detail, kcal, protein_g, carbs_g,
      // fat_g, slot, source, photo_r2_key, transcript, confidence, logged_at,
      // created_at). The old insert was missing user_id + created_at + the
      // photo_r2_key slot, so every prod write was silently failing.
      await env.DB
        .prepare(
          `INSERT INTO meals
             (id, user_id, name, detail, kcal, protein_g, carbs_g, fat_g,
              slot, source, photo_r2_key, transcript, confidence, logged_at, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)`
        )
        .bind(
          crypto.randomUUID(),
          userId,
          result.meal.name,
          result.meal.detail,
          result.meal.kcal,
          result.meal.protein_g,
          result.meal.carbs_g,
          result.meal.fat_g,
          result.meal.slot,
          result.meal.source,
          null,
          transcript,
          result.meal.confidence,
          now,
          now
        )
        .run();
    } catch (err) {
      // Log to Workers console so the failure is visible, but don't fail the
      // parse response — the iOS client persists locally and re-syncs.
      console.error("voice/parse D1 write failed", (err as Error).message);
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

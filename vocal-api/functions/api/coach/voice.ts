// POST /api/coach/voice
//
// ElevenLabs TTS proxy. Body: { text: string }. Streams the resulting
// MP3 (audio/mpeg) back to the caller. Hard cap on text length (800
// chars) because TTS bills per character — runaway requests are the
// most expensive failure mode here.
//
// Key rotation: ELEVENLABS_API_KEYS is a comma-separated list. On 401
// / 402 / 429 / 5xx we rotate to the next key. ELEVENLABS_API_KEY
// (singular) is accepted as a fallback for single-key dev setups.
// When every key is exhausted we return a 502.
//
// Auth: HARD-REQUIRED bearer JWT + active Pro entitlement. TTS is the
// most expensive endpoint by far (~$16/min upstream); the soft-mint
// helper was removed here so anonymous users see a 402 paywall hand-off
// instead of burning ElevenLabs credits.
// Rate limit 20/min/identity on top of the Pro gate.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env } from "../../../src/types";
import {
  AuthRequiredError,
  EntitlementRequiredError,
  authErrorResponse,
  proRequiredResponse,
  requirePro
} from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const MAX_TEXT_CHARS = 800;
const DEFAULT_VOICE_ID = "pNInz6obpgDQGcFmaJgB"; // Adam — ElevenLabs default voice

interface VoiceBody { text?: string; }

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const bindings = env as unknown as Env & { JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  const rl = await checkRateLimit(bindings, request, "coach/voice", 20);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  let userId: string;
  try {
    ({ userId } = await requirePro(bindings, request));
  } catch (err) {
    if (err instanceof EntitlementRequiredError) return proRequiredResponse(err, CORS);
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }
  void userId;

  // Pre-flight size — text is small JSON, no need for a generous cap.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > 8 * 1024) {
    return jsonErr(413, "Request body too large");
  }

  let body: VoiceBody;
  try {
    body = (await request.json()) as VoiceBody;
  } catch {
    return jsonErr(400, "Invalid JSON");
  }

  const raw = (body.text ?? "").trim();
  if (!raw) return jsonErr(400, "text required");
  if (raw.length > MAX_TEXT_CHARS) {
    return jsonErr(413, `text too long (max ${MAX_TEXT_CHARS} chars)`);
  }
  const text = raw;

  // Collect keys: comma-separated ELEVENLABS_API_KEYS, then singular
  // ELEVENLABS_API_KEY. Dedupe so a CSV that contains the singular key
  // doesn't double-try the same credential.
  const keys = collectKeys(bindings);
  if (keys.length === 0) {
    return jsonErr(503, "ELEVENLABS_API_KEYS not configured");
  }

  const voiceId = (bindings.ELEVENLABS_VOICE_ID || DEFAULT_VOICE_ID).trim();
  // Pin the model + output format so cost is predictable. eleven_turbo_v2_5
  // is the cheapest reasonable-quality model; mp3_44100_128 is small enough
  // to stream over LTE without buffering.
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}?output_format=mp3_44100_128`;
  const payload = JSON.stringify({
    text,
    model_id: "eleven_turbo_v2_5",
    voice_settings: { stability: 0.5, similarity_boost: 0.75 }
  });

  const errors: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: {
          "xi-api-key": key,
          "Content-Type": "application/json",
          "Accept": "audio/mpeg"
        },
        body: payload
      });
    } catch (err) {
      // Network blip — try next key.
      errors.push(`fetch-failed/${maskKey(key)}: ${(err as Error).message.slice(0, 80)}`);
      continue;
    }

    if (res.ok) {
      // Stream the audio body through. Don't buffer — Workers can pipe
      // bytes from one fetch into the response directly.
      const headers = new Headers(CORS);
      headers.set("Content-Type", "audio/mpeg");
      // Discourage caching downstream — TTS is per-user and audio bytes
      // are large enough that we don't want a shared CDN holding them.
      headers.set("Cache-Control", "private, no-store");
      return new Response(res.body, { status: 200, headers });
    }

    // Decide whether to rotate. 401/402/403/429/5xx are key-level issues
    // (bad key, out of credit, throttled, upstream). 4xx (other) is a
    // request-shape bug — same on every key, bail out.
    if (isRotatableStatus(res.status)) {
      const detail = await safeText(res);
      errors.push(`${maskKey(key)} ${res.status}: ${detail.slice(0, 120)}`);
      continue;
    }
    const detail = await safeText(res);
    console.error("coach/voice: non-rotatable upstream error", { status: res.status, detail: detail.slice(0, 200) });
    return jsonErr(502, `TTS upstream rejected request (${res.status})`);
  }

  console.error("coach/voice: all keys exhausted", { tried: keys.length, errors: errors.slice(-3) });
  return jsonErr(502, "all TTS keys exhausted");
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function collectKeys(env: Env): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const push = (raw: string | undefined): void => {
    if (!raw) return;
    for (const k of raw.split(",")) {
      const t = k.trim();
      if (t && !seen.has(t)) { seen.add(t); out.push(t); }
    }
  };
  push(env.ELEVENLABS_API_KEYS);
  push(env.ELEVENLABS_API_KEY);
  return out;
}

function isRotatableStatus(status: number): boolean {
  return status === 401 || status === 402 || status === 403
      || status === 408 || status === 429
      || (status >= 500 && status <= 599);
}

async function safeText(res: Response): Promise<string> {
  try { return await res.text(); } catch { return ""; }
}

function maskKey(k: string): string {
  if (k.length < 10) return "***";
  return `${k.slice(0, 4)}…${k.slice(-3)}`;
}

function jsonErr(status: number, detail: string): Response {
  return new Response(JSON.stringify({ error: detail }), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}

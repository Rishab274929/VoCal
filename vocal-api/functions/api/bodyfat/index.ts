// POST /api/bodyfat — body-fat estimate.
//
// Two execution paths, picked by the request body:
//
//   A. VISION  — image_b64_front + image_b64_side present
//      → multimodal LLM call against a vision-capable provider, returns
//        a real estimate with model-driven reasoning.
//
//   B. R2 / HEURISTIC — front_r2_key + side_r2_key (or no photos at all)
//      → falls back to the BMI heuristic. Kept for backwards-compat with
//        clients that pre-upload to R2 and just pass keys.
//
// Both paths share validation, auth, rate limiting, and the body_metrics
// write. The response shape is stable: { body_fat_pct, confidence, reasoning }.
//
// Auth: HARD-REQUIRED bearer JWT. The legacy body.user_id soft fallback
// was removed once the iOS + Flutter clients both shipped /api/auth/* —
// old clients will see a 401 (a deliberate cutover).

import {
  AuthRequiredError,
  EntitlementRequiredError,
  authErrorResponse,
  proRequiredResponse,
  requirePro
} from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";
import { chat } from "../../../src/ai/llmClient";
import type { Env } from "../../../src/types";

interface BFBody {
  user_id?: string;
  weight_lb: number;
  height_in: number;
  sex?: string;
  // Vision path
  image_b64_front?: string;
  image_b64_side?: string;
  // R2 path (legacy)
  front_r2_key?: string;
  side_r2_key?: string;
}

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST,OPTIONS",
  "access-control-allow-headers": "content-type,authorization",
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

// Two photos at 1.5MB each = ~4MB base64. Hard cap on the full envelope.
const MAX_IMAGE_BYTES = 1_500_000;
const BASE64_OVERHEAD = 1.34;
const MAX_REQUEST_BYTES = Math.ceil(MAX_IMAGE_BYTES * 2 * BASE64_OVERHEAD) + 8192;

const VISION_SYSTEM_PROMPT = `You are a body-composition estimator. Given front
and side photos and basic anthropometrics, estimate body fat percentage with
your confidence. Reply ONLY with a JSON object in this exact shape:
{"body_fat_pct": number, "confidence": number between 0 and 1, "reasoning": "short string under 200 chars"}

Rules:
- body_fat_pct is a single number, e.g. 18.5 (not a range).
- confidence reflects how much the photos + measurements pinned the estimate.
- reasoning is one sentence explaining what you saw. No moralizing.
- No prose, no markdown, no code fences. JSON only.`;

interface VisionLLMOutput {
  body_fat_pct?: number;
  confidence?: number;
  reasoning?: string;
}

export const onRequestOptions = async (): Promise<Response> => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const bindings = env as unknown as Env & { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  // Rate limit: 10/min/identity — body-fat is a rare action; this catches
  // abuse before the LLM cost mounts.
  const rl = await checkRateLimit(bindings, request, "bodyfat", 10);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  // Pre-flight content-length — refuse before allocating ~4MB of base64.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > MAX_REQUEST_BYTES) {
    return json({ error: "Request body too large; resize photos to ~1.5MB each" }, { status: 413 });
  }

  let body: BFBody;
  try {
    body = (await request.json()) as BFBody;
  } catch {
    return json({ error: "Invalid JSON" }, { status: 400 });
  }

  // Pro-gated: vision LLM call costs $$ per request. Bearer JWT
  // hard-required and an active entitlement row must exist. We do this
  // BEFORE the LLM call so an unauthenticated or unpaid client can't
  // burn vision-provider credits. body.user_id is ignored.
  let userId: string;
  try {
    ({ userId } = await requirePro(bindings, request));
  } catch (err) {
    if (err instanceof EntitlementRequiredError) return proRequiredResponse(err, CORS);
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // Anthropometric validation: identical to the heuristic path so a vision
  // call never runs on garbage inputs.
  const weight_lb = Number(body.weight_lb);
  const height_in = Number(body.height_in);
  if (!isFinite(weight_lb) || weight_lb <= 0 || weight_lb > 2000) {
    return json({ error: "weight_lb out of range" }, { status: 400 });
  }
  if (!isFinite(height_in) || height_in <= 0 || height_in > 120) {
    return json({ error: "height_in out of range" }, { status: 400 });
  }

  const hasVisionImages = !!(body.image_b64_front && body.image_b64_side);

  // --- Decide which path runs ------------------------------------------------
  let bodyFatPct: number;
  let confidence: number;
  let reasoning: string;
  let source: "vision" | "r2" | "heuristic" = "heuristic";

  if (hasVisionImages) {
    // Strip data: prefix if iOS bundled it. Be permissive of the variations
    // SwiftUI's UIImage encoder produces.
    const frontB64 = body.image_b64_front!.replace(/^data:image\/[\w+.-]+;base64,/, "");
    const sideB64  = body.image_b64_side!.replace(/^data:image\/[\w+.-]+;base64,/, "");

    // Per-image bounds. Without this a single 4MB image could squeak past the
    // total-request cap if the OTHER image was tiny.
    if (frontB64.length > MAX_IMAGE_BYTES * BASE64_OVERHEAD
        || sideB64.length > MAX_IMAGE_BYTES * BASE64_OVERHEAD) {
      return json({ error: "Each photo must be <=1.5MB. Resize before posting." }, { status: 413 });
    }
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(frontB64) || !/^[A-Za-z0-9+/=\r\n]+$/.test(sideB64)) {
      return json({ error: "image_b64_front / image_b64_side must be valid base64" }, { status: 400 });
    }

    const sexLabel = body.sex === "f" ? "female"
                   : body.sex === "m" ? "male"
                   : "unspecified";
    // Build a multimodal user message: text context + two image parts.
    // The image type is "image/jpeg" by default — iOS posts JPEG; if the user
    // sends PNG it'll still decode at the provider since the JPEG mimetype is
    // just a hint to the LLM provider.
    const userParts = [
      {
        type: "text" as const,
        text: `Anthropometrics: weight ${weight_lb} lb, height ${height_in} in, sex ${sexLabel}. Photos below: front view first, side view second.`
      },
      { type: "image_url" as const, image_url: { url: `data:image/jpeg;base64,${frontB64}` } },
      { type: "image_url" as const, image_url: { url: `data:image/jpeg;base64,${sideB64}` } },
      { type: "text" as const, text: "Estimate body fat. JSON only." }
    ];

    try {
      const result = await chat({
        messages: [
          { role: "system", content: VISION_SYSTEM_PROMPT },
          { role: "user", content: userParts }
        ],
        responseFormat: "json_object",
        maxTokens: 400,
        temperature: 0.2,
        needsVision: true
      }, env);

      const parsed = safeJson<VisionLLMOutput>(result.content);
      if (!parsed || typeof parsed.body_fat_pct !== "number" || !isFinite(parsed.body_fat_pct)) {
        // Model output didn't match the schema — fall back to the heuristic
        // rather than returning a 5xx. The user still gets a reasonable answer.
        console.warn("bodyfat/vision: LLM output didn't match schema", { provider: result.provider, raw: result.content.slice(0, 200) });
        const heur = heuristic(weight_lb, height_in, body.sex);
        bodyFatPct = heur.pct;
        confidence = heur.confidence;
        reasoning = `Vision model didn't return usable JSON; fell back to BMI heuristic.`;
        source = "heuristic";
      } else {
        // Sanity-clamp to physiologically plausible range.
        bodyFatPct = clamp(parsed.body_fat_pct, 4, 60);
        confidence = clamp(
          typeof parsed.confidence === "number" && isFinite(parsed.confidence) ? parsed.confidence : 0.6,
          0.1, 0.99
        );
        reasoning = typeof parsed.reasoning === "string"
          ? parsed.reasoning.slice(0, 200)
          : `Estimated from front+side photos via ${result.provider}.`;
        source = "vision";
      }
    } catch (err) {
      // Vision providers all down — fall back gracefully instead of failing
      // the request. The user paid for an estimate; the heuristic still gives
      // one (lower confidence makes that clear).
      console.error("bodyfat/vision: all providers failed", (err as Error).message);
      const heur = heuristic(weight_lb, height_in, body.sex);
      bodyFatPct = heur.pct;
      confidence = heur.confidence;
      reasoning = "Vision providers unavailable; BMI heuristic only.";
      source = "heuristic";
    }
  } else {
    // R2-key path or no-photo path — both use the heuristic. The R2 keys
    // are persisted to body_metrics so a later batch job could re-score.
    const heur = heuristic(weight_lb, height_in, body.sex);
    bodyFatPct = heur.pct;
    confidence = body.front_r2_key && body.side_r2_key ? heur.confidence + 0.1 : heur.confidence;
    confidence = clamp(confidence, 0.1, 0.99);
    reasoning = body.front_r2_key && body.side_r2_key
      ? "BMI heuristic (R2 photos stored for a future vision pass)."
      : "BMI heuristic only — supply image_b64_front + image_b64_side for a vision estimate.";
    source = body.front_r2_key && body.side_r2_key ? "r2" : "heuristic";
  }

  // --- Persist as a body_metrics row ---------------------------------------
  // userId is already resolved from the JWT above.
  try {
    const now = Date.now();
    if (bindings.DB) {
      await bindings.DB.prepare(
        `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`,
      ).bind(userId, "VoCal User", now, now).run();

      await bindings.DB.prepare(
        `INSERT INTO body_metrics (id, user_id, weight_lb, body_fat_pct, bf_confidence, front_r2_key, side_r2_key, notes, measured_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
      ).bind(
        crypto.randomUUID(),
        userId,
        weight_lb,
        bodyFatPct,
        confidence,
        body.front_r2_key ? body.front_r2_key.slice(0, 200) : null,
        body.side_r2_key ? body.side_r2_key.slice(0, 200) : null,
        source,
        now,
      ).run();
    }
  } catch (err) {
    console.error("bodyfat: DB write failed", (err as Error).message);
    // continue — return result anyway
  }

  return json({
    body_fat_pct: Number(bodyFatPct.toFixed(1)),
    confidence: Number(confidence.toFixed(2)),
    reasoning,
    // Kept for backwards-compat — older clients read `notes`.
    notes: reasoning,
    source
  });
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function heuristic(weight_lb: number, height_in: number, sex: string | undefined): { pct: number; confidence: number } {
  const kg = weight_lb * 0.4536;
  const m = height_in * 0.0254;
  const bmi = m > 0 ? kg / (m * m) : 22;
  const baseline = sex === "f" ? 22.0 : 16.0;
  let pct = baseline + (bmi - 22) * 1.6;
  pct = clamp(pct, 7.5, 40);
  return { pct, confidence: 0.62 };
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

function safeJson<T>(raw: string): T | null {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidates: string[] = [];
  if (fenced?.[1]) candidates.push(fenced[1]);
  candidates.push(raw);
  const balanced = extractBalancedObject(raw);
  if (balanced) candidates.push(balanced);
  for (const c of candidates) {
    try { return JSON.parse(c) as T; } catch { /* try next */ }
  }
  return null;
}

function extractBalancedObject(s: string): string | null {
  const start = s.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let inStr = false;
  let escape = false;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (escape) { escape = false; continue; }
      if (c === "\\") { escape = true; continue; }
      if (c === '"') { inStr = false; continue; }
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === "{") { depth++; continue; }
    if (c === "}") {
      depth--;
      if (depth === 0) return s.slice(start, i + 1);
    }
  }
  return null;
}

// POST /api/photo/parse
//
// Body: { image_base64: string (without data URL prefix), voice_context?: string }
// Returns: VoiceParseResponse with the parsed meal (or a follow-up question).
//
// Pipeline:
//   1. Send the image + an optional voice context to a vision LLM. We use
//      OpenRouter because Wafer Pass currently doesn't ship a multimodal
//      model (Qwen-3 / GLM-5 are text-only). Model: `openai/gpt-4o-mini`
//      with image input — cheap, fast, accurate enough for meal photos.
//   2. Strict JSON-mode output, validate macro ranges.
//   3. Reuse the same ParsedMeal shape as voice/parse so the iOS app
//      handles both paths identically.
//
// Cost guardrail: hard cap on incoming image bytes (1.5 MB). The iOS app
// must resize before posting; this prevents wasted tokens.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env, VoiceParseResponse, ParsedMeal } from "../../../src/types";
import { guessSlot } from "../../../src/lib/normalize";
import { chat } from "../../../src/ai/llmClient";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

const MAX_IMAGE_BYTES = 1_500_000;
// Base64 expansion is exactly 4/3 ≈ 1.3333, plus padding (up to +2 chars).
// Use 1.34 — older code used 1.36 which under-rejected by ~1.5%.
const BASE64_OVERHEAD = 1.34;
// Hard cap on the entire request body. iOS sends JSON of the form
// { "image_base64": "<base64>", "voice_context": "..." } so the worst case
// is ~2 MB of base64 + ~600 chars of voice context + JSON envelope.
const MAX_REQUEST_BYTES = Math.ceil(MAX_IMAGE_BYTES * BASE64_OVERHEAD) + 4096;

const SYSTEM_PROMPT = `You are VoCal's photo-parsing engine. The user submits
a photo of a meal — sometimes with optional voice context describing what's
on the plate. Identify each visible ingredient, account for hidden layers
mentioned in the voice context, and return a strict JSON object with the
meal's macros.

Required fields when you return a meal:
{
  "name": "Display name, Title Case, no quotes",
  "detail": "Short clarifying phrase like 'photo + voice'",
  "kcal": integer total calories,
  "protein_g": integer grams of protein,
  "carbs_g": integer grams of carbohydrate,
  "fat_g": integer grams of total fat,
  "slot": one of "breakfast" | "lunch" | "dinner" | "snack",
  "confidence": float in [0, 1]
}

Or if you genuinely need clarification:
{
  "follow_up_question": "One short question.",
  "reasoning": "Why you need it."
}

Rules:
- Use USDA reference portions when not specified ("a medium apple" is ~182g).
- When the user names a chain restaurant, use that chain's actual published
  nutrition for the item if you know it.
- Voice context overrides photo when they conflict ("there's chicken under
  the rice" means count chicken even if you can't see it).
- Round all numeric fields to integers.
- Output JSON only. No prose, no markdown.`;

interface LLMMealOutput {
  name?: string;
  detail?: string;
  kcal?: number;
  protein_g?: number;
  carbs_g?: number;
  fat_g?: number;
  slot?: string;
  confidence?: number;
  follow_up_question?: string;
  reasoning?: string;
}

interface PhotoParseRequest {
  image_base64?: string;
  voice_context?: string | null;
}

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  // Pre-flight size check: refuse before parsing the body to keep a malicious
  // 50MB upload from forcing a giant string allocation in the worker.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > MAX_REQUEST_BYTES) {
    return json({ error: "Image too large; resize to ~1.5MB before posting" }, 413);
  }
  let payload: PhotoParseRequest;
  try {
    payload = (await request.json()) as PhotoParseRequest;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const b64 = (payload.image_base64 ?? "").replace(/^data:image\/[\w+.-]+;base64,/, "");
  if (!b64) return json({ error: "image_base64 required" }, 400);
  // Hard cap on the base64 string itself, in case Content-Length was absent
  // (chunked transfer or a permissive proxy).
  if (b64.length > MAX_IMAGE_BYTES * BASE64_OVERHEAD) {
    return json({ error: "Image too large; resize to ~1.5MB before posting" }, 413);
  }
  // Cheap base64 sanity check — reject obviously-corrupt input rather than
  // wasting an LLM call on bytes the provider will reject anyway.
  if (!/^[A-Za-z0-9+/=\r\n]+$/.test(b64)) {
    return json({ error: "image_base64 is not valid base64" }, 400);
  }
  // Vision provider pool: Wafer GLM-5.1 → Gemini Flash (free) → OpenRouter
  // gpt-4o-mini. Configure multiple keys per provider with the *_API_KEYS
  // plural (comma-separated) and the rotator falls through on 402/429/5xx.

  const userParts: Array<{ type: "text" | "image_url"; text?: string; image_url?: { url: string } }> = [
    { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } }
  ];
  if (payload.voice_context?.trim()) {
    userParts.push({ type: "text", text: `Voice context: ${payload.voice_context.trim()}` });
  } else {
    userParts.push({ type: "text", text: "Parse this meal photo into macros. JSON only." });
  }

  const started = Date.now();
  let raw = "";
  let provider = "";
  try {
    const result = await chat({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userParts }
      ],
      responseFormat: "json_object",
      maxTokens: 1500,
      temperature: 0.1,
      needsVision: true
    }, env);
    raw = result.content;
    provider = `${result.provider}/${result.model}`;
  } catch (err) {
    // Do NOT echo the provider error back to the client — upstream errors
    // can contain key fragments, internal hostnames, or stack frames.
    // Log it for observability (Workers logs) and return a generic 502.
    console.error("photo/parse provider failure", (err as Error).message);
    return json({ error: "All vision providers are unavailable. Try again or describe your meal by voice." }, 502);
  }

  const parsed = safeJson<LLMMealOutput>(raw);
  if (parsed?.follow_up_question) {
    const response: VoiceParseResponse = {
      transcript: payload.voice_context ?? "",
      follow_up_question: parsed.follow_up_question,
      meal: null,
      reasoning: parsed.reasoning ?? "Need clarification before logging."
    };
    return json(response, 200);
  }
  if (parsed && isValidMeal(parsed)) {
    const meal: ParsedMeal = {
      name: parsed.name!,
      detail: parsed.detail ?? "photo + voice",
      kcal: Math.round(parsed.kcal!),
      protein_g: Math.round(parsed.protein_g!),
      carbs_g: Math.round(parsed.carbs_g!),
      fat_g: Math.round(parsed.fat_g!),
      slot: (parsed.slot as ParsedMeal["slot"]) ?? guessSlot(),
      source: payload.voice_context?.trim() ? "voice+photo" : "photo",
      confidence: typeof parsed.confidence === "number"
        ? Math.max(0, Math.min(1, parsed.confidence))
        : 0.78
    };
    const response: VoiceParseResponse = {
      transcript: payload.voice_context ?? "",
      follow_up_question: null,
      meal,
      reasoning: `Parsed photo via ${provider} in ${Date.now() - started}ms.`
    };
    return json(response, 200);
  }

  // No fabricated stub: when the model can't produce valid macros we ask
  // the user for a verbal cue instead of inventing numbers.
  return json({
    transcript: payload.voice_context ?? "",
    follow_up_question: "I couldn't read the plate confidently — what's the main food and rough portion?",
    meal: null,
    reasoning: "Vision model output didn't match the expected JSON schema."
  } satisfies VoiceParseResponse, 200);
};

function isValidMeal(p: LLMMealOutput): boolean {
  return typeof p.name === "string"
    && typeof p.kcal === "number" && p.kcal > 0 && p.kcal < 5000
    && typeof p.protein_g === "number" && p.protein_g >= 0 && p.protein_g < 400
    && typeof p.carbs_g === "number" && p.carbs_g >= 0 && p.carbs_g < 600
    && typeof p.fat_g === "number" && p.fat_g >= 0 && p.fat_g < 300;
}

function safeJson<T>(raw: string): T | null {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidates: string[] = [];
  if (fenced?.[1]) candidates.push(fenced[1]);
  candidates.push(raw);
  // Brace-balanced extraction — see foodParser.safeJson for the rationale.
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

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}

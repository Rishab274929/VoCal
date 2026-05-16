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

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

const MAX_IMAGE_BYTES = 1_500_000;

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
  let payload: PhotoParseRequest;
  try {
    payload = (await request.json()) as PhotoParseRequest;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const b64 = (payload.image_base64 ?? "").replace(/^data:image\/\w+;base64,/, "");
  if (!b64) return json({ error: "image_base64 required" }, 400);
  // base64 expands ~33% so 1.5MB binary ≈ 2MB base64. Cap on the source bytes.
  if (b64.length > MAX_IMAGE_BYTES * 1.36) {
    return json({ error: "Image too large; resize to ~1.5MB before posting" }, 413);
  }
  if (!env.OPENROUTER_API_KEY) {
    return json({ error: "Vision model not configured (OPENROUTER_API_KEY missing)" }, 503);
  }

  const userParts: Array<{ type: "text" | "image_url"; text?: string; image_url?: { url: string } }> = [
    { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } }
  ];
  if (payload.voice_context?.trim()) {
    userParts.push({ type: "text", text: `Voice context: ${payload.voice_context.trim()}` });
  } else {
    userParts.push({ type: "text", text: "Parse this meal photo into macros. JSON only." });
  }

  const started = Date.now();
  let raw: string;
  try {
    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://vocal.best",
        "X-Title": "VoCal"
      },
      body: JSON.stringify({
        model: "openai/gpt-4o-mini",
        temperature: 0.1,
        max_tokens: 1000,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userParts }
        ]
      })
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      return json({ error: `OpenRouter ${res.status}: ${txt.slice(0, 240)}` }, 502);
    }
    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string | null } }>;
    };
    raw = data.choices?.[0]?.message?.content ?? "";
    if (!raw) return json({ error: "OpenRouter returned empty content" }, 502);
  } catch (err) {
    return json({ error: `Vision call failed: ${(err as Error).message}` }, 502);
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
      reasoning: `Parsed photo via gpt-4o-mini in ${Date.now() - started}ms.`
    };
    return json(response, 200);
  }

  return json({
    transcript: payload.voice_context ?? "",
    follow_up_question: null,
    meal: null,
    reasoning: "Vision model output didn't match the expected JSON schema."
  } satisfies VoiceParseResponse, 422);
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
  const objMatch = raw.match(/\{[\s\S]*\}/);
  if (objMatch) candidates.push(objMatch[0]);
  for (const c of candidates) {
    try { return JSON.parse(c) as T; } catch { /* try next */ }
  }
  return null;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}

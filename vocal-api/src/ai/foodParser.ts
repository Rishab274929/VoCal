// Top-level food parser. Resolution order:
//   1. KV cache hit (if FOOD_KV is bound) — instant return
//   2. Chipotle bowl special-case (because it can yield a follow-up question)
//   3. Chain canon match (McDonald's, Starbucks, etc.) — deterministic
//   4. LLM with tool-style USDA lookup (Wafer first, OpenRouter fallback)
//   5. Generic 450 kcal fallback (clearly low-confidence)

import type { Env, VoiceParseResponse, ParsedMeal } from "../types";
import { cacheKey, guessSlot, normalize } from "../lib/normalize";
import { matchChain, parseChipotleBowl } from "./canon";
import { chat } from "./llmClient";
import { usdaSearch } from "./usda";

const SYSTEM_PROMPT = `You are VoCal's food-parsing engine. The user speaks freely
("two scrambled eggs and a piece of toast", "8 oz grilled chicken breast",
"slice of pepperoni pizza"). Return a strict JSON object with the meal's
macros. If the transcript is genuinely under-specified (e.g. ambiguous portion
that materially changes the answer), instead return a one-question follow-up.

Required fields when you return a meal:
{
  "name": "Display name, Title Case, no quotes",
  "detail": "Short clarifying phrase like 'estimated from portion language'",
  "kcal": integer total calories,
  "protein_g": integer grams of protein,
  "carbs_g": integer grams of carbohydrate,
  "fat_g": integer grams of total fat,
  "slot": one of "breakfast" | "lunch" | "dinner" | "snack",
  "confidence": float in [0, 1]
}

Or if you need clarification:
{
  "follow_up_question": "One short question.",
  "reasoning": "Why you need it."
}

Rules:
- Use USDA reference portions when the user didn't specify (a "medium apple"
  is ~182g, a "slice of pizza" is ~107g, "1 cup rice" cooked is ~158g).
- When the user names a chain ("Burger King Whopper") and you know the public
  nutrition for it, return that exact item — not an estimate.
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

// The 450/20/45/20 generic stub was removed in iter 19. When all five
// real-detection tiers (KV, Chipotle, chain canon, LLM, USDA) fail, we
// return meal: null + a follow-up question instead of fabricating macros.
// The iOS client treats a null meal as "ask me again" rather than logging
// a phantom 450-kcal meal that doesn't match what the user said.

export async function parseTranscript(
  transcript: string,
  followUpAnswer: string | null | undefined,
  env: Env
): Promise<VoiceParseResponse> {
  const trimmed = transcript.trim();
  if (!trimmed) {
    return {
      transcript,
      follow_up_question: "What did you eat?",
      meal: null,
      reasoning: "Empty transcript — please describe the meal."
    };
  }

  // 1. KV cache
  if (env.FOOD_KV) {
    const key = cacheKey(trimmed, followUpAnswer);
    const cached = await env.FOOD_KV.get<VoiceParseResponse>(key, "json").catch(() => null);
    if (cached) {
      return { ...cached, transcript, reasoning: `Cache hit. ${cached.reasoning}` };
    }
  }

  // 2. Chipotle bowl (may return a follow-up)
  const chipotle = parseChipotleBowl(trimmed, followUpAnswer);
  if (chipotle) {
    if ("followUp" in chipotle) {
      return {
        transcript,
        follow_up_question: chipotle.followUp,
        meal: null,
        reasoning: chipotle.reasoning
      };
    }
    return cacheAndReturn(env, trimmed, followUpAnswer, {
      transcript,
      follow_up_question: null,
      meal: chipotle.meal,
      reasoning: "Matched Chipotle bowl template."
    });
  }

  // 3. Chain canon
  const chain = matchChain(trimmed);
  if (chain) {
    return cacheAndReturn(env, trimmed, followUpAnswer, {
      transcript,
      follow_up_question: null,
      meal: chain,
      reasoning: "Matched chain canon item."
    });
  }

  // 4. LLM
  try {
    const userMsg = followUpAnswer
      ? `Transcript: ${trimmed}\nUser's follow-up answer: ${followUpAnswer}`
      : `Transcript: ${trimmed}`;
    const result = await chat({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMsg }
      ],
      responseFormat: "json_object",
      maxTokens: 1500,
      temperature: 0.1
    }, env);

    const parsed = safeJson<LLMMealOutput>(result.content);
    if (parsed?.follow_up_question) {
      return {
        transcript,
        follow_up_question: parsed.follow_up_question,
        meal: null,
        reasoning: parsed.reasoning ?? `Need clarification (${result.provider}).`
      };
    }
    if (parsed && isValidMeal(parsed)) {
      const meal: ParsedMeal = {
        name: parsed.name!,
        detail: parsed.detail ?? "Estimated by LLM",
        kcal: Math.round(parsed.kcal!),
        protein_g: Math.round(parsed.protein_g!),
        carbs_g: Math.round(parsed.carbs_g!),
        fat_g: Math.round(parsed.fat_g!),
        slot: (parsed.slot as ParsedMeal["slot"]) ?? guessSlot(),
        source: "voice",
        confidence: typeof parsed.confidence === "number"
          ? Math.max(0, Math.min(1, parsed.confidence))
          : 0.78
      };
      return cacheAndReturn(env, trimmed, followUpAnswer, {
        transcript,
        follow_up_question: null,
        meal,
        reasoning: `Parsed by ${result.provider} (${result.model}) in ${result.latencyMs}ms.`
      });
    }
  } catch (err) {
    // 4b. LLM failed — try USDA directly as a softer signal
    const usda = await usdaSearch(normalize(trimmed), env).catch(() => null);
    if (usda) {
      const meal: ParsedMeal = {
        name: usda.description,
        detail: `USDA FDC #${usda.fdcId} per ${usda.servingGrams}g`,
        kcal: Math.round(usda.kcal),
        protein_g: Math.round(usda.protein_g),
        carbs_g: Math.round(usda.carbs_g),
        fat_g: Math.round(usda.fat_g),
        slot: guessSlot(),
        source: "voice",
        confidence: 0.65
      };
      return cacheAndReturn(env, trimmed, followUpAnswer, {
        transcript,
        follow_up_question: null,
        meal,
        reasoning: `LLM unavailable (${(err as Error).message}); USDA fallback.`
      });
    }
  }

  // 5. No tier was confident enough. Return meal: null so the iOS client
  // can ask the user to be more specific instead of logging a fake meal.
  return {
    transcript,
    follow_up_question: "I'm not sure what that is — could you describe it with portions or a brand?",
    meal: null,
    reasoning: "No matcher confident enough. Refusing to fabricate macros."
  };
}

function isValidMeal(p: LLMMealOutput): boolean {
  return typeof p.name === "string"
    && typeof p.kcal === "number" && p.kcal > 0 && p.kcal < 5000
    && typeof p.protein_g === "number" && p.protein_g >= 0 && p.protein_g < 400
    && typeof p.carbs_g === "number" && p.carbs_g >= 0 && p.carbs_g < 600
    && typeof p.fat_g === "number" && p.fat_g >= 0 && p.fat_g < 300;
}

function safeJson<T>(raw: string): T | null {
  // 1. Strip ```json ... ``` if the model fenced its output.
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidates: string[] = [];
  if (fenced?.[1]) candidates.push(fenced[1]);
  candidates.push(raw);

  // 2. Extract the first balanced-brace object. Thinking models sometimes
  // emit reasoning prose around the JSON, e.g. "Let me think... { ... }".
  const objMatch = raw.match(/\{[\s\S]*\}/);
  if (objMatch) candidates.push(objMatch[0]);

  for (const cand of candidates) {
    try {
      return JSON.parse(cand) as T;
    } catch {
      // try next candidate
    }
  }
  return null;
}

async function cacheAndReturn(
  env: Env,
  transcript: string,
  followUp: string | null | undefined,
  response: VoiceParseResponse
): Promise<VoiceParseResponse> {
  if (env.FOOD_KV && response.meal) {
    const key = cacheKey(transcript, followUp);
    // 30-day TTL is plenty: nutrition data is effectively static.
    await env.FOOD_KV.put(key, JSON.stringify(response), { expirationTtl: 60 * 60 * 24 * 30 })
      .catch(() => undefined);
  }
  return response;
}

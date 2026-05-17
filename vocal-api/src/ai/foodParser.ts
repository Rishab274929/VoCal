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

Optional micronutrient fields — include ONLY when you have well-documented
public nutrition (chain restaurant nutrition guides, USDA standard refs).
OMIT the key entirely when uncertain. Do NOT guess.
{
  "sodium_mg":   integer milligrams of sodium,
  "fiber_g":     integer grams of dietary fiber,
  "sugar_g":     integer grams of total sugar,
  "calcium_mg":  integer milligrams of calcium,
  "iron_mg":     number milligrams of iron (one decimal allowed),
  "vitamin_c_mg": number milligrams of vitamin C,
  "potassium_mg": integer milligrams of potassium
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
- Round kcal + macros + sodium + fiber + sugar + calcium + potassium to integers.
- iron_mg and vitamin_c_mg may have one decimal.
- Omit any micronutrient field you're not confident about. Empty is better than wrong.
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
  sodium_mg?: number;
  fiber_g?: number;
  sugar_g?: number;
  calcium_mg?: number;
  iron_mg?: number;
  vitamin_c_mg?: number;
  potassium_mg?: number;
  follow_up_question?: string;
  reasoning?: string;
}

// Sanity bounds — reject obviously hallucinated values. Numbers based on
// the worst-case "all of one ingredient" upper bounds for a single meal.
const MICRO_MAX = {
  sodium_mg: 10000,
  fiber_g: 100,
  sugar_g: 300,
  calcium_mg: 3000,
  iron_mg: 50,
  vitamin_c_mg: 2000,
  potassium_mg: 8000
} as const;

function pickMicros(p: LLMMealOutput): Partial<Pick<ParsedMeal,
  "sodium_mg" | "fiber_g" | "sugar_g" | "calcium_mg" |
  "iron_mg" | "vitamin_c_mg" | "potassium_mg">> {
  const out: Partial<ParsedMeal> = {};
  const intField = (k: keyof typeof MICRO_MAX): void => {
    const v = p[k];
    if (typeof v === "number" && isFinite(v) && v >= 0 && v <= MICRO_MAX[k]) {
      (out as Record<string, number>)[k] = Math.round(v);
    }
  };
  const floatField = (k: "iron_mg" | "vitamin_c_mg"): void => {
    const v = p[k];
    if (typeof v === "number" && isFinite(v) && v >= 0 && v <= MICRO_MAX[k]) {
      (out as Record<string, number>)[k] = Math.round(v * 10) / 10;
    }
  };
  intField("sodium_mg");
  intField("fiber_g");
  intField("sugar_g");
  intField("calcium_mg");
  floatField("iron_mg");
  floatField("vitamin_c_mg");
  intField("potassium_mg");
  return out;
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
          : 0.78,
        ...pickMicros(parsed)
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

  // 2. Extract the first BALANCED-brace object. The old regex /\{[\s\S]*\}/
  // is greedy and grabs from the first `{` to the LAST `}`, which fails
  // when the model emits e.g. `{...} and here's why: {...}`. Scan for the
  // first `{` and walk forward tracking depth + string state.
  const balanced = extractBalancedObject(raw);
  if (balanced) candidates.push(balanced);

  for (const cand of candidates) {
    try {
      return JSON.parse(cand) as T;
    } catch {
      // try next candidate
    }
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

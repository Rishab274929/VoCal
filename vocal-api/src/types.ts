// Shared types between functions and src modules.

export interface VoiceParsePayload {
  transcript: string;
  follow_up_answer?: string | null;
}

export interface ParsedMeal {
  name: string;
  detail: string;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  slot: "breakfast" | "lunch" | "dinner" | "snack";
  source: "voice" | "photo" | "manual" | "voice+photo" | "barcode";
  confidence: number;
  // Optional micronutrients — additive, present only when the matcher / LLM
  // is confident enough to surface them. The parser MUST omit a field
  // rather than guess. The iOS / Flutter clients treat missing fields as
  // "unknown" and don't display them.
  sodium_mg?: number;
  fiber_g?: number;
  sugar_g?: number;
  calcium_mg?: number;
  iron_mg?: number;
  vitamin_c_mg?: number;
  potassium_mg?: number;
}

export interface VoiceParseResponse {
  transcript: string;
  follow_up_question: string | null;
  meal: ParsedMeal | null;
  reasoning: string;
}

export interface Env {
  // LLM providers — set the singular OR the plural OR numbered (..._API_KEY_2 etc.)
  WAFER_API_KEY?: string;
  WAFER_API_KEY_2?: string;
  WAFER_API_KEY_3?: string;
  WAFER_API_KEY_4?: string;
  WAFER_API_KEYS?: string;            // comma-separated bulk seed
  OPENROUTER_API_KEY?: string;
  OPENROUTER_API_KEY_2?: string;
  OPENROUTER_API_KEYS?: string;
  GEMINI_API_KEY?: string;            // Google AI Studio (free tier)
  GEMINI_API_KEY_2?: string;
  GEMINI_API_KEYS?: string;
  GROQ_API_KEY?: string;              // Free, fast Llama 3.x
  GROQ_API_KEYS?: string;
  MISTRAL_API_KEY?: string;
  MISTRAL_API_KEYS?: string;
  // Other infra
  USDA_FDC_API_KEY?: string;
  JWT_SECRET?: string;
  // ElevenLabs TTS — comma-separated list of keys for rotation on 401/429/5xx.
  // Single-key callers can set ELEVENLABS_API_KEY instead.
  ELEVENLABS_API_KEYS?: string;
  ELEVENLABS_API_KEY?: string;
  ELEVENLABS_VOICE_ID?: string; // optional override; defaults to "pNInz6obpgDQGcFmaJgB" (Adam)
  GOOGLE_CLIENT_ID_IOS?: string;
  GOOGLE_CLIENT_ID_ANDROID?: string;
  GOOGLE_CLIENT_ID_WEB?: string;
  // Sign in with Apple — REQUIRED if /api/auth/apple is exposed. The bundle
  // ID is the iOS app's `aud` claim; APPLE_AUDIENCES is an optional CSV of
  // extra audiences (e.g. a Services ID for Apple sign-in on the web).
  APPLE_BUNDLE_ID?: string;
  APPLE_AUDIENCES?: string;
  FOOD_KV?: KVNamespace;
  DB?: D1Database;
}

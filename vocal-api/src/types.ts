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
  GOOGLE_CLIENT_ID_IOS?: string;
  GOOGLE_CLIENT_ID_ANDROID?: string;
  GOOGLE_CLIENT_ID_WEB?: string;
  FOOD_KV?: KVNamespace;
  DB?: D1Database;
}

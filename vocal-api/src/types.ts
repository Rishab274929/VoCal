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
  WAFER_API_KEY?: string;
  OPENROUTER_API_KEY?: string;
  USDA_FDC_API_KEY?: string;
  FOOD_KV?: KVNamespace;
  DB?: D1Database;
}

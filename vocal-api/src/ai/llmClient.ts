// LLM gateway: try Wafer first (flat-rate, fast open-source models), fall back
// to OpenRouter on error or missing key. Both are OpenAI-compatible chat APIs.

import type { Env } from "../types";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  /** Force JSON-mode output. Both Wafer and OpenRouter honor this. */
  responseFormat?: "json_object";
  /** Hard cap on output tokens. */
  maxTokens?: number;
  /** Override default temperature (default: 0.1 for deterministic parsing). */
  temperature?: number;
}

export interface ChatResult {
  content: string;
  provider: "wafer" | "openrouter";
  model: string;
  /** Total latency in ms for the chosen provider's call only. */
  latencyMs: number;
}

const WAFER_URL = "https://pass.wafer.ai/v1/chat/completions";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

// Available Wafer models (as of 2026-05): GLM-5.1, Qwen3.5-397B-A17B,
// Qwen3.6-35B-A3B, qwen3.6-max-preview.
//
// GLM-5.1 is a direct-response model (not a thinking model). The Qwen3.6
// family puts its chain-of-thought in `reasoning` and leaves `content: null`
// when running in JSON-mode, which doesn't fit our extractor. GLM-5.1 emits
// JSON directly in `content` like a normal OpenAI-style chat completion.
const WAFER_MODEL = "GLM-5.1";
const OPENROUTER_MODEL = "openai/gpt-4o-mini";

/**
 * Call an LLM and return the response. Wafer is tried first; if it errors or
 * returns malformed JSON, we fall back to OpenRouter. Both keys are read from
 * Cloudflare Pages env. If neither is configured the call throws.
 */
export async function chat(req: ChatRequest, env: Env, signal?: AbortSignal): Promise<ChatResult> {
  const body = (model: string) => ({
    model,
    messages: req.messages,
    temperature: req.temperature ?? 0.1,
    // Thinking-style models (GLM-5.1, Qwen3.6) can spend hundreds of tokens
    // in `reasoning_content` before emitting the JSON answer. We need to
    // budget for both. 1500 is a safe ceiling for food parsing.
    max_tokens: req.maxTokens ?? 1500,
    ...(req.responseFormat === "json_object" ? { response_format: { type: "json_object" } } : {})
  });

  if (env.WAFER_API_KEY) {
    try {
      const started = Date.now();
      const res = await fetch(WAFER_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${env.WAFER_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(body(WAFER_MODEL)),
        signal
      });
      if (res.ok) {
        const data = (await res.json()) as {
          choices?: Array<{
            message?: {
              content?: string | null;
              reasoning_content?: string | null;
              reasoning?: string | null;
            };
            finish_reason?: string;
          }>;
        };
        const choice = data?.choices?.[0];
        const msg = choice?.message;
        // GLM-5.1 puts the JSON answer in `content`; thinking-style models
        // (Qwen3.6 family) put work in `reasoning`/`reasoning_content` and
        // leave `content: null`. Fall through to those if needed.
        const content = msg?.content || msg?.reasoning_content || msg?.reasoning;
        if (content && typeof content === "string" && content.trim().length > 0) {
          return {
            content,
            provider: "wafer",
            model: WAFER_MODEL,
            latencyMs: Date.now() - started
          };
        }
        console.log(`[llmClient] Wafer 200 but no usable content (finish_reason=${choice?.finish_reason})`);
      } else {
        console.log(`[llmClient] Wafer non-2xx: ${res.status} ${(await res.text().catch(() => "")).slice(0, 200)}`);
      }
    } catch (e) {
      console.log(`[llmClient] Wafer threw: ${(e as Error).message}`);
    }
  }

  if (env.OPENROUTER_API_KEY) {
    const started = Date.now();
    const res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://vocal.best",
        "X-Title": "VoCal"
      },
      body: JSON.stringify(body(OPENROUTER_MODEL)),
      signal
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      console.log(`[llmClient] OpenRouter non-2xx: ${res.status} ${txt.slice(0, 300)}`);
      throw new Error(`OpenRouter failed: ${res.status} ${txt.slice(0, 200)}`);
    }
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      console.log(`[llmClient] OpenRouter empty: ${JSON.stringify(data).slice(0, 200)}`);
      throw new Error("OpenRouter returned empty content");
    }
    return {
      content,
      provider: "openrouter",
      model: OPENROUTER_MODEL,
      latencyMs: Date.now() - started
    };
  } else {
    console.log("[llmClient] OPENROUTER_API_KEY not set");
  }

  throw new Error("No LLM credentials configured (WAFER_API_KEY or OPENROUTER_API_KEY).");
}

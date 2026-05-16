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

const WAFER_MODEL = "openai/gpt-oss-120b";
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
    max_tokens: req.maxTokens ?? 600,
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
        const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = data.choices?.[0]?.message?.content;
        if (content) {
          return {
            content,
            provider: "wafer",
            model: WAFER_MODEL,
            latencyMs: Date.now() - started
          };
        }
      }
    } catch {
      // fall through to OpenRouter
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
      throw new Error(`OpenRouter failed: ${res.status} ${await res.text().catch(() => "")}`);
    }
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error("OpenRouter returned empty content");
    return {
      content,
      provider: "openrouter",
      model: OPENROUTER_MODEL,
      latencyMs: Date.now() - started
    };
  }

  throw new Error("No LLM credentials configured (WAFER_API_KEY or OPENROUTER_API_KEY).");
}

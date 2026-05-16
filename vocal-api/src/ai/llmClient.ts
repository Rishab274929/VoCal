// Thin shim over `providerPool.callLLM`. Keeps the existing import surface
// (`chat`, `ChatRequest`, `ChatResult`) stable so foodParser.ts and the
// coach endpoint don't have to know about the new multi-provider rotator.

import type { Env } from "../types";
import { callLLM, type ChatMessage, type CallOptions } from "./providerPool";

export type { ChatMessage };

export interface ChatRequest {
  messages: ChatMessage[];
  responseFormat?: "json_object";
  maxTokens?: number;
  temperature?: number;
  needsVision?: boolean;
}

export interface ChatResult {
  content: string;
  provider: string;
  model: string;
  latencyMs: number;
}

/** Call an LLM. Pool rotates Wafer → Gemini → Groq → Mistral → OpenRouter
 * on credit / rate-limit / 5xx errors. Throws only if every configured
 * provider/key combination fails. */
export async function chat(req: ChatRequest, env: Env, signal?: AbortSignal): Promise<ChatResult> {
  const opts: CallOptions = {
    messages: req.messages,
    needsVision: req.needsVision,
    responseFormat: req.responseFormat,
    maxTokens: req.maxTokens,
    temperature: req.temperature
  };
  // `signal` is intentionally unused — Workers' fetch already enforces a
  // platform timeout, and AbortController inside a Worker doesn't propagate
  // cleanly to downstream fetch the way Node would. Left in the signature
  // for source-compat with the prior shape.
  void signal;
  return await callLLM(opts, env);
}

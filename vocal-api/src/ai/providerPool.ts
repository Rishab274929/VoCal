// LLM provider pool with key rotation and automatic failover.
//
// Configure providers via secrets. Each provider supports multiple keys —
// either as numbered env vars (FOO_API_KEY, FOO_API_KEY_2, FOO_API_KEY_3)
// OR comma-separated in a single FOO_API_KEYS plural (whitespace tolerated).
//
// When a key returns 401/402/403/429/5xx the pool rotates to the next key
// for that provider. When every key for a provider is exhausted the pool
// rolls to the next provider. The text and vision pools share this logic
// but differ in which providers they enable.
//
// Free / cheap providers wired in:
//   - Wafer Pass    — flat-rate, GLM-5.1 (vision-capable)
//   - Google Gemini — free tier ~1500 req/day Flash, vision-capable
//   - Groq          — free tier, blazingly fast Llama 3.x (text only)
//   - Mistral       — free tier, mistral-small/large (text only)
//   - OpenRouter    — pay-as-you-go, multi-provider gateway
//
// Add your maroon26 Wafer referral credits by creating extra accounts and
// pasting their keys into WAFER_API_KEYS (comma-separated). No code change.

import type { Env } from "../types";

// ---------------------------------------------------------------------------
// Key collection
// ---------------------------------------------------------------------------

function collectKeys(env: Env, prefix: string): string[] {
  const keys: string[] = [];
  const seen = new Set<string>();
  const push = (raw: unknown): void => {
    if (typeof raw !== "string") return;
    for (const k of raw.split(",")) {
      const trimmed = k.trim();
      if (trimmed && !seen.has(trimmed)) {
        seen.add(trimmed);
        keys.push(trimmed);
      }
    }
  };
  const bag = env as unknown as Record<string, unknown>;
  // Plural FOO_API_KEYS — preferred for bulk seeding.
  push(bag[`${prefix}_API_KEYS`]);
  // Singular FOO_API_KEY plus numbered FOO_API_KEY_2 .. FOO_API_KEY_20.
  push(bag[`${prefix}_API_KEY`]);
  for (let i = 2; i <= 20; i++) push(bag[`${prefix}_API_KEY_${i}`]);
  return keys;
}

// ---------------------------------------------------------------------------
// Provider adapters
// ---------------------------------------------------------------------------

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  /** Plain text OR multimodal content array (OpenAI-style). */
  content: string | Array<{ type: "text" | "image_url"; text?: string; image_url?: { url: string } }>;
}

export interface CallOptions {
  messages: ChatMessage[];
  /** True if any message has image content — restricts to vision-capable providers. */
  needsVision?: boolean;
  responseFormat?: "json_object";
  maxTokens?: number;
  temperature?: number;
}

export interface CallResult {
  content: string;
  provider: string;
  model: string;
  latencyMs: number;
}

interface Provider {
  name: string;
  /** Whether this provider can accept image inputs. */
  vision: boolean;
  /** Models to try in order (first wins). */
  models: string[];
  keys: string[];
  call: (key: string, model: string, opts: CallOptions) => Promise<string>;
}

// --- Wafer Pass (OpenAI-compatible, GLM-5.1 is multimodal) -----------------

async function callWafer(key: string, model: string, opts: CallOptions): Promise<string> {
  const res = await fetch("https://pass.wafer.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: opts.messages,
      temperature: opts.temperature ?? 0.1,
      max_tokens: opts.maxTokens ?? 1200,
      ...(opts.responseFormat === "json_object" ? { response_format: { type: "json_object" } } : {})
    })
  });
  if (!res.ok) throw new ProviderError("wafer", res.status, await safeText(res));
  const data = (await res.json()) as {
    choices?: Array<{ message?: {
      content?: string | null;
      reasoning_content?: string | null;
      reasoning?: string | null;
    } }>;
  };
  const msg = data.choices?.[0]?.message;
  const out = msg?.content || msg?.reasoning_content || msg?.reasoning || "";
  if (!out.trim()) throw new ProviderError("wafer", 502, "empty content");
  return out;
}

// --- Google Gemini (free tier, vision-capable) -----------------------------

async function callGemini(key: string, model: string, opts: CallOptions): Promise<string> {
  // Convert OpenAI-style messages to Gemini's content/parts shape.
  const system = opts.messages.find(m => m.role === "system");
  const turns = opts.messages.filter(m => m.role !== "system");
  let droppedImages = 0;
  let attachedImages = 0;
  const contents = turns.map(m => {
    const parts: Array<{ text: string } | { inline_data: { mime_type: string; data: string } }> = [];
    if (typeof m.content === "string") {
      parts.push({ text: m.content });
    } else {
      for (const p of m.content) {
        if (p.type === "text" && p.text) parts.push({ text: p.text });
        if (p.type === "image_url" && p.image_url?.url) {
          // Strip data: prefix. Gemini only accepts inline base64; remote URLs
          // are not supported. If the URL isn't a data: URL we have to drop
          // the image — surface that as a provider error so the rotator can
          // try the next provider rather than silently sending text-only.
          const url = p.image_url.url;
          const match = url.match(/^data:(.+?);base64,(.+)$/);
          if (match) {
            parts.push({ inline_data: { mime_type: match[1], data: match[2] } });
            attachedImages++;
          } else {
            droppedImages++;
          }
        }
      }
    }
    return {
      role: m.role === "assistant" ? "model" : "user",
      parts
    };
  });
  if (droppedImages > 0 && attachedImages === 0) {
    // Caller asked for vision but every image was un-attachable. Throw a
    // non-rotatable error — re-trying the same payload on another Gemini key
    // won't help.
    throw new ProviderError("gemini", 400, "all images were non-data-URL; cannot attach");
  }

  const body: Record<string, unknown> = {
    contents,
    generationConfig: {
      temperature: opts.temperature ?? 0.1,
      maxOutputTokens: opts.maxTokens ?? 1200,
      ...(opts.responseFormat === "json_object" ? { responseMimeType: "application/json" } : {})
    }
  };
  if (system && typeof system.content === "string") {
    body.systemInstruction = { parts: [{ text: system.content }] };
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(key)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new ProviderError("gemini", res.status, await safeText(res));
  const data = (await res.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const out = data.candidates?.[0]?.content?.parts?.map(p => p.text ?? "").join("") ?? "";
  if (!out.trim()) throw new ProviderError("gemini", 502, "empty content");
  return out;
}

// --- Groq (OpenAI-compatible, super fast, text-only) -----------------------

async function callGroq(key: string, model: string, opts: CallOptions): Promise<string> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: opts.messages.map(stringifyMessage),
      temperature: opts.temperature ?? 0.1,
      max_tokens: opts.maxTokens ?? 1200,
      ...(opts.responseFormat === "json_object" ? { response_format: { type: "json_object" } } : {})
    })
  });
  if (!res.ok) throw new ProviderError("groq", res.status, await safeText(res));
  const data = (await res.json()) as { choices?: Array<{ message?: { content?: string | null } }> };
  const out = data.choices?.[0]?.message?.content?.trim() ?? "";
  if (!out) throw new ProviderError("groq", 502, "empty content");
  return out;
}

// --- Mistral La Plateforme (OpenAI-compatible) ------------------------------

async function callMistral(key: string, model: string, opts: CallOptions): Promise<string> {
  const res = await fetch("https://api.mistral.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: opts.messages.map(stringifyMessage),
      temperature: opts.temperature ?? 0.1,
      max_tokens: opts.maxTokens ?? 1200,
      ...(opts.responseFormat === "json_object" ? { response_format: { type: "json_object" } } : {})
    })
  });
  if (!res.ok) throw new ProviderError("mistral", res.status, await safeText(res));
  const data = (await res.json()) as { choices?: Array<{ message?: { content?: string | null } }> };
  const out = data.choices?.[0]?.message?.content?.trim() ?? "";
  if (!out) throw new ProviderError("mistral", 502, "empty content");
  return out;
}

// --- OpenRouter (multi-provider gateway) -----------------------------------

async function callOpenRouter(key: string, model: string, opts: CallOptions): Promise<string> {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${key}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://vocal.best",
      "X-Title": "VoCal"
    },
    body: JSON.stringify({
      model,
      messages: opts.messages,
      temperature: opts.temperature ?? 0.1,
      max_tokens: opts.maxTokens ?? 1200,
      ...(opts.responseFormat === "json_object" ? { response_format: { type: "json_object" } } : {})
    })
  });
  if (!res.ok) throw new ProviderError("openrouter", res.status, await safeText(res));
  const data = (await res.json()) as { choices?: Array<{ message?: { content?: string | null } }> };
  const out = data.choices?.[0]?.message?.content?.trim() ?? "";
  if (!out) throw new ProviderError("openrouter", 502, "empty content");
  return out;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class ProviderError extends Error {
  constructor(public provider: string, public status: number, public detail: string) {
    super(`${provider} ${status}: ${detail.slice(0, 200)}`);
  }
}

async function safeText(res: Response): Promise<string> {
  try { return await res.text(); } catch { return ""; }
}

function stringifyMessage(m: ChatMessage): { role: string; content: string } {
  if (typeof m.content === "string") return { role: m.role, content: m.content };
  // Text-only providers can't take image parts. Drop images, keep text.
  // If the message was image-only, leave a marker so the upstream gets a
  // non-empty content and a clear hint that we routed a vision request to
  // a text provider by mistake (the caller should set needsVision=true).
  const text = m.content.filter(p => p.type === "text").map(p => p.text ?? "").join("\n").trim();
  return {
    role: m.role,
    content: text || "[image content omitted — text-only provider; caller must set needsVision]"
  };
}

function isRotatableStatus(status: number): boolean {
  // 401 = bad key. 402 = out of credit. 403 = rate-limited/banned key.
  // 408 = timeout. 429 = per-minute / per-day rate limit. 5xx = upstream issue.
  return status === 401 || status === 402 || status === 403
      || status === 408 || status === 429
      || (status >= 500 && status <= 599);
}

// ---------------------------------------------------------------------------
// Public entry
// ---------------------------------------------------------------------------

/** Build the provider list. Order = preference.
 *  ALL providers use free tiers only — no paid models. */
function buildProviders(env: Env): Provider[] {
  return [
    {
      name: "gemini",
      vision: true,
      // Free tier: ~1500 req/day. Best free vision model available.
      models: ["gemini-2.5-flash", "gemini-1.5-flash"],
      keys: collectKeys(env, "GEMINI"),
      call: callGemini
    },
    {
      name: "wafer",
      vision: true,
      // Referral credits — free until exhausted.
      models: ["GLM-5.1"],
      keys: collectKeys(env, "WAFER"),
      call: callWafer
    },
    {
      name: "groq",
      vision: false,
      // Free tier: ~14,400 req/day. Extremely fast. Text-only.
      models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
      keys: collectKeys(env, "GROQ"),
      call: callGroq
    },
    {
      name: "mistral",
      vision: false,
      // Free tier available. Text-only.
      models: ["mistral-small-latest"],
      keys: collectKeys(env, "MISTRAL"),
      call: callMistral
    },
    {
      name: "openrouter",
      vision: true,
      // ALL :free models — zero cost regardless of account balance.
      models: [
        "google/gemma-4-31b-it:free",
        "google/gemma-4-26b-a4b-it:free",
        "nvidia/nemotron-nano-12b-v2-vl:free"
      ],
      keys: collectKeys(env, "OPENROUTER"),
      call: callOpenRouter
    }
  ];
}

/**
 * Run a chat call with automatic provider + key rotation. Throws only if
 * every configured provider/key combination fails.
 */
export async function callLLM(opts: CallOptions, env: Env): Promise<CallResult> {
  const providers = buildProviders(env);
  const errors: string[] = [];

  for (const provider of providers) {
    if (opts.needsVision && !provider.vision) continue;
    if (provider.keys.length === 0) continue;
    let bailProvider = false;
    keyLoop: for (const key of provider.keys) {
      for (const model of provider.models) {
        const started = Date.now();
        try {
          const content = await provider.call(key, model, opts);
          return { content, provider: provider.name, model, latencyMs: Date.now() - started };
        } catch (err) {
          const e = err as ProviderError;
          errors.push(`${provider.name}/${model}/${maskKey(key)}: ${e.message}`);
          // For non-rotatable errors (e.g. 400 bad request, 404 model not found)
          // the same payload will fail on EVERY key+model for this provider —
          // bail out of both the model loop and the key loop. Without the
          // labeled break we'd waste every key on a payload-side bug.
          if (e instanceof ProviderError && !isRotatableStatus(e.status)) {
            bailProvider = true;
            break keyLoop;
          }
        }
      }
    }
    void bailProvider;
  }

  throw new Error(`All providers exhausted. Last errors: ${errors.slice(-3).join(" | ")}`);
}

function maskKey(key: string): string {
  if (key.length < 8) return "***";
  return `${key.slice(0, 4)}…${key.slice(-3)}`;
}

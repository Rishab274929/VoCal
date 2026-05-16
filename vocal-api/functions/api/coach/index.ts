// POST /api/coach
//
// Conversational nutrition coach. The iOS app sends:
//   { prompt, history[], totals? }
//
// We forward to the same LLM (Wafer GLM-5.1) used by /api/voice/parse,
// with a coach-specific system prompt that grounds the reply in the
// user's day. Replies are 1-3 sentences, conversational (read aloud
// via AVSpeechSynthesizer on the iOS side), and never moralizing.
//
// Falls back to a heuristic reply if the LLM is unavailable — covers
// the killer-demo path on a dead network.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env } from "../../../src/types";
import { chat } from "../../../src/ai/llmClient";
import { authIdentity, resolveUserId } from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

interface Totals {
  calorie_goal: number;
  calories_eaten: number;
  protein_goal: number;
  protein_eaten: number;
  carbs_goal: number;
  carbs_eaten: number;
  fat_goal: number;
  fat_eaten: number;
}
interface HistoryTurn { role: "user" | "assistant"; content: string; }
interface CoachBody {
  prompt?: string;
  history?: HistoryTurn[];
  totals?: Totals;
  // Legacy support — older iOS clients sent just { user_id, prompt } and
  // expected the server to fetch totals from D1.
  user_id?: string;
}

const SYSTEM_PROMPT = `You are VoCal's nutrition coach. The user is mid-day,
juggling protein and calories. Respond in 1-3 sentences, conversationally,
the way a sports dietitian would — friendly but direct. Use real numbers
from the day-state context when available; suggest specific menu items
from common chains (Cava, Chick-fil-A, Chipotle, Starbucks) when relevant.

Rules:
- Never moralize about food choices. The user knows what they ate.
- Never invent macros for a meal you weren't told about.
- If the user asks something open-ended, ASK one clarifying question
  back rather than guessing.
- Keep replies short enough to be spoken aloud (~30 words).
- Output plain text. Do not wrap in JSON or markdown.`;

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  // Rate limit: 30/min/identity. Coach replies hit the LLM every time,
  // so an unattended client looping on a chat box is the main risk.
  const rl = await checkRateLimit(env, request, "coach", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  // Size cap — coach payloads include a history array but should never exceed
  // a few KB. 64KB is comfortable headroom and stops malicious giant bodies.
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > 64 * 1024) {
    return json({ error: "Request body too large" }, 413);
  }
  let body: CoachBody;
  try {
    body = (await request.json()) as CoachBody;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const rawPrompt = (body.prompt ?? "").trim();
  if (!rawPrompt) return json({ error: "prompt required" }, 400);
  // Cap prompt length — 2000 chars is more than any natural coach question and
  // stops malicious payloads from blowing through the LLM context budget.
  const prompt = rawPrompt.slice(0, 2000);

  // --- Day-state context line (either from request or D1 fallback) ---
  let context = "";
  let fallbackTotals: Totals | undefined = body.totals;
  if (body.totals) {
    const t = body.totals;
    const kcalLeft = Math.max(0, t.calorie_goal - t.calories_eaten);
    const proteinShort = Math.max(0, t.protein_goal - t.protein_eaten);
    context = `Day so far: ${t.calories_eaten} of ${t.calorie_goal} kcal (${kcalLeft} left). Protein ${t.protein_eaten} of ${t.protein_goal}g (${proteinShort}g short). Carbs ${t.carbs_eaten}g, fat ${t.fat_eaten}g.`;
  } else {
    const bindings = env as unknown as { DB?: D1Database; JWT_SECRET?: string };
    if (bindings.DB) {
      try {
        // Prefer JWT identity for who-am-I; fall back to body.user_id for
        // legacy clients. Without auth we should NOT happily serve another
        // user's row — but for back-compat we keep the path and log it.
        const identity = await authIdentity(request, bindings);
        const { userId, mismatch } = resolveUserId(identity, body.user_id);
        if (mismatch) {
          console.warn("coach: rejecting client user_id, using JWT sub", { jwt: identity.userId, claimed: body.user_id });
        }
        const startTs = new Date(); startTs.setHours(0, 0, 0, 0);
        const row = await bindings.DB.prepare(
          `SELECT COALESCE(SUM(kcal),0) AS k, COALESCE(SUM(protein_g),0) AS p, COUNT(*) AS c
           FROM meals WHERE user_id = ?1 AND logged_at >= ?2`
        ).bind(userId, startTs.getTime()).first<{ k: number; p: number; c: number }>();
        if (row) {
          context = `Day so far: ${row.k ?? 0} kcal across ${row.c ?? 0} meals; ${row.p ?? 0}g protein.`;
          fallbackTotals = {
            calorie_goal: 2200, calories_eaten: row.k ?? 0,
            protein_goal: 160,  protein_eaten: row.p ?? 0,
            carbs_goal: 240,    carbs_eaten: 0,
            fat_goal: 70,       fat_eaten: 0
          };
        }
      } catch { /* swallow */ }
    }
  }

  // --- Call the LLM ---
  const messages: Array<{ role: "system" | "user" | "assistant"; content: string }> = [
    { role: "system", content: SYSTEM_PROMPT }
  ];
  if (context) messages.push({ role: "system", content: `Context — ${context}` });
  // Validate each history turn: drop malformed entries, cap per-turn content
  // length, and limit total turns. Untrusted history is the classic vector
  // for prompt-injection (a malicious client could inject a fake assistant
  // turn that says "ignore previous instructions"). We can't prevent that
  // since the user controls their own client, but we can keep it bounded.
  const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
  for (const turn of history) {
    if (!turn || (turn.role !== "user" && turn.role !== "assistant")) continue;
    if (typeof turn.content !== "string") continue;
    messages.push({ role: turn.role, content: turn.content.slice(0, 1500) });
  }
  messages.push({ role: "user", content: prompt });

  try {
    const result = await chat({ messages, maxTokens: 220, temperature: 0.4 }, env);
    const reply = stripJsonNoise(result.content);
    return json({ reply, provider: result.provider, model: result.model, latencyMs: result.latencyMs }, 200);
  } catch (err) {
    // Log the provider error for observability, but don't echo it to the
    // client — provider failures can include key fragments or internal URLs.
    console.error("coach: all providers failed", (err as Error).message);
    return json({
      reply: heuristic(prompt, fallbackTotals),
      provider: "fallback"
    }, 200);
  }
};

function stripJsonNoise(content: string): string {
  // Some thinking models reply with chain-of-thought + JSON. Pull out the
  // most likely "final answer" line.
  const fenced = content.match(/```(?:json|markdown)?\s*([\s\S]*?)```/);
  let text = (fenced?.[1] ?? content).trim();
  // If the model wrapped the answer in { "reply": "..." }, unwrap it.
  const objMatch = text.match(/^\{[\s\S]*"reply"\s*:\s*"([\s\S]+?)"[\s\S]*\}$/);
  if (objMatch?.[1]) text = objMatch[1];
  // Drop leading "Assistant:" or "Coach:" prefixes.
  text = text.replace(/^(assistant|coach)\s*:\s*/i, "");
  return text;
}

function heuristic(prompt: string, t: Totals | undefined): string {
  const lower = prompt.toLowerCase();
  const kcalLeft = t ? Math.max(0, t.calorie_goal - t.calories_eaten) : 1200;
  const proteinShort = t ? Math.max(0, t.protein_goal - t.protein_eaten) : 60;
  if (lower.includes("protein")) {
    return `You have ${kcalLeft} kcal left and you're ${proteinShort}g short on protein. Try Cava's grilled chicken bowl (~520 kcal, 42g protein).`;
  }
  if (lower.includes("pasta") || lower.includes("dinner")) {
    return `With ${kcalLeft} kcal to play with, a 2-cup pasta pomodoro is ~560 kcal. Add 4 oz grilled chicken (~190 kcal, 35g protein) and you're under budget.`;
  }
  if (lower.includes("hungry") || lower.includes("snack")) {
    return `Likely a protein gap. Greek yogurt + a handful of almonds (~250 kcal, 18g protein) usually does it.`;
  }
  return `So far: ${t?.calories_eaten ?? 0} kcal eaten, ${kcalLeft} left, ${t?.protein_eaten ?? 0}g protein. What are you thinking of?`;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}

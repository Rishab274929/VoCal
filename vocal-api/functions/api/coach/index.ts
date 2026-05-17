// POST /api/coach
//
// Conversational nutrition coach. iOS sends:
//   { prompt, history[], totals? }
//
// We forward to the same LLM (Wafer GLM-5.1) used by /api/voice/parse,
// with a coach-specific system prompt that grounds the reply in the
// user's actual day — today's totals + the last few meals by name +
// the recent coach conversation. Replies are 1-3 sentences, spoken
// aloud by AVSpeechSynthesizer / ElevenLabs on the client.
//
// Memory: we persist each turn to the `coach_messages` D1 table and on
// every request we reload the last 20 stored turns. Local client state
// is opportunistic; the server is the source of truth so a new device
// or a wiped install still gets the conversation context.
//
// Falls back to a heuristic reply if every LLM provider fails.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env } from "../../../src/types";
import { chat } from "../../../src/ai/llmClient";
import { AuthRequiredError, authErrorResponse, requireUserId } from "../../../src/lib/auth";
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
  // Legacy support — older iOS clients sent { user_id, prompt }. We now
  // require a bearer token, but accept the field for forward compat.
  user_id?: string;
}

// Aggressive grounding — the previous prompt was too vague and the model
// defaulted to "here's a generic high-protein lunch idea" no matter what
// the user asked. Now we point at the actual logged meals and forbid
// generic suggestions.
const SYSTEM_PROMPT = `You are VoCal, the user's calorie + macro coach. You
KNOW what they ate today and recently — refer to those meals by name in your
reply. Respond in 1-3 sentences, conversational, the way a sports dietitian
would. Spoken aloud, so under ~35 words.

Hard rules:
- Use the actual numbers from the day-state context. If protein is short
  by 40g, say "you're 40g short on protein", not "you should eat more protein".
- Suggest specific foods or restaurants the user has logged from before
  (you'll see them in the context). For example, if they've eaten Chipotle
  this week, recommend Chipotle items by name; if Cava, suggest a Cava bowl.
- NEVER default to a generic "here's a high-protein lunch idea" — that's lazy.
  Either ground in the user's history or ask a single short clarifying
  question.
- Do NOT moralize about food choices. The user knows what they ate.
- Do NOT invent macros for a meal you weren't told about.
- If the user asks something off-topic (weather, sports, code), redirect
  gently in one sentence back to nutrition / macros.
- Output plain text. No JSON, no markdown, no headings.`;

// Soft cap so we don't blow the LLM context budget. 20 server-loaded turns
// + up to 8 client-supplied turns is plenty of memory for a same-day chat.
const MAX_SERVER_HISTORY = 20;
const MAX_CLIENT_HISTORY = 8;
// How many recent meals to surface by name in the context block. The aim
// is "enough that the model can pattern-match the user's preferences"
// without bloating the prompt.
const RECENT_MEALS_FOR_CONTEXT = 12;

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const bindings = env as unknown as Env & { DB?: D1Database; JWT_SECRET?: string; FOOD_KV?: KVNamespace };

  // Rate limit: 30/min/identity.
  const rl = await checkRateLimit(bindings, request, "coach", 30);
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

  // Hard-require a bearer JWT now. body.user_id is accepted only for the
  // mismatch warning inside requireUserId.
  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request, body.user_id));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // --- Build grounded context: today's totals + recent meals by name -------
  let context = "";
  let recentMealNames: string[] = [];
  let fallbackTotals: Totals | undefined = body.totals;

  if (body.totals) {
    const t = body.totals;
    const kcalLeft = Math.max(0, t.calorie_goal - t.calories_eaten);
    const proteinShort = Math.max(0, t.protein_goal - t.protein_eaten);
    context = `Day so far: ${t.calories_eaten} of ${t.calorie_goal} kcal (${kcalLeft} left). Protein ${t.protein_eaten} of ${t.protein_goal}g (${proteinShort}g short). Carbs ${t.carbs_eaten}g, fat ${t.fat_eaten}g.`;
  } else if (bindings.DB) {
    try {
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
    } catch (err) {
      console.warn("coach: totals lookup failed", (err as Error).message);
    }
  }

  // Recent meals by name — this is the lever that makes replies non-generic.
  // We pull from the last ~10 days so the model has signal on the user's
  // actual rotation (Chipotle, Cava, Sweetgreen, etc.) without including
  // every meal they've ever logged.
  if (bindings.DB) {
    try {
      const tenDaysAgo = Date.now() - 10 * 24 * 60 * 60 * 1000;
      const { results } = await bindings.DB.prepare(
        `SELECT name FROM meals WHERE user_id = ?1 AND logged_at >= ?2
         ORDER BY logged_at DESC LIMIT ?3`
      ).bind(userId, tenDaysAgo, RECENT_MEALS_FOR_CONTEXT).all<{ name: string }>();
      recentMealNames = (results ?? [])
        .map(r => (r.name ?? "").trim())
        .filter(Boolean);
    } catch (err) {
      console.warn("coach: recent meals lookup failed", (err as Error).message);
    }
  }

  // --- Load persisted coach history ----------------------------------------
  // We DESC for the lookup (cheap with the index) then reverse to chronological
  // order before sending to the LLM.
  let serverHistory: HistoryTurn[] = [];
  if (bindings.DB) {
    try {
      const { results } = await bindings.DB.prepare(
        `SELECT role, content FROM coach_messages
         WHERE user_id = ?1 ORDER BY created_at DESC LIMIT ?2`
      ).bind(userId, MAX_SERVER_HISTORY).all<{ role: string; content: string }>();
      serverHistory = (results ?? [])
        .reverse()
        .filter(r => r.role === "user" || r.role === "assistant")
        .map(r => ({ role: r.role as "user" | "assistant", content: r.content }));
    } catch (err) {
      console.warn("coach: history lookup failed", (err as Error).message);
    }
  }

  // Client-supplied history: validate + clamp.
  const clientHistoryRaw = Array.isArray(body.history) ? body.history.slice(-MAX_CLIENT_HISTORY) : [];
  const clientHistory: HistoryTurn[] = [];
  for (const turn of clientHistoryRaw) {
    if (!turn || (turn.role !== "user" && turn.role !== "assistant")) continue;
    if (typeof turn.content !== "string") continue;
    clientHistory.push({ role: turn.role, content: turn.content.slice(0, 1500) });
  }

  // Dedupe: client history often re-sends turns the server already stored
  // (the iOS app keeps a local mirror). Filter out any server turn that
  // matches a client turn by (role + content) signature.
  const clientSig = new Set(clientHistory.map(t => `${t.role} ${t.content}`));
  const mergedHistory: HistoryTurn[] = [
    ...serverHistory.filter(t => !clientSig.has(`${t.role} ${t.content}`)),
    ...clientHistory
  ];

  // --- Build the message list ----------------------------------------------
  const messages: Array<{ role: "system" | "user" | "assistant"; content: string }> = [
    { role: "system", content: SYSTEM_PROMPT }
  ];
  if (context) messages.push({ role: "system", content: `Context — ${context}` });
  if (recentMealNames.length > 0) {
    messages.push({
      role: "system",
      content: `Recent meals (most recent first): ${recentMealNames.slice(0, RECENT_MEALS_FOR_CONTEXT).join("; ")}.`
    });
  }
  for (const turn of mergedHistory) {
    messages.push({ role: turn.role, content: turn.content });
  }
  messages.push({ role: "user", content: prompt });

  // --- Call the LLM ---------------------------------------------------------
  let reply: string;
  let provider = "fallback";
  let model = "";
  let latencyMs = 0;
  try {
    const result = await chat({ messages, maxTokens: 220, temperature: 0.4 }, env);
    reply = stripJsonNoise(result.content);
    provider = result.provider;
    model = result.model;
    latencyMs = result.latencyMs;
  } catch (err) {
    console.error("coach: all providers failed", (err as Error).message);
    reply = heuristic(prompt, fallbackTotals);
  }

  // --- Persist BOTH turns (user + assistant) so the next call sees them ----
  // Best-effort: a write failure here MUST NOT break the response. The
  // alternative — failing the whole request because we couldn't journal
  // the turn — would leave the user with no reply at all.
  if (bindings.DB) {
    const now = Date.now();
    try {
      await bindings.DB.prepare(
        `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)`
      ).bind(userId, "VoCal User", now, now).run();
      // Use the D1 batch to write both turns atomically — saves a round trip
      // and avoids the case where the user turn lands but the reply turn
      // doesn't, leaving an unanswered question in the journal.
      await bindings.DB.batch([
        bindings.DB.prepare(
          `INSERT INTO coach_messages (id, user_id, role, content, created_at) VALUES (?1, ?2, ?3, ?4, ?5)`
        ).bind(crypto.randomUUID(), userId, "user", prompt.slice(0, 2000), now),
        bindings.DB.prepare(
          `INSERT INTO coach_messages (id, user_id, role, content, created_at) VALUES (?1, ?2, ?3, ?4, ?5)`
        ).bind(crypto.randomUUID(), userId, "assistant", reply.slice(0, 2000), now + 1)
      ]);
    } catch (err) {
      console.error("coach: persist failed", (err as Error).message);
    }
  }

  return json({ reply, provider, model, latencyMs }, 200);
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

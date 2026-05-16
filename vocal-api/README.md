# vocal-api

Cloudflare Pages backend for [VoCal](../VoCal). Hosts the static landing site
under `vocal-web/dist/` and the API under `functions/api/`.

## What this fixes

The previously deployed `vocal.best/api/voice/parse` only matched 4 phrases
(McDonald's medium fries, Starbucks oat latte, Chipotle bowl, "scrambled eggs
and toast") and returned a 450 kcal stub for everything else. This rewrite
adds a real resolution pipeline:

1. **KV cache** (optional binding `FOOD_KV`) — 30-day TTL, instant returns.
2. **Chipotle bowl special case** — supports the killer-demo follow-up flow.
3. **Chain canon** — curated nutrition for McDonald's, Starbucks, Chick-fil-A,
   Burger King, Subway, Taco Bell. Deterministic and fast.
4. **LLM resolver** — Wafer first (`openai/gpt-oss-120b`), OpenRouter fallback
   (`openai/gpt-4o-mini`). JSON-mode output, strict validation, 0.1 temp.
5. **USDA FDC** — final structured fallback if LLM unavailable.
6. **Generic 450 kcal stub** — only when nothing else has any signal.

## Local development

```bash
cd vocal-api
npm install
cp .dev.vars.example .dev.vars   # fill in keys
npm run dev                       # wrangler pages dev on :8788
```

Then in the iOS app, set `VOCAL_API_BASE_URL=http://localhost:8788/api` in the
scheme env so the device hits your local build.

## Required secrets

Set in Cloudflare Pages dashboard → Settings → Environment variables → Secrets:

- `WAFER_API_KEY` — flat-rate gateway for open-source LLMs (recommended first
  choice). Sign up at https://pass.wafer.ai
- `OPENROUTER_API_KEY` — fallback. https://openrouter.ai/keys
- `USDA_FDC_API_KEY` — optional but useful. Free key at
  https://fdc.nal.usda.gov/api-key-signup

Optional bindings:

- `FOOD_KV` — KV namespace for the 30-day meal cache
- `DB` — D1 database for persistent meal logging

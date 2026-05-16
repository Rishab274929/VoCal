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

- `FOOD_KV` — KV namespace. Used for the 30-day meal cache **and** for the
  per-minute rate limiter (`src/lib/rateLimit.ts`). Without it the limiter
  fails open, which is fine for local dev but not for production.
- `DB` — D1 database for persistent meal logging

## Auth endpoints

Three providers are wired in:

- `/api/auth/anonymous` — device-bound 1h session (no secrets required).
- `/api/auth/google` — requires `GOOGLE_CLIENT_ID_*` (at least one) +
  `JWT_SECRET`.
- `/api/auth/apple` — requires `APPLE_BUNDLE_ID` + `JWT_SECRET`. The
  audience check is non-negotiable; without `APPLE_BUNDLE_ID` set the
  endpoint returns 503.

Both Google and Apple accept optional `link_anonymous_user_id` +
`link_anonymous_token` body fields to merge an anon session's
meals / body_metrics / coach_messages into the new authenticated
identity. The merge helper lives in `src/lib/identityMerge.ts`.

## D1 schema

The schema is in `db/migrations/0001_initial.sql`. The `body_metrics`,
`meals`, and `coach_messages` tables are all referenced by the identity
merge helper — if you apply only a subset of migrations, the helper falls
back to a meals-only merge with a warning logged. Apply with:

```bash
wrangler d1 migrations apply <db-name>
```

## Rate limiting

`src/lib/rateLimit.ts` is a KV-backed minute-bucket limiter. Limits per
endpoint:

| Endpoint            | Limit               |
|---------------------|---------------------|
| `/api/photo/parse`  | 30 / min / identity |
| `/api/voice/parse`  | 60 / min / identity |
| `/api/coach`        | 30 / min / identity |
| `/api/bodyfat`      | 10 / min / identity |
| `/api/auth/*`       | 20 / min / IP       |

When a caller exceeds the limit they get a 429 with a `Retry-After` header
and a body of `{ "error": "rate_limited", "retry_after_sec": N }`.

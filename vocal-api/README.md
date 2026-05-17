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
- `ELEVENLABS_API_KEYS` — comma-separated list of ElevenLabs API keys for
  `/api/coach/voice` TTS. The endpoint rotates on 401/402/429/5xx. Single-key
  callers can set `ELEVENLABS_API_KEY` instead.
- `ELEVENLABS_VOICE_ID` (optional) — override the default voice ID
  (`pNInz6obpgDQGcFmaJgB`, Adam).

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

### Hard-required vs soft-required bearer auth

`src/lib/auth.ts` exposes two helpers:

- `resolveUserId(identity, bodyUserId)` — soft fallback. Prefers a verified
  JWT, then a body-supplied `user_id`, then `"demo-user"`. Used by parser
  endpoints whose D1 write is best-effort.
- `requireUserId(env, request, bodyUserId?)` — hard-required. Throws
  `AuthRequiredError` if the Authorization header is missing or the JWT
  fails to verify. Use `authErrorResponse(err, corsHeaders)` to return the
  standard 401 + `WWW-Authenticate: Bearer` body.

| Endpoint                          | Auth          |
|-----------------------------------|---------------|
| `GET  /api/meals`                 | hard-required |
| `POST /api/meals`                 | hard-required |
| `PATCH /api/meals/:id`            | hard-required |
| `DELETE /api/meals/:id`           | hard-required |
| `POST /api/coach`                 | hard + **Pro** |
| `POST /api/coach/voice`           | hard + **Pro** |
| `POST /api/bodyfat`               | hard + **Pro** |
| `POST /api/voice/parse`           | hard + **Pro** |
| `POST /api/photo/parse`           | hard + **Pro** |
| `POST /api/entitlements/refresh`  | hard-required |
| `GET  /api/barcode/:code`         | soft (public lookup) |
| `POST /api/auth/*`                | none (mint tokens) |

Hard-required endpoints return `401 { "error": "auth_required" \| "auth_invalid", "detail": "..." }`
with a `WWW-Authenticate: Bearer realm="vocal-api"` header. Old clients
that still send `body.user_id` without a bearer token will see a 401 — a
deliberate cutover.

## D1 schema

The schema is in `db/migrations/`. Migrations are additive — apply in
numeric order:

- `0001_initial.sql` — `users`, `meals`, `body_metrics`, `coach_messages`,
  `integrations`.
- `0002_meal_micros.sql` — adds optional `sodium_mg`, `fiber_g`, `sugar_g`,
  `calcium_mg`, `iron_mg` (REAL), `vitamin_c_mg` (REAL), `potassium_mg`
  columns to `meals`. Existing rows are NULL — the iOS / Flutter clients
  treat NULL as "unknown". Applied to vocal-prod on 2026-05-16.
- `0003_user_entitlements.sql` — adds the `user_entitlements` table used
  by `requirePro()` in `src/lib/auth.ts`. Pro-gated endpoints look up
  this row to decide 200 vs 402.
- `0004_user_entitlements_original_tx_id.sql` — adds
  `original_transaction_id` (nullable TEXT) + index. Populated by
  `/api/entitlements/refresh` from Apple's verifyReceipt response.
  Stable across renewals; readies the schema for ASSN V2 webhooks.

Apply with the migrations runner (now that the D1 binding lives at the
top level of `wrangler.toml`):

```bash
wrangler d1 migrations apply vocal-prod --remote
```

Single-file replay is still possible for ad-hoc fixes, but if you go
that route you MUST also insert a row into `d1_migrations` so the
runner stays in sync:

```bash
wrangler d1 execute vocal-prod --remote --file=db/migrations/0005_whatever.sql
wrangler d1 execute vocal-prod --remote \
  --command "INSERT INTO d1_migrations (name) VALUES ('0005_whatever.sql')"
```

### Manually granting Pro (testers / comps)

Until the iOS app ships StoreKit receipt forwarding, populate
`user_entitlements` by hand:

```bash
wrangler d1 execute vocal-prod --remote --command \
  "INSERT INTO user_entitlements (user_id, is_pro, product_id, expires_at, updated_at, source)
   VALUES ('<jwt-sub>', 1, 'com.EricSpencer.VoCal.pro.lifetime', NULL, $(date +%s)000, 'manual')
   ON CONFLICT(user_id) DO UPDATE SET is_pro=1, expires_at=NULL, updated_at=excluded.updated_at, source='manual';"
```

## Pro entitlement gate

Pro-gated endpoints check `user_entitlements` and return **402** with
`{ "error": "pro_required", "reason": "no_row" | "expired" | "not_pro" }`
when the row is absent or inactive. The bearer JWT is hard-required;
anonymous sessions are valid identity but won't have a Pro row, so they
get 402 (not 401).

| Endpoint                | Pro-gated |
|-------------------------|-----------|
| `/api/coach`            | yes       |
| `/api/coach/voice`      | yes       |
| `/api/bodyfat`          | yes       |
| `/api/photo/parse`      | yes       |
| `/api/voice/parse`      | yes       |

### `/api/entitlements/refresh`

iOS posts a base64 StoreKit receipt; we verify it with Apple's
`verifyReceipt` and upsert into `user_entitlements`. Requires
`APPLE_SHARED_SECRET` (App Store Connect → App-Specific Shared Secret);
without it the endpoint returns 503.

## Rate limiting

`src/lib/rateLimit.ts` is a KV-backed minute-bucket limiter. Limits per
endpoint:

| Endpoint                | Limit               |
|-------------------------|---------------------|
| `/api/photo/parse`      | 30 / min / identity |
| `/api/voice/parse`      | 60 / min / identity |
| `/api/coach`            | 30 / min / identity |
| `/api/coach/voice`      | 20 / min / identity |
| `/api/bodyfat`          | 10 / min / identity |
| `/api/meals` (list)     | 30 / min / identity |
| `/api/meals` (create)   | 30 / min / identity |
| `/api/meals/:id` (PATCH/DELETE) | 30 / min / identity (shared bucket) |
| `/api/auth/*`           | 20 / min / IP       |

When a caller exceeds the limit they get a 429 with a `Retry-After` header
and a body of `{ "error": "rate_limited", "retry_after_sec": N }`.

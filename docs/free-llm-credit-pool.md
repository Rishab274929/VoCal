# Free-credit LLM pool — config + maroon26 + scaling notes

VoCal's backend now rotates through **multiple LLM providers + multiple
keys per provider** with automatic failover on 401/402/403/408/429/5xx.
The rotation is implemented in
[`vocal-api/src/ai/providerPool.ts`](../vocal-api/src/ai/providerPool.ts);
every call from `/api/voice/parse`, `/api/coach`, and `/api/photo/parse`
goes through the same pool.

The end result: as long as **any** configured provider has a working key
with credit, the request succeeds.

## Provider order

Preference is hard-coded in `buildProviders()`:

1. **Wafer Pass** (`WAFER_API_KEY*`) — flat-rate, GLM-5.1, multimodal
2. **Google Gemini** (`GEMINI_API_KEY*`) — massive free tier, multimodal
3. **Groq** (`GROQ_API_KEY*`) — free, blazingly fast Llama 3.x (text only)
4. **Mistral La Plateforme** (`MISTRAL_API_KEY*`) — free tier (text only)
5. **OpenRouter** (`OPENROUTER_API_KEY*`) — multi-provider gateway

For the photo endpoint, only providers marked `vision: true` are used
(Wafer, Gemini, OpenRouter).

## Secret naming

Each provider accepts EITHER form — both are merged:

**Numbered**
```
WAFER_API_KEY        = wfr_xxx
WAFER_API_KEY_2      = wfr_yyy
WAFER_API_KEY_3      = wfr_zzz
```

**Plural (comma-separated bulk seed)**
```
WAFER_API_KEYS       = wfr_xxx, wfr_yyy, wfr_zzz, wfr_aaa
```

Same pattern for `OPENROUTER`, `GEMINI`, `GROQ`, `MISTRAL`. Numbered keys
go up to `_API_KEY_20` and dedupe is applied so you can mix both forms
without doubling up.

Set them in Cloudflare Pages → Settings → Environment variables → Secrets,
or via wrangler:

```bash
echo -n "wfr_a,wfr_b,wfr_c" | npx wrangler pages secret put WAFER_API_KEYS --project-name vocal
```

## Free credit playbook

| Provider | Free quota | Sign up |
|---|---|---|
| **Wafer Pass** | Flat-rate via "maroon26" referral code — best for prod | https://pass.wafer.ai (paste maroon26 in the referral field at signup) |
| **Google AI Studio (Gemini)** | ~1,500 req/day Flash, 50 req/day Pro — huge | https://aistudio.google.com/apikey |
| **Groq** | ~14,400 req/day total, 30 req/min/model | https://console.groq.com/keys |
| **Mistral** | ~500K tokens/day on free tier | https://console.mistral.ai/api-keys |
| **OpenRouter** | Pay-as-you-go but you can prepay $10 and get many millions of tokens | https://openrouter.ai/keys |

### Where to drop maroon26

When signing up for a new **Wafer Pass** account:

1. Go to https://pass.wafer.ai/signup
2. During signup, look for the **Referral code** or **Promo code** field
   (sometimes hidden under "Have a code?")
3. Enter **`maroon26`**
4. Complete signup — your new account gets bonus credit applied
5. Create an API key from Dashboard → API keys
6. Append the new key to the existing `WAFER_API_KEYS` secret

Repeat for as many accounts as you want stacked in the pool. The rotator
treats each key as an independent budget — when one runs out (402), it
transparently rolls to the next.

## Scaling notes

- **Most requests stay on Wafer GLM-5.1** because it handles every
  request type we use (JSON-mode food parsing, conversational coach,
  vision photo parse) and we have multi-key flat-rate. Gemini Flash
  free tier is the on-ramp for overflow.
- **Photo requests** are bigger (~50KB-1MB upload) and slower (3-7s
  vision inference). The pool counts these against the same key budget
  — keep eyes on Wafer dashboard.
- **Rate limit kindness**: when a key hits 429 the rotator marks it
  bad and tries the next one in the same provider — but the key isn't
  permanently disabled. The next Worker invocation gets a fresh attempt
  list and may succeed on that key once the rate window resets.
- **Telemetry**: every successful response includes `reasoning` with
  `provider/model` and `latencyMs`. Tail logs with
  `wrangler pages deployment tail <id> --project-name vocal` to see
  which provider served each request.

## Currently-live key state

As of last deploy:

- `WAFER_API_KEY` set — single key, flat-rate active
- `OPENROUTER_API_KEY` set — out of credit (402)
- `GEMINI_API_KEY` **not set** — add one to get free-tier headroom
- `GROQ_API_KEY` **not set** — add one for text-only speed
- `MISTRAL_API_KEY` **not set**

To stress-test the pool, sign up for Gemini + Groq (both 60-second
signups, no card required) and paste both keys into the Pages secrets.
The first time Wafer hits a rate limit, the next call will transparently
land on Gemini instead.

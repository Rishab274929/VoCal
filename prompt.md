# VoCal — Hackathon Spec

**Team:** 4 · **Window:** 18 hours · **Codebase:** `/Users/eric/GitHub/uncommonhacks26/VoCal` · **Domain:** `vocal.best`

---

## 1. Context

**The whole point is voice.** Today: Cal AI is photo-only and can't take a spoken command. MyFitnessPal is typing-only — you can search "McDonald's medium fry" but you have to *type* it. Nobody can just say "**log a medium fry from McDonald's**" and have it work. That's the gap VoCal owns.

Voice unlocks two things photo and typing can't:
1. **Restaurant items by name** — "medium fry from McDonald's," "grande oat milk latte," "Chipotle bowl with double chicken." Agentic search resolves to canonical menu entries with real macros, no scrolling through a database.
2. **Fact-checking what the camera can't see** — secondary use case. Photo gets a first pass; voice fills in what's hidden ("there's rice underneath"). This is the accuracy story.

The hackathon goal is a TestFlight-shippable, paywall-gated app where a judge can hold up their phone, say one sentence about food, and watch it log correctly with real macros — including chain-restaurant items — in under 5 seconds.

The iOS wireframe is already live ([`VoCal/`](VoCal)) with the calorie ring, macro bars, meal log, mic CTA, voice-capture sheet, history, and profile tabs. Build/sign/archive/IPA all pass `-validate-for-store`. This spec scopes the next 18 hours.

---

## 2. The Wedge (what every demo line should land)

| Cal AI | MyFitnessPal | **VoCal** |
|---|---|---|
| Photo only — no voice input | Typing + manual search | **Speak it: "medium fry from McDonald's" → logged in 3 seconds** |
| No restaurant intelligence | Type & scroll a database | **Agentic search across chain menus + USDA** |
| Can't see hidden food | No automation | Photo + voice fact-check: **"Is there rice under the chicken?"** |
| No coaching | Charts only | **Voice nutrition coach you can talk to** |
| Static goals | Static goals | WHOOP/Watch-aware daily targets |

One-liner pitch: **"Just say what you ate. VoCal is the first calorie tracker that actually listens — and knows what's on the menu at McDonald's, Chipotle, and Starbucks without you typing a word."**

---

## 3. Feature List (Tier-ordered, hackathon-realistic)

### Tier 0 — Demo-critical (must ship in 18h)

**1. Voice meal logging — the headline feature.** Tap mic → speak → STT → LLM parses → structured `MealEntry` → log in < 5s. Must handle three input shapes:
   - **Plain food**: "two scrambled eggs and a piece of toast"
   - **Restaurant by name** *(killer demo)*: "medium fry from McDonald's", "grande iced oat latte", "Chipotle bowl with double chicken, brown rice, black beans, guac, salsa"
   - **Approximate / messy**: "a big bowl of pasta with red sauce, maybe two cups"

**2. Restaurant agentic search — the thing nobody else has.** LLM tool-calls `searchRestaurantMenu(brand, item)` against a Cloudflare Vectorize index seeded at deploy time with the menus of the top ~25 US chains: McDonald's, Chipotle, Starbucks, Sweetgreen, Cava, Panera, Subway, Chick-fil-A, Taco Bell, Wendy's, Burger King, Dunkin', Domino's, Pizza Hut, Five Guys, Shake Shack, Panda Express, Olive Garden, KFC, Popeyes, Jersey Mike's, Jimmy John's, In-N-Out, Whataburger, Raising Cane's. Each item has canonical name + calories/macros + portion options ("small/medium/large"). If the LLM can't resolve, fall back to USDA Vectorize index, then web search (Worker-bound fetch).

3. **Today screen.** Calorie ring, macros, recent meals (done in wireframe).
4. **Sign in with Apple → Cloudflare D1 session.** Anonymous-first; upgrade on first save.
5. **Hard paywall after onboarding.** RevenueCat (sandbox) → "VoCal Pro" entitlement. Demo on TestFlight with sandbox accounts so "fake money" flows work for judges.
6. **Photo + voice fact-check loop.** Secondary differentiator. Snap photo → Vision LLM first-pass → AI asks 1–2 follow-up questions ("Is there rice underneath?", "How big — fist, two fists?") → user voice-replies → AI updates estimate → save. The voice answer is the same pipeline as #1; this is just the photo entry point into it.
7. **Body-fat % from photo (real model).** Front + side selfie → vision LLM prompt with height/weight context → BF% estimate + delta over time. Onboarding captures baseline.
8. **Progress tab.** Weight log (manual entry) + calorie/macro trend chart + BF% chart.
9. **Voice nutrition coach.** Chat + TTS voice output. Knows the user's day/week, answers "how do I hit 180g protein tomorrow?" with concrete suggestions. **Voice in, voice out** is the brand consistency story — every interaction in VoCal can be spoken.

### Tier 0 (continued) — Apple ecosystem (in scope per directive: "do all Apple extensions")

10. **App Intents + Siri** — *"Hey Siri, log a medium fry from McDonald's"* hits the same voice pipeline. Massive wow factor; cheap to add once the voice pipeline exists (App Intents just call our LLM endpoint).
11. **HealthKit** — write `dietaryEnergyConsumed`, protein/carbs/fat, body mass, body fat percentage; read steps + active energy to nudge the daily target.
12. **Apple Watch app** (independent target) — voice capture on the watch; either processes locally via WatchConnectivity hand-off or, if Watch has its own cell, hits the API directly. Confirmation haptic + glance.
13. **Watch complication** — calorie ring on the watch face.
14. **Home Screen Widget** — small/medium widget: today's calorie ring + remaining + last meal. iOS 17+ interactive widget = tap-mic shortcut.
15. **Lock Screen Widget** — circular complication for calories remaining.
16. **Live Activity / Dynamic Island** — when a voice log is in flight: shows live transcript, then result with confidence. Stays around for 10s so the user can swipe to edit.
17. **Shortcuts integration** — every App Intent shows up in the Shortcuts app for free, so power users can automate (e.g., "When my Starbucks order completes, log a grande oat latte").

### Tier 1 — Demo-bonus (if a stream finishes early)
18. **Control Center widget (iOS 18+)** — global mic shortcut.
19. **Action Button / Camera Control button** — assignable to "open VoCal mic" via App Intent.
20. **WHOOP integration** — OAuth → pull recovery/strain → bump kcal target ±200 on high-strain days. One-way pull only.
21. **Barcode scan** fallback for packaged food.
22. **Share Extension** — share a meal photo from Photos/Messages to VoCal for logging.

### Tier 2 — Post-hackathon
- Recipe import from Instagram/TikTok URLs
- Meal photo journal with throwbacks
- Macro-aware recipe suggestions
- Social: share streaks / week summaries
- Watch native voice capture (no phone hand-off)
- Coach proactively pings ("you're 40g short on protein, want a suggestion?")

---

## 4. Design System

The current [`Theme.swift`](VoCal/VoCal/Theme.swift) is the source of truth. Formalizing it here so the team writes consistent code.

### Palette

| Token | Hex | Use |
|---|---|---|
| `brand` | `#00B884` | Primary actions, mic button, ring fill, success |
| `brandSoft` | `#00D4AA` | Gradient highlight, hover/pressed lighten |
| `brandDeep` | `#008E70` | Gradient end, dark-mode primary |
| `energy` | `#FF8C4D` | Streak flame, "kcal left" stat, over-budget warning |
| `protein` | `#EE5780` | Protein macro bar |
| `carbs` | `#FCBC32` | Carbs macro bar |
| `fat` | `#6B9EF7` | Fat macro bar |
| `canvas` | systemBackground | Page background (auto dark/light) |
| `surface` | secondarySystemBackground | Card background |
| `hairline` | primary @ 7% opacity | Dividers, ring track |

Gradients: `brandGradient` (brandSoft → brand → brandDeep, top-leading → bottom-trailing). Used on ring, mic, primary CTA, history chart's "today" bar.

### Typography (SF Pro, system default)

- **Hero numbers** (kcal remaining, BF%): `.system(size: 44, weight: .bold, design: .rounded)` + `.monospacedDigit()`
- **Title**: `.title2.weight(.bold)`
- **Section header**: `.title3.weight(.bold)`
- **Body**: `.body` / `.subheadline.weight(.semibold)`
- **Caption/labels**: `.caption` / `.caption2`, uppercase tracking for stat labels

### Shape & motion

- Card radius: 24 continuous (`.Radius.lg`)
- Pill / chip radius: 12 continuous (`.Radius.sm`)
- Mic button: 76pt circle, pulse ring (1.4s ease-out loop, opacity 0.18→0)
- Waveform orb (listening): 5 capsule bars, staggered ease-in-out 0.45–0.75s autoreverses
- Ring progress: 0.6s easeOut on value change; `.contentTransition(.numericText())` on the kcal number
- Sheet detents: `.medium` & `.large` for voice capture; `.medium` only for coach

### Component library (already in `Components.swift`)

`CalorieRing`, `MacroBar`, `MealCard`, `MicButton`, `SectionHeader`. Need to add: `WeightChart`, `BFCard`, `CoachBubble`, `OnboardingStep`, `PaywallSheet`, `FollowUpQuestionCard`.

### Voice / TTS persona

- **Coach voice**: warm, encouraging, not preachy. ElevenLabs voice ID TBD (pick during integration; one masculine + one feminine option in settings). Apple `AVSpeechSynthesizer` with `.allyssa`/`.tom` as no-credits fallback.
- **Follow-up question tone**: short, conversational. "Was there rice under that?" not "Please indicate whether the dish contained rice."

### Empty / error states

- Empty Today log: emerald mic illustration + "Tap to log your first meal."
- Mic permission denied: surface inline with one-tap "Open Settings."
- Network down: cache last 7 days locally; banner "Offline — synced log when reconnected."

---

## 5. Architecture

**Domain:** Everything lives on **`vocal.best`** as a single Cloudflare Pages project with Pages Functions handling the API. No subdomain split — keeps DNS, CORS, and CDN config trivial.

- `vocal.best/` → marketing + ToS + Privacy + Support (static, Astro)
- `vocal.best/api/*` → API (Pages Functions, file-based routing under `functions/api/`)
- iOS app base URL: `https://vocal.best/api`

Cloudflare account: **`27b63de7643a2b3fdbefe3c7bdbbc610`** (espencer2@luc.edu). Wrangler has all required scopes (workers, d1, pages, kv, queues, ai, ai-search/Vectorize, secrets).

```
                     ┌──────────────────────────────────────────────────────────┐
                     │                       iOS App                             │
                     │  SwiftUI · SwiftData · AVFoundation · Speech              │
                     │  HealthKit · WatchConnectivity · WidgetKit · ActivityKit  │
                     │  App Intents · RevenueCat SDK · Keychain                  │
                     │                                                           │
                     │  Targets: VoCal (app) · VoCalWatch · VoCalWidgets ·       │
                     │           VoCalIntents · VoCalShareExt                    │
                     └─────────────┬──────────────────────────┬──────────────────┘
                                   │ HTTPS (JWT)              │ WebSocket (streaming voice)
                                   ▼                          ▼
                     ┌──────────────────────────────────────────────────────────┐
                     │             vocal.best (Cloudflare Pages)                 │
                     │   /                  → static landing (Astro)             │
                     │   /api/auth/*        Pages Functions                      │
                     │   /api/meals/*       Pages Functions                      │
                     │   /api/coach/*       Pages Functions                      │
                     │   /api/bodyfat/*     Pages Functions                      │
                     │   /api/voice/stream  Durable Object (WS)                  │
                     │                  AI Gateway router                        │
                     └───┬─────────┬─────────┬─────────┬─────────┬───────────────┘
                         │         │         │         │         │
                         ▼         ▼         ▼         ▼         ▼
                       D1       R2       KV     Vectorize    Queues
                    (records) (media) (cache) (food+menus)  (async)
                         │
                         └── External (use any inference necessary, scale not a concern):
                             • Claude Sonnet 4.6 (reasoning + vision, primary)
                             • GPT-5 (vision fallback, second opinion)
                             • ElevenLabs Scribe v2 Realtime (STT) + voices (TTS)
                             • Brave Search API (Google-style web search)
                             • Workers AI (embeddings, PDF text extraction)
                             • Wafer (cost-optimization swap for low-stakes calls)
                             • WHOOP API · RevenueCat webhooks · Apple SiwA keys
```

### iOS

- SwiftUI, **iOS 18 minimum** (we're already on iOS 26 deployment target — keep it; gives us `Foundation Models`, `VisionKit`, latest sheet detents).
- SwiftData for the local cache (offline-first; synced to D1 on reconnect). Schema mirrors backend.
- `Speech` framework for on-device STT fallback if ElevenLabs credits don't arrive in time.
- `AVCaptureSession` for camera; we already have iOS 18 PhotoKit access patterns to draw on.
- `WatchConnectivity` for the Watch quick-log handoff (Tier-1).
- `HealthKit` for read steps/active-energy, write meals/weights/BF%.
- `RevenueCat` SDK + sandbox keys; entitlement `vocal_pro`.

### Backend (Cloudflare — all on vocal.best)

Single **Cloudflare Pages project** with Pages Functions under `functions/api/`. Pages Functions have full Workers runtime + every binding (D1, R2, KV, Vectorize, Queues, AI, Durable Objects). One `wrangler pages deploy` ships landing + API together.

- **Pages Functions** (Hono framework, file-based routing). One handler per route under `functions/api/`. Mono-deploy.
- **Durable Object** for the voice WebSocket: streams audio chunks to ElevenLabs Scribe, fans partial transcripts back to iOS, runs the LLM tool-call loop, returns the final `MealEntry`. One DO instance per active mic session, keyed on user+session.
- **D1** for relational data. Schema in §6.
- **R2** for binary blobs: meal photos, body photos. Signed PUT URLs for client upload (no auth token embedded in image data); body photos encrypted at rest with a per-user key.
- **KV** for low-latency caches: USDA lookup results, restaurant menu cache, web-fetch HTML/PDF cache (24h TTL), in-flight LLM tool-call dedupe.
- **Vectorize** — two indexes, both populated at deploy time and refreshed via Queues:
  - `food-usda`: USDA SR-Legacy embeddings (full DB, ~8k items)
  - `restaurant-menus`: top-25 chain menus + scraped/PDF-extracted item data
- **Queues** for async work the user shouldn't wait on: Vectorize updates, WHOOP daily sync, photo post-processing, PDF text extraction.
- **AI Gateway**: single proxy endpoint that routes to Claude / GPT-5 / ElevenLabs / Wafer / Brave Search with caching, rate-limiting, structured logging, and observability. Provider choice per-call by `env.PRIMARY_MODEL` etc. — lets us swap any provider via wrangler secret without code changes.
- **Wrangler config**: `wrangler.toml` declares all bindings; `wrangler pages secret put` for API keys; `wrangler d1 migrations apply vocal-prod` for schema; `wrangler vectorize create` for indexes. Custom domain `vocal.best` attached via `wrangler pages project create vocal && wrangler pages deployment create` once.

### Auth

- **Sign in with Apple** (required for App Store apps that take payment).
- Flow: iOS gets Apple identity token → POST `/auth/apple` → Worker verifies with Apple's public keys → upserts user in D1 → returns short-lived JWT (1h) + refresh.
- **Anonymous mode**: first launch issues a device-bound anon JWT so the user can try voice logging before signup. On first save we surface the SiwA prompt. All anon data is migrated on link.

### AI pipeline

**Voice path (mic → log) — the main pipeline. Optimize this path above all else:**
1. iOS streams 16kHz PCM to the voice Durable Object via WebSocket.
2. DO forwards to ElevenLabs Scribe v2 Realtime (150ms latency); partial transcripts streamed back to iOS for live caption display.
3. On user-tap "stop" (or VAD endpoint): final transcript → Claude Sonnet 4.6 with **food-parser system prompt** + agentic tool loop (ReAct). Tools, ordered by what the LLM is likely to reach for first:
   - `searchRestaurantMenu(brand, item, size?)` → Vectorize over the seeded chain-menu index. **Tried first** when the transcript mentions a brand or chain-sounding name.
   - `searchUsdaDatabase(query)` → Vectorize over USDA SR-Legacy. Tried for plain foods.
   - `googleSearch(query)` → Brave Search API. Used when the LLM needs to find a menu page or nutrition info for an item not in our indexes ("regional burger chain", "specific Sweetgreen seasonal salad", "I had a Bonchon order"). Returns top 5 results with URL + title + snippet.
   - `fetchAndExtract(url)` → Worker-bound `fetch()` → HTML → Readability text extraction. **For PDFs**: detects `application/pdf`, runs through `unpdf` (WASM-friendly PDF text extractor running inside the Worker), returns text. Used because **a lot of chain-restaurant nutrition info is published as PDFs** (e.g., Chick-fil-A nutrition guide, Olive Garden allergen PDF, Panera macros sheet).
   - `lookupBarcode(upc)` → KV/USDA. For Tier-1 barcode flow.
   - `askFollowUp(question, reason)` → returns to client as a follow-up prompt and re-opens the mic.
4. The LLM does an agentic ReAct loop: search → fetch → extract → reason. Each tool result is cached in KV (24h TTL keyed on tool+args hash) so repeat queries are instant.
5. If LLM emits `askFollowUp`, iOS plays the question (ElevenLabs TTS or `AVSpeechSynthesizer` fallback) and re-opens mic for the answer; result loops back into the same LLM context with prior tool results retained.
6. Final structured `MealEntry` JSON → DO writes to D1 + returns to iOS.

**Why this beats Cal AI's static database:** a Cal AI-style lookup hits a static DB and either finds the item or doesn't. Our agentic loop can search Google, fetch the actual restaurant PDF, parse it, and pull the exact macros for *any* item — even seasonal/limited menu items the seed index doesn't know about. The cost per query goes up; per the directive "scale is no issue, use any inference necessary," we accept that trade.

**Latency budget for the killer demo** ("medium fry from McDonald's" → logged):
- STT (final transcript): ~400ms
- LLM tool-call decision + Vectorize query: ~600ms
- LLM JSON output: ~400ms
- D1 write + iOS UI update: ~200ms
- **Total target: < 2 seconds end-to-end.** This is what makes the demo feel magical.

**Photo path (snap → log):**
1. iOS uploads photo to R2 (presigned URL).
2. iOS POSTs `/meals/photo` with R2 key.
3. Worker calls Vision LLM (Wafer-hosted Qwen-VL preferred; OpenAI/Anthropic vision as Pro tier or fallback).
4. Vision LLM returns:
   - First-pass `MealEntry` guess
   - Up to 2 follow-up questions ranked by uncertainty contribution
5. iOS shows guess + speaks first follow-up → loops via voice path.
6. Final structured `MealEntry` → D1.

**Body-fat path:**
1. Front + side selfie → R2.
2. Worker prompts Vision LLM with rendered measurement context (height, weight, sex, age, prior BF%).
3. LLM returns BF% point estimate + confidence band + visual notes.
4. Stored as `BodyMetric` row; chart pulls last N entries.

**Nutrition coach:**
- Chat endpoint with conversation history + a rolling 7-day macro summary in the system prompt.
- Tools: `getDayLog(date)`, `getGoals()`, `suggestMeal(constraints)`.
- TTS via ElevenLabs (Pro) or `AVSpeechSynthesizer` (free).

### Subscriptions

- **RevenueCat** for IAP, entitlements, sandbox testing.
- Products: `vocal_pro_monthly` ($4.99), `vocal_pro_annual` ($39.99). Sandbox mode for hackathon judges.
- Paywall: hard, post-onboarding. Free tier: view history + log 3 meals/day. Pro: everything.
- Server-side: RevenueCat webhook → Worker → flip `users.entitlement` in D1.
- Restore-purchases flow on Settings → Subscription.

### Landing page (vocal.best root)

- **Cloudflare Pages** + Astro (fastest static site).
- Pages: `/` (marketing), `/terms`, `/privacy`, `/support`, `/beta` (TestFlight invite link).
- Required for App Store: Privacy Policy URL + Support URL. **Block on this — App Store Connect won't accept the build for review without them.**
- Lives in the same Pages project as the API, just under `/` instead of `/api/*`. One `wrangler pages deploy ./vocal-web/dist` ships both.

---

### Apple Extensions (full coverage per directive)

The same `vocal-shared` Swift package — exposing `APIClient`, `Session`, models, and `VoCalKit` (the public domain logic) — is depended on by every target. Each extension is a thin layer over this shared kit.

**1. App Intents + Siri.** Define `LogMealByVoiceIntent(spokenText: String)`, `LogMealIntent(name, kcal, …)`, `OpenMicIntent()`, `GetDailyMacrosIntent()`. iOS surfaces these in Siri (no Shortcuts config required), Shortcuts app, Action Button, Camera Control button, and the Spotlight search. The voice intent calls our `/api/voice/parse` endpoint with the spoken text and returns a logged meal. **This is what makes "Hey Siri, log a medium fry from McDonald's" work without ever opening the app.**

**2. HealthKit.** New `VoCalHealth` module wraps HKHealthStore:
- Write on save: `HKQuantityTypeIdentifier.dietaryEnergyConsumed`, `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal`, `.bodyMass`, `.bodyFatPercentage`.
- Read on launch: `.stepCount`, `.activeEnergyBurned` for the last 7 days → factors into the daily goal nudge.
- Permissions prompted during onboarding, gracefully degrades if denied.

**3. Apple Watch app** (`VoCalWatch` target). Independent SwiftUI watchOS app:
- Glance: today's calorie ring (same `CalorieRing` component reused).
- Tap mic complication → record up to 30s → if watch is paired+nearby, send audio via `WCSession.sendMessageData` to phone for processing; if cellular watch, hit `/api/voice/parse` directly.
- Haptic on save (success: `.success`; failure: `.failure`).
- Complications: `.accessoryCircular` (ring), `.accessoryCorner` (kcal remaining), `.accessoryRectangular` (last meal + ring).

**4. Home Screen Widgets** (`VoCalWidgets` extension):
- `TodayMacrosWidget` (small/medium): calorie ring + remaining + macros mini-bars.
- `LastMealWidget` (small/medium): name + kcal + relative time ("logged 12m ago").
- `StreakWidget` (small): flame + N-day streak.
- **Interactive (iOS 17+)**: small ring widget has a tap-target wired to `OpenMicIntent()` — single tap launches the mic without opening the app shell.
- TimelineProvider refreshes every 15 minutes or via `WidgetCenter.reloadAllTimelines()` on save.

**5. Lock Screen Widgets** — same `TodayMacrosWidget` rendered at `.accessoryCircular` and `.accessoryRectangular` families.

**6. Live Activity / Dynamic Island** (`VoCalLiveActivities` via ActivityKit):
- Started when a voice or photo log enters the parsing state.
- Expanded view: transcript stream + spinner. Compact: "VoCal listening…" + animated dot.
- On resolution (≤10s): shows the meal name + kcal for 10 seconds then auto-dismisses.
- User can tap to open the app and edit.

**7. Shortcuts** — every App Intent is automatically exposed. We ship 3 pre-built Shortcuts via `AppShortcutsProvider`:
- "Log meal with voice" → `OpenMicIntent`
- "What are my macros today?" → `GetDailyMacrosIntent` (reads aloud)
- "Log <name>" with parameter → `LogMealByVoiceIntent`

**8. Share Extension** (Tier-1, `VoCalShareExt`): receive an image from Photos/Messages → upload to R2 → pass into the photo logging flow.

**9. Notification Service Extension** (Tier-1): rich notifications for daily reminders ("Don't forget lunch — log it with one tap"). Tappable shortcut → `OpenMicIntent`.

**Target list (Xcode):**
| Target | Type | Min OS |
|---|---|---|
| VoCal | iOS App | iOS 18 |
| VoCalWatch | watchOS App | watchOS 11 |
| VoCalWidgets | Widget Extension | iOS 18 |
| VoCalIntents | App Intents Extension | iOS 18 |
| VoCalLiveActivities | Widget Extension (Activity) | iOS 18 |
| VoCalShareExt | Share Extension | iOS 18 |
| VoCalKit | Shared Swift Package | — |

Re-using `Theme.swift` and `Components.swift` (e.g., `CalorieRing`, `MacroBar`) across every target keeps the visual language consistent on phone, watch, lock screen, widget, and Dynamic Island.

---

## 6. Data Model (D1 schema)

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,              -- uuid
  apple_sub TEXT UNIQUE,            -- Apple subject claim
  display_name TEXT,
  sex TEXT,                         -- 'm' | 'f' | 'x'
  height_in REAL,
  weight_lb REAL,
  birth_date TEXT,
  daily_kcal_goal INT DEFAULT 2200,
  protein_g_goal INT DEFAULT 160,
  carbs_g_goal INT DEFAULT 240,
  fat_g_goal INT DEFAULT 70,
  entitlement TEXT DEFAULT 'free',  -- 'free' | 'pro'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE meals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  detail TEXT,
  kcal INT NOT NULL,
  protein_g INT NOT NULL,
  carbs_g INT NOT NULL,
  fat_g INT NOT NULL,
  slot TEXT NOT NULL,               -- breakfast|lunch|dinner|snack
  source TEXT NOT NULL,             -- voice|photo|voice+photo|manual|barcode
  photo_r2_key TEXT,
  transcript TEXT,
  confidence REAL,                  -- 0..1
  logged_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_meals_user_day ON meals(user_id, logged_at);

CREATE TABLE body_metrics (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  weight_lb REAL,
  body_fat_pct REAL,
  bf_confidence REAL,
  front_r2_key TEXT,
  side_r2_key TEXT,
  notes TEXT,
  measured_at INTEGER NOT NULL
);
CREATE INDEX idx_body_user_day ON body_metrics(user_id, measured_at);

CREATE TABLE coach_messages (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  role TEXT NOT NULL,               -- user|assistant
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_coach_user_time ON coach_messages(user_id, created_at);

CREATE TABLE integrations (
  user_id TEXT NOT NULL REFERENCES users(id),
  provider TEXT NOT NULL,           -- whoop|healthkit|garmin
  access_token TEXT,
  refresh_token TEXT,
  expires_at INTEGER,
  PRIMARY KEY (user_id, provider)
);
```

---

## 7. 18-Hour Plan, 4-Person Parallel

Roles. Pick once at hour 0; do not reshuffle:

- **A — iOS Lead.** Continues from current wireframe ([`VoCal/`](VoCal)).
- **B — Backend / Cloudflare.** Workers, D1, R2, AI Gateway, RevenueCat webhook.
- **C — AI / Inference.** System prompts, tool definitions, Vectorize seeding, vision pipeline.
- **D — Landing + DevOps + Polish.** vocal.best, ToS/Privacy, RevenueCat dashboard, App Store Connect record, demo prep.

| Hours | A (iOS app + voice) | B (Apple extensions) | C (Backend + AI on vocal.best) | D (Landing + Ops + Demo) |
|---|---|---|---|---|
| **0–2** | Onboarding + paywall sheet (RC SDK) + Keychain session | Set up `VoCalKit` shared package, `VoCalWatch` + `VoCalWidgets` + `VoCalIntents` targets in Xcode | Pages project on vocal.best; D1 + R2 + KV + Vectorize bindings; auth/apple endpoint | App Store Connect record, RC sandbox products, vocal.best Pages skeleton |
| **2–6** | Voice sheet → real STT (ElevenLabs Scribe streaming) → live transcript | `App Intents` (`LogMealByVoiceIntent`, `OpenMicIntent`) wired to `/api/voice/parse` | **Voice → `searchRestaurantMenu` → `MealEntry`** end-to-end. Seed Vectorize with top-25 chain menus. PDF + Google search tools online. | ToS + Privacy + Support pages live at vocal.best |
| **6–10** | Photo capture + follow-up loop UI (reuses voice pipeline) | HealthKit module (read+write); Watch app glance + complication; submit Siri test phrase | `/api/meals/photo`, `/api/coach`, RC webhook, voice Durable Object stable | TestFlight build #1 uploaded; sandbox testers invited |
| **10–14** | BF photo capture + Progress tab charts (`WeightChart`, `BFCard`) | Home Screen Widgets (`TodayMacrosWidget`, `LastMealWidget`); Lock Screen widget family | `/api/bodyfat`, `body_metrics` schema; coach prompt with rolling 7-day summary; TTS wired | Landing-page polish, demo script v1, capture seed-data demo videos |
| **14–16** | Coach chat UI + voice-in/voice-out | Live Activity / Dynamic Island for in-progress logs | **End-to-end smoke test: "medium fry from McDonald's" must hit < 2s.** Tune prompts and Vectorize K. | TestFlight build #2, demo dry-run #1 |
| **16–18** | Final polish, animations, perf, error states | Watch complications variants; Shortcuts pre-built shortcuts surfaced | Stand-by for prompt tweaks; cache warmup for demo items | Demo dry-run #2, 60-second pitch rehearsal, fallback offline demo video recorded |

**Hard checkpoints:**
- **Hour 6**: Killer-demo path ("medium fry from McDonald's" via voice → log in < 2s) must work. **If not, all 4 roles converge on it.**
- **Hour 12**: Tier-0 Apple extensions (App Intents, HealthKit, Widget, Live Activity) must be at least stub-wired so the demo can include them.
- **Hour 16**: Feature freeze. Only polish + bug fixes after this point.

**Shared file dependency**: `vocal-shared` Swift package contains `APIClient`, `Session`, `Theme`, model definitions, `VoCalKit`. Every iOS/watchOS/extension target depends on it. Set up at hour 0 so widgets/watch can be developed in parallel by role B without blocking on role A.

**Daily standup at hours 6 and 12.** Cut Tier-1 ruthlessly if any Tier-0 is at risk.

---

## 8. Critical Files & Reuse

**iOS — already built, extend in place:**
- [`VoCal/VoCal/Theme.swift`](VoCal/VoCal/Theme.swift) — design tokens. Don't fork; extend.
- [`VoCal/VoCal/Components.swift`](VoCal/VoCal/Components.swift) — `CalorieRing`, `MacroBar`, `MealCard`, `MicButton`. Add `WeightChart`, `BFCard`, `CoachBubble` here.
- [`VoCal/VoCal/TodayView.swift`](VoCal/VoCal/TodayView.swift) — main screen; wire mic button to real voice pipeline.
- [`VoCal/VoCal/VoiceCaptureSheet.swift`](VoCal/VoCal/VoiceCaptureSheet.swift) — has the `.listening` / `.review` state machine; replace mock `.review` with real LLM result + follow-up loop.
- [`VoCal/VoCal/HistoryView.swift`](VoCal/VoCal/HistoryView.swift) — add Weight + BF% charts beside the kcal chart.
- [`VoCal/VoCal/ProfileView.swift`](VoCal/VoCal/ProfileView.swift) — wire Subscription row to RC paywall sheet; "Apple Health" + "Voice & language" rows are already stubbed.
- [`VoCal/VoCal/Item.swift`](VoCal/VoCal/Item.swift) — has the models; swap to `@Model` (SwiftData) when persistence lands.
- [`VoCal/VoCal/MockData.swift`](VoCal/VoCal/MockData.swift) — keep as fallback while backend bringup is in flight; flip a flag to switch source.

**iOS — new files / targets to add:**

*Main app (`VoCal/`):*
- `OnboardingFlow.swift` — name, sex, height/weight, baseline body photos, goal-setting.
- `PaywallSheet.swift` — RC offering display.
- `CameraCaptureView.swift` — meal + body photo capture, AVFoundation-backed.
- `CoachView.swift` — chat with TTS playback (voice in + voice out).
- `LiveActivityController.swift` — starts/updates the in-progress logging activity.

*Shared package (`VoCalKit/` Swift Package):*
- `APIClient.swift` — networking against `https://vocal.best/api` (URLSession + async/await).
- `AudioStreamer.swift` — mic → WS to `wss://vocal.best/api/voice/stream` → partial transcript callbacks.
- `Session.swift` — JWT in Keychain, refresh logic, shared with watch + extensions.
- `Theme.swift`, `Components.swift`, `Models.swift` — moved here so widgets/watch can reuse.
- `Intents/` — `LogMealByVoiceIntent.swift`, `OpenMicIntent.swift`, `GetDailyMacrosIntent.swift`, `LogMealIntent.swift`, `AppShortcutsProvider.swift`.
- `VoCalHealth.swift` — HealthKit reads/writes wrapper.

*Watch target (`VoCalWatch/`):*
- `VoCalWatchApp.swift`, `WatchHomeView.swift`, `WatchMicView.swift`, `WatchConnectivityClient.swift`.
- `Complications/` — `.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular` providers.

*Widget extension (`VoCalWidgets/`):*
- `TodayMacrosWidget.swift`, `LastMealWidget.swift`, `StreakWidget.swift`, `LockScreenWidgets.swift`.

*Live Activity extension (`VoCalLiveActivities/`):*
- `VoCalActivityWidget.swift`, `VoCalActivityAttributes.swift`.

*Share extension (`VoCalShareExt/`, Tier-1):*
- `ShareViewController.swift`.

**Backend (`vocal-api/`, in `functions/` directory of the Pages project):**
- `wrangler.toml` — bindings for D1, R2, KV, Vectorize, Queues, AI, Durable Objects.
- `functions/api/auth/apple.ts` — Apple identity-token verification + session JWT mint.
- `functions/api/meals/index.ts`, `functions/api/meals/photo.ts` — meal CRUD + photo upload.
- `functions/api/voice/stream.ts` — WebSocket entry to the voice Durable Object.
- `functions/api/voice/parse.ts` — non-streaming parse endpoint used by App Intents.
- `functions/api/coach/index.ts` — chat endpoint.
- `functions/api/bodyfat/index.ts` — BF% endpoint.
- `functions/api/integrations/revenuecat.ts` — RC webhook.
- `src/ai/foodParser.ts`, `src/ai/visionParser.ts`, `src/ai/coach.ts`, `src/ai/bodyfat.ts` — LLM prompt + tool loop logic.
- `src/ai/tools/` — `searchRestaurantMenu.ts`, `searchUsda.ts`, `googleSearch.ts`, `fetchAndExtract.ts` (with PDF support via `unpdf`).
- `src/durable/voiceSession.ts` — DO class for streaming voice.
- `db/schema.sql`, `db/migrations/*.sql`.
- `seed/restaurants.json` — top-25 chain menu seed data.
- `seed/load.ts` — one-shot script to push seed data into D1 + Vectorize.

**Landing (`vocal-web/`, also in the Pages project):**
- Astro project at `vocal-web/`, builds to `dist/` which Pages serves at root.
- Pages: `/`, `/terms`, `/privacy`, `/support`, `/beta`.

**Repo layout:**

```
uncommonhacks26/
├── VoCal/                      # existing iOS project (extend in place)
│   ├── VoCal.xcodeproj
│   ├── VoCal/                  # main app target
│   ├── VoCalKit/               # shared Swift package (new)
│   ├── VoCalWatch/             # watch target (new)
│   ├── VoCalWidgets/           # widget extension (new)
│   ├── VoCalIntents/           # app intents extension (new)
│   ├── VoCalLiveActivities/    # live activity extension (new)
│   └── VoCalShareExt/          # share extension (new, Tier-1)
├── vocal-api/                  # Pages project (api + landing co-located)
│   ├── wrangler.toml
│   ├── functions/api/...       # Pages Functions
│   ├── src/...
│   ├── db/...
│   ├── seed/...
│   └── vocal-web/              # Astro landing site, builds to ./dist
└── STATUS.md                   # ralph loop iteration journal
```

---

## 9. Risk Register & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| ElevenLabs credits don't land | High | iOS `Speech` framework on-device STT as default; ElevenLabs is a swap behind AI Gateway. App works fully without credits — just less snappy. |
| Wafer onboarding delayed | Low | AI Gateway routes to Claude Sonnet 4.6 or GPT-5 by default; Wafer is the optional cost-optimization tier. **Per directive "scale is no issue,"** premium models are the default anyway. |
| Restaurant PDF parsing fails on weird formats | Medium | `unpdf` covers ~95% of restaurant PDFs. Fall back to `googleSearch` + `fetchAndExtract` on the HTML version; many chains publish both. Cache results 24h to avoid repeat misses. |
| Brave Search API key not approved in time | Medium | Swap to Serper, Tavily, or even a Google Custom Search Engine. AI Gateway has a single `WebSearchProvider` interface. |
| App Store Connect record creation fails / Apple Dev hiccup | Medium | TestFlight already builds locally ([`build/VoCal.ipa`](VoCal/build/export/VoCal.ipa)). Demo via direct device install with the team's Apple ID as fallback. |
| Apple App Review rejects voice without Privacy disclosures | Medium | Mic + photo + HealthKit usage strings all in `Info.plist`. ToS + Privacy live at vocal.best before submission. |
| Vision model gets food wrong in demo | High | Demo script picks meals we've pre-tested + cached. The "follow-up question" UX **turns model errors into product moments**. Manual-edit always one tap away. |
| BF% from photo too inaccurate for demo | Medium | Show confidence band, not a point estimate. Pair with manual entry. Frame as "estimate that gets better with more photos." |
| Live Activity flakey on simulator | Low | Test only on physical device. Loop verification runs against the demo device, not sim. |
| Watch hand-off latency over WCSession | Medium | Pre-warm the connection on watch app launch; fall back to "saved locally, syncing…" UI if hand-off times out. |
| RC webhook race vs. client-side entitlement check | Medium | Client trusts RC SDK first (offline-friendly); server reconciles within seconds. Don't gate UI on webhook. |
| Ralph loop spins on an unfixable manual checkpoint (e.g., SiwA private key) | High | Flag manual blockers in `STATUS.md` so the loop halts and surfaces "needs human" rather than thrashing. |
| 18h scope creep | **Highest** | Tier 0 is law. Tier 1 only after sign-off from all 4 roles at hour 12. |
| Inference cost overrun | Low (per directive) | "Scale is no issue, use any inference necessary." Accepted trade. |

---

## 10. Demo Script (60 seconds)

The script opens on the headline. Voice command, restaurant item, < 2s to logged. Nothing else gets demoed until that lands.

> **"Cal AI makes you take a photo. MyFitnessPal makes you type. VoCal just listens."**
>
> *[Open app, tap mic]* **"Log a medium fry from McDonald's."**
>
> *[~2 seconds later, the meal appears in the Today log with real macros: 320 kcal, 4g protein, 43g carbs, 15g fat. Calorie ring advances.]*
>
> "That's the first time any app has done that." *[beat]*
>
> *[Tap mic again]* **"And a grande oat milk latte from Starbucks."** *[logged]*
>
> *[Tap mic]* **"Chipotle bowl, double chicken, brown rice, black beans, guac."**
>
> *[App voice replies]* "Single scoop of guac?"
>
> "Yeah." *[logged, ~710 kcal]*
>
> "Now the photo trick — for stuff that isn't on a menu." *[Snap layered salad]* App: "I see greens, chicken, quinoa. Anything underneath I can't see?" "Half a cup more quinoa." *[logged, with confidence band]*
>
> *[Tap Progress tab]* "Weight, body-fat from selfies, syncs to your Watch and WHOOP." *[Tap paywall — sandbox subscribe]* "Hard paywall, day one. **That's VoCal.**"

Four beats, escalating: **voice + restaurant → voice + restaurant (×2 for proof) → voice + photo follow-up → progress & paywall.**

---

## 11. Verification (how we know it works end-to-end)

Before declaring "done" for the demo, run the full happy path on a clean TestFlight install:

1. **Cold launch** → onboarding → Apple sign-in → goal set → paywall → sandbox subscribe → home.
2. **The killer demo**: tap mic → say *"medium fry from McDonald's"* → meal appears in log with **the actual McDonald's medium-fry macros (320 kcal, 4P/43C/15F)** in **under 2 seconds**. Repeat with *"grande iced oat latte from Starbucks"* and *"Chipotle burrito bowl with double chicken, brown rice, black beans, guac"* (last one should trigger guac-size follow-up). **If this doesn't work, nothing else matters.**
3. **Photo log**: camera → snap → first-pass result → follow-up about hidden food → reply → meal updated → saved.
4. **BF% capture**: profile → "update body" → front + side selfie → estimate appears → saved to chart.
5. **Coach**: open coach tab → ask "how do I hit my protein?" → text answer + TTS → suggestion makes sense given today's log.
6. **History**: confirm both meals + body entry appear on Today and History.
7. **Background → resume**: data persists; if backend reachable, server has the rows (`wrangler d1 execute vocal-prod --command "SELECT * FROM meals ORDER BY created_at DESC LIMIT 5"`).
8. **Offline**: airplane mode, log a meal by voice (Apple STT fallback) → toast "synced when online" → re-enable network → confirm sync.

Failing #2 = demo is dead. Failing any of 1, 3–6 = ship-blocker. 7 and 8 are nice-to-have.

---

## 12. Open Questions / Flagged Decisions

- **Voice persona name**: pick during integration (e.g., "Vo"). Coach tab personality is a brand moment.
- **Photo retention**: do we keep meal photos in R2 forever, or auto-delete after N days for privacy? Default: 30 days unless user opts in to keep.
- **Body photos**: encrypt at rest in R2 (per-user key derived from Apple sub). Never returned to client after upload — only the BF% number.
- **WHOOP integration** is Tier-1; descope cleanly if Tier-0 is at risk by hour 12.
- **Apple Watch app**: hand-off Tier-1; native voice capture is post-hackathon.
- **Free-tier limit (3 meals/day)** vs. unlimited-but-paywall-AI: locked to hard paywall per team decision. Revisit post-launch based on conversion data.

---

## 13. Ralph Loop — Execution Strategy

The directive: "Do this in a ralph loop. The product SHOULD work. Ensure it does."

Per the `ralph-loop` skill, this means the implementation phase reruns the same prompt against persisted file state until a `<promise>` tag is emitted. The loop is appropriate here because the success criterion is **a concrete, testable end-to-end path**, not an open-ended design choice.

### Completion promise

```
<promise>VOCAL-DEMO-READY</promise>
```

Emitted only when **all of the following pass on a fresh TestFlight install on a real device**:

1. Cold launch → onboarding → Apple sign-in → paywall → sandbox subscribe → home screen.
2. **Killer demo**: speak *"medium fry from McDonald's"* → meal appears with correct macros (320 kcal / 4P / 43C / 15F, ±10%) in **< 3 seconds wall-clock** (relaxed from 2s to give the loop margin).
3. **Killer demo #2**: speak *"grande iced oat latte from Starbucks"* → logged correctly.
4. **Killer demo #3**: speak *"Chipotle bowl, double chicken, brown rice, black beans, guac"* → app asks a follow-up question (guac size or rice amount) → logged correctly after reply.
5. **Photo + voice**: snap any meal photo → first-pass macros appear → app asks a follow-up → voice reply → updated macros.
6. **BF photo**: front + side selfie → BF% number returned with confidence band → appears on Progress chart.
7. **Coach**: ask "how do I hit 180g protein today?" → coherent answer cites today's actual log.
8. **App Intent**: say "Hey Siri, log a medium fry from McDonald's" → logs without opening the app.
9. **HealthKit**: meal write shows up in Apple Health for `dietaryEnergyConsumed`.
10. **Widget**: Home Screen widget reflects today's ring within 30s of a save.
11. **Live Activity**: appears in Dynamic Island during a voice log, dismisses after save.
12. **Watch**: tapping the watch complication starts a mic capture that completes on the phone.
13. **Backend**: `wrangler d1 execute vocal-prod --command "SELECT COUNT(*) FROM meals WHERE created_at > <session_start>"` returns ≥ 5.
14. **Landing page**: vocal.best, vocal.best/terms, vocal.best/privacy, vocal.best/support all return 200.
15. **TestFlight**: build with version `1.0 (1)` is processed and installable on the demo device.

### Loop configuration

```
/ralph-loop "Implement VoCal per /Users/eric/.claude/plans/now-walk-through-how-crispy-toast.md. Build, deploy, and verify every item in §13. Emit <promise>VOCAL-DEMO-READY</promise> only when all 15 checks pass." --completion-promise "VOCAL-DEMO-READY" --max-iterations 40
```

Why 40 iterations: at roughly 25-30 minutes of useful work per iteration, that's ~16-20 hours of compute window — matches the hackathon budget.

### Per-iteration loop discipline

Every iteration follows the same arc, so the next iteration can resume cleanly from disk state:

1. **Read** the plan + the iteration journal (`.claude/.ralph-loop.local.md` plus a `STATUS.md` we append to).
2. **Decide** the smallest next change that moves the closest-to-failing checkpoint from §13 closer to green.
3. **Implement** the change (Swift, TS, prompts, config).
4. **Verify** it: `xcodebuild test`, `wrangler dev` end-to-end curl, sim install + screenshot.
5. **Update** `STATUS.md` with: what changed, what's now green, what's now closest to green.
6. **Decide** whether the completion promise is earned. If yes, emit it.

### Risk: silent regressions across iterations

Mitigation: a `bin/verify-vocal.sh` script in the repo that runs the 15 checks (those that can be automated — 1, 13, 14, 15 are scriptable; the rest are recorded in a manual test log). Run on every iteration. Drift caught immediately.

### Manual checkpoints (cannot be ralph-looped)

Three human-in-the-loop moments:
- Apple Sign-in needs an Apple developer key configured in the Cloudflare Worker secret (`wrangler pages secret put APPLE_SIWA_PRIVATE_KEY`). Requires a private key downloaded from developer.apple.com.
- RevenueCat sandbox setup needs IAP products approved in App Store Connect (~10 minutes manual).
- Final TestFlight build upload requires Xcode Organizer interaction.

These are flagged explicitly in `STATUS.md` so the loop pauses and surfaces "needs human" rather than spinning on something it can't fix.

---

## 14. Out of Scope (explicitly not for this hackathon)

- Android app
- Web app (landing page only)
- Family/sharing features
- Social feed / friends
- Native macOS app
- Multi-language UI (English only at demo)
- Custom-trained nutrition model (we use hosted LLMs + USDA lookup)
- HIPAA/medical-grade claims — we are a tracker, not a medical device. State this in ToS.

Sources used while drafting this spec:
- [Wafer (Y Combinator)](https://www.ycombinator.com/companies/wafer) — flat-rate fast inference platform; backs our `Wafer` LLM tier.
- [Wafer Pass on Product Hunt](https://www.producthunt.com/products/wafer) — pricing/model lineup.
- [ElevenLabs Scribe v2 Realtime](https://elevenlabs.io/realtime-speech-to-text) — 150ms streaming STT; primary voice-in.
- [ElevenLabs Speech-to-Text API docs](https://elevenlabs.io/docs/overview/capabilities/speech-to-text) — implementation reference.
- [Cal AI accuracy review (KCalm)](https://www.kcalm.app/blog/ai-food-recognition-accuracy/) — confirms the 3D/layered-food accuracy gap VoCal is built to close.

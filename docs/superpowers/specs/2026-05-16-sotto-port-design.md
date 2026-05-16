# Sotto Port — Design Spec

**Date:** 2026-05-16
**Author:** Eric Spencer (with Claude)
**Status:** Approved (sections 1–2 confirmed, 3–8 written under user direction "stop asking questions")

## Problem

VoCal's marketing site (`vocal-api/vocal-web/dist/`) is empty — App Store URLs point at unstyled placeholders. The iOS app has a strong dark editorial design but lacks the kind of "showpiece" product moments that turn install intent into installs. The Sotto repo (https://github.com/arjunsrivastava-ai/sotto) ships a single-file landing page with three distinctive elements we want: a scroll-scrubbed rotating-plate hero (`mp_.mp4`), a scroll-scrubbed exploding-view of a meal (`explode.mp4`), and a polished "Soft Structuralism" structural system (glass-pill nav, double-bezel cards, asymmetric bento, editorial 01/02/03 step list, marquee, FAQ, film grain).

## Goal

1. Vendor sotto as a git submodule so its assets are licensed/traceable to upstream.
2. Rebuild `vocal-web` as a from-scratch sotto-structured landing in VoCal's dark editorial palette.
3. Add iOS surfaces that consume the two sotto videos: hero plate on Today + onboarding intro, and a "meal explode" sheet for meal detail.
4. Re-shape iOS Today as the asymmetric bento using the existing `Theme` token system.

## Non-goals

- Light-mode iOS. VoCal stays dark.
- Replacing VoCal's branding with Sotto's. Brand stays VoCal; sotto contributes design language + raw video assets only.
- Re-rendering the videos. We use sotto's `mp_.mp4` and `explode.mp4` as-is for now (see §Risks for licensing).
- Re-doing prophet-lab. Out of scope.

## Approach: A — selective port, VoCal brand

Locked in during brainstorming. Submodule sotto, port sotto's structural language to web in VoCal palette, port the two videos + bento card system + explode flow to iOS, keep dark editorial intact.

---

## §1. Repo & asset wiring

### Layout

```
uncommonhacks26/
├── sotto/                          ← git submodule, read-only by convention
├── vocal-api/
│   └── vocal-web/
│       ├── public/
│       │   ├── mp_.mp4             ← synced from sotto/
│       │   └── explode.mp4         ← synced from sotto/
│       └── dist/index.html         ← built artifact (committed for Pages)
├── VoCal/VoCal/
│   ├── Resources/
│   │   ├── mp_.mp4                 ← bundled, synced from sotto/
│   │   └── explode.mp4             ← bundled, synced from sotto/
│   └── (Today / Onboarding / MealDetailSheet — modified)
└── scripts/
    └── sync-sotto-assets.sh        ← copies the two .mp4s to both targets
```

### Mechanics

- `git submodule add https://github.com/arjunsrivastava-ai/sotto.git sotto` pins to the current upstream HEAD.
- `scripts/sync-sotto-assets.sh` runs on demand: `cp sotto/mp_.mp4 vocal-api/vocal-web/public/ && cp sotto/mp_.mp4 VoCal/VoCal/Resources/` (and same for `explode.mp4`). Both targets need real files — iOS can't bundle from a submodule path, and the Pages build serves `public/` verbatim.
- iOS uses `AVPlayer` against the bundle URL; web uses `<video preload="auto" muted playsinline>` exactly like sotto's hero.

### Why not symlink / not git-lfs

Symlinks break Cloudflare Pages and Xcode resource copy. Git-LFS is overkill for two ~MB files that come from upstream by submodule reference anyway.

---

## §2. Design tokens (sotto → VoCal-dark mapping)

| Sotto role | Sotto color | VoCal-dark | Where it shows |
|---|---|---|---|
| paper | `#F4F4F2` | `#0A0A0B` (`Palette.ink`) | page background |
| mist | `#FBFBFA` | `#121214` (`inkRaised`) | inner card surface |
| ink | `#0B0B0C` | `#F6F4EC` (`bone`) | hero copy + headings |
| slate | `#5A5C5B` | `#BDBBB2` (`ash`) | body, muted captions |
| sage | `#16613F` | `#E5FF59` (`voltage`) | accent dots, "Most loved" tag |
| sagelt | `#E7EFEA` | `voltage.opacity(0.14)` | chip backgrounds for tags |
| white/55 (outer bezel) | `rgba(255,255,255,0.55)` | `white.opacity(0.04)` | outer bezel of every card |
| ink/[0.05] (hairline) | `rgba(11,11,12,0.05)` | `white.opacity(0.07)` (`hairline`) | every border |

**Restraint on voltage:** sotto uses sage as a quiet botanical accent against bright paper. Voltage against dark is loud. Use voltage sparingly on web — pill dots, the "1.2s logged" chip, the FAQ "+", the "Most loved" pricing tag — and NOT as a full button fill. Primary CTAs are bone-on-ink (the role-reversed equivalent of sotto's ink-on-mist).

**Coral (`pulse`):** reserved for the live-mic state across both web and iOS, identical to current usage.

**Type:**
- Web display face: **Clash Display** 500/600/700, from Fontshare. Replaces sotto's same choice.
- Web body face: **Plus Jakarta Sans** 400/500/600, from Google Fonts.
- iOS display: **New York serif** (existing). Clash on iOS would dilute the brand — kept native serif.
- iOS body: **SF Pro** (existing).

**Shadows on dark:** sotto's three diffused-drop shadows can't carry weight on `#0A0A0B`. Translate the *geometry* via a thin outer ring (`white.opacity(0.04)`) around an inner `inkRaised` card, plus an inset top highlight (`white.opacity(0.06)`). This preserves sotto's "double-bezel" geometry while accepting that the soft-drop part of "Soft Structuralism" doesn't translate.

**Motion:** keep both sotto easing curves: `cubic-bezier(0.22, 1, 0.36, 1)` (fluid, for opacity/translate) and `cubic-bezier(0.32, 0.72, 0, 1)` (spring, for scale). Add as `Theme.Motion.fluid` and `Theme.Motion.spring` on iOS.

**Film grain:** keep at 3.5% opacity. Swap the SVG noise fill from black-on-light to white-on-dark so it renders as faint light TV-static instead of vanishing.

---

## §3. Website (`vocal-api/vocal-web/`)

### Stack

Match sotto exactly: single static `dist/index.html` with embedded `<script src="https://cdn.tailwindcss.com">`, embedded Tailwind config, embedded `<style>`, embedded vanilla JS. No build step. Sits at `vocal-web/dist/index.html` so the existing Cloudflare Pages config serves it.

The accompanying `/terms`, `/privacy`, `/support`, `/beta` paths from STATUS.md iteration 3 will be regenerated as sibling files using the same shell (header + minimal section + footer) so they're consistent.

### Section list (in order)

1. **Floating glass-pill nav** ("Fluid Island"). Wordmark left (small VoCal serif italic, matching the iOS wordmark token), four links (`#features`, `#how`, `#pricing`, `#faq`), nested ink-CTA "Get the app" with arrow icon. Hamburger on mobile → full-screen `#menu` overlay with staggered link reveal.
2. **Hero**. `min-h-[100dvh]`. Background: `mp_.mp4` scrubbed by scroll (FPS=24, range=3×viewport), masked inward via the existing radial mask. Foreground: eyebrow pill ("Vocal nutrition · now in beta"), Clash Display headline ("Just say what you ate. We do the rest."), subhead ("VoCal turns a sentence into a meal. *'Medium fry from McDonald's'* — logged, broken down, tracked before you've put your phone down."), two CTAs (bone-on-ink "Start tracking by voice" + outlined "See it work"), and the double-bezel "Listening" capture card with animated vox bars + sample transcript + 3-stat readout (kcal/protein/logged).
3. **Exploding view** (`#explode`). Sticky-stage section with `explode.mp4` autoplaying once on entry (rate 1.2×). Centered editorial copy panel + scroll hint pill.
4. **Trust marquee**. Drifting line of audiences: "Dietitians · Runners · Strength athletes · Busy parents · Coaches · Home cooks" with voltage dot separators. Linear translateX animation, edge-feathered with linear mask.
5. **Features bento** (`#features`). 7/5/5/4/4/4 column grid:
   - **A (col-span-7, row-span-2):** "Speak naturally. It just understands." + a sample "Heard" card with chip readout.
   - **B (col-span-5):** "Macros, the moment you finish talking."
   - **C (col-span-5, ink-inverted card):** "A coach that nudges, gently."
   - **D (col-span-4):** "Private by design" — on-device transcription.
   - **E (col-span-4):** "Speaks 30 languages" — code-switch.
   - **F (col-span-4):** "Lives on your wrist" — watch logging + HealthKit.
6. **How it works** (`#how`). Left col: eyebrow + Clash heading + intro paragraph. Right col: three numbered cards (01 / 02 / 03), the last one ink-inverted, exactly matching sotto's editorial step list.
7. **Editorial testimonial**. Large quote + author chip in a paper plate. Copy attributed to a plausible dietitian persona (kept generic — not a real endorsement).
8. **Pricing** (`#pricing`). Three tiers, middle ink-inverted with "Most loved" voltage chip:
   - **Taste** — Free. Voice logging, daily macros, 7-day history.
   - **VoCal Pro** — $6/mo. Unlimited history, AI coach, full HealthKit, watch app, full export.
   - **Clinic** — Custom. Practitioner dashboards.
9. **FAQ** (`#faq`). Four questions, single-open accordion:
   - "How accurate can a spoken estimate really be?"
   - "Does it work offline and on the watch?"
   - "What happens to my voice recordings?"
   - "Can I export to my dietitian's tools?"
10. **Final CTA** (`#cta`). Big ink-card with voltage halo radial: "Stop typing your food. Start telling it." Two CTAs (Download bone-on-ink, "Watch the 40s demo" outlined).
11. **Footer**. Wordmark left, product/company link columns right, copyright line.

### Embedded JS modules (vanilla, kept in `<script>` tags identical to sotto)

- Fluid Island nav condense on scroll
- Hamburger morph + menu show/hide + Escape close
- Scroll-reveal via IntersectionObserver
- Hero video scrub (FPS=24, 3-viewport range)
- Explode video autoplay once at ≥0.9 intersection ratio
- FAQ single-open accordion

`prefers-reduced-motion: reduce` short-circuits all of the above to a static render, copied directly from sotto.

### Copy direction

VoCal voice, not Sotto's. Specifically: replace "Sotto" with "VoCal" everywhere; replace sotto's grilled-salmon-bowl example with a VoCal-canon example ("Medium fry from McDonald's", "Grande iced oat latte from Starbucks", "Chipotle bowl, double chicken"); replace the dietitian persona with one that matches VoCal's positioning; keep sotto's quiet/editorial register throughout (no exclamation points, no hype words).

### Aux pages

`/terms.html`, `/privacy.html`, `/support.html`, `/beta.html` — same nav + footer shell, simple `<article>` body. Content carried over from whatever currently exists (STATUS iteration 3 said these were minimal placeholders; the new shell upgrades the chrome but keeps the legal copy).

---

## §4. iOS — Today screen bento

### Current Today (from `TodayView.swift` per STATUS iteration 5)

Vertical stack: kcal ring, macro bars, recent meals list, ambient background.

### New Today (asymmetric bento, dark VoCal palette)

```
┌──────────────────────────────────────────┐
│  EYEBROW: TODAY                          │
│  Big serif date headline                 │
├─────────────────────────┬────────────────┤
│                         │  Plate clip    │
│  Calorie ring           │  (mp_.mp4      │
│  (voltage stroke)       │   silent, low- │
│  serif kcal remaining   │   FPS, looped) │
│                         │                │
├─────────────────────────┴────────────────┤
│  Macro bars row (protein / carbs / fat)  │
├──────────────────────────────────────────┤
│  EYEBROW: MEALS                          │
│  Meal cards (existing component)         │
└──────────────────────────────────────────┘
   floating mic (existing) ▲
```

- Outer container: page padding, no scroll-view chrome change.
- Each card uses a new `BentoCard` view modifier: outer bezel (`white.opacity(0.04)` 1pt ring) + inner `inkRaised` fill + inset top highlight, radius 22. Matches the "Soft Structuralism" geometry from §2.
- Plate clip: small (~120pt square) `AVPlayerLayer` showing `mp_.mp4` looped at 0.6× rate, muted, masked to a soft radial gradient so it dissolves into the card.
- Tap on plate clip: no-op in v1. Reserved for a future Today-snapshot sheet but explicitly out of scope here.

### Touched files

- `TodayView.swift` — restructured.
- `Components.swift` — add `BentoCard` modifier, add `AmbientVideoPlayer` view.
- `Theme.swift` — add `Theme.Motion.fluid` / `Theme.Motion.spring` easing tokens.

---

## §5. iOS — Onboarding intro

### Current onboarding (`OnboardingFlow.swift`)

5-step: pitch → name → body baseline → goal → ready.

### New step 0 — "Welcome"

Inserted before the existing 5 steps. Full-bleed `AVPlayer` of `mp_.mp4` looping silently at 1× rate, masked to inward radial. Overlay: VoCal serif wordmark top, headline "Just say what you ate. We do the rest." (mirroring sotto's hero copy, in VoCal voice), single bone-on-ink CTA "Begin". CTA advances to existing step 1 (name).

`UIUserInterfaceStyle = Dark` stays pinned. The video plays even on Reduce Motion (it's looping atmosphere, not an effect — the static-frame fallback would feel weirder than the loop).

### Touched files

- `OnboardingFlow.swift` — add step 0.

---

## §6. iOS — Meal detail "explode" sheet

### Current behavior

Tapping a meal in the recent-meals list does nothing — meal rows in `TodayView.swift` are passive `MealCard` renders with no gesture wired up.

### New behavior

Tap meal → present `MealExplodeSheet`. Layout:

```
┌──────────────────────────────────────────┐
│  ✕ close                                 │
│                                          │
│  [explode.mp4 plays once, full-bleed     │
│   behind a centered copy panel, masked   │
│   to feather edges into ink]             │
│                                          │
│       EYEBROW: PARSED                    │
│       Big serif meal title               │
│                                          │
│       ┌────┐ ┌────┐ ┌────┐               │
│       │chip│ │chip│ │chip│ ← ingredients │
│       └────┘ └────┘ └────┘               │
│                                          │
│       kcal / protein / carbs / fat       │
│                                          │
│       [Delete]                           │
└──────────────────────────────────────────┘
```

- `explode.mp4` plays once on sheet appear, rate 1.2× (matching sotto). Loops once then freezes on last frame.
- Ingredient chips stagger-reveal as the video plays (opacity + 12pt translate + 8pt blur out, fluid easing, 80ms per chip).
- Chips come from `MealEntry.components` (the new field added in Item.swift) if present; if the meal lacks components, the sheet shows a single chip with the meal name and the explode video still plays.
- Delete uses existing `AppModel.removeMeal`. Edit is intentionally out of scope for v1 (no `replaceMeal`, no edit UX) — call site reserved for later.

### Touched files

- `MealExplodeSheet.swift` — new file.
- `TodayView.swift` — wire tap action.
- `Item.swift` — add `MealEntry.components: [MealEntry.Component]?` (new nested struct with `name: String, grams: Double?, kcal: Int?`). New — does not exist in the current `Item.swift`. (No `replaceMeal` — the sheet only needs read + delete in v1.)
- `Components.swift` — add `IngredientChip`.

---

## §7. Asset handling

### Sync script (`scripts/sync-sotto-assets.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOTTO="$ROOT/sotto"
WEB="$ROOT/vocal-api/vocal-web/public"
IOS="$ROOT/VoCal/VoCal/Resources"
mkdir -p "$WEB" "$IOS"
for f in mp_.mp4 explode.mp4; do
  cp -v "$SOTTO/$f" "$WEB/$f"
  cp -v "$SOTTO/$f" "$IOS/$f"
done
```

Run manually after `git submodule update --remote`. Both copies live in source control (videos are <10MB combined).

### Xcode bundling

Add `VoCal/VoCal/Resources/` as a folder reference (blue) to the Xcode project so any file dropped in is auto-bundled. iOS code loads via `Bundle.main.url(forResource: "mp_", withExtension: "mp4")`.

### Cloudflare Pages

`vocal-web/public/` is served at root. Hero `<video>` uses `<source src="/mp_.mp4">`.

---

## §8. Verification

This spec ships green when:

1. `git submodule status` shows `sotto` pinned to a non-zero commit.
2. `bash scripts/sync-sotto-assets.sh` copies both videos into both targets without error.
3. `vocal-api/vocal-web/dist/index.html` opens in a browser and:
   - Glass-pill nav floats, hamburger morphs on mobile.
   - Hero video scrubs with scroll, headline + capture card visible.
   - `explode.mp4` plays once when its section enters the viewport.
   - Marquee drifts, bento renders 7/5/5/4/4/4, FAQ single-opens, final CTA reads correctly.
   - Reduce-motion preference produces static, scroll-able fallback.
4. `xcodebuild build -scheme VoCal -destination 'generic/platform=iOS'` succeeds.
5. App launches → onboarding step 0 plays plate video → step 1 name → … → home. Today screen shows the new bento layout with the plate clip looping in the small card. Tapping a meal opens the explode sheet, which plays `explode.mp4` once and reveals ingredient chips.
6. Reduce-motion on iOS skips chip-stagger animation but still plays the looping plate (atmospheric, see §5).

### Test plan (manual)

| Surface | Test |
|---|---|
| Web hero | Scroll slowly through hero — video frames step forward smoothly, not janky. |
| Web hero | DevTools Network: confirm only one fetch of `mp_.mp4`. |
| Web explode | Scroll into `#explode` — video plays once at 1.2×, freezes on last frame, never resets. |
| Web reduce-motion | Set OS reduce-motion → reload — no scrubbing, static first frame, all sections still readable. |
| Web mobile | iPhone Safari — hamburger opens full-screen menu, staggered link reveal, Escape closes (n/a on mobile, tap closes). |
| iOS onboarding | Cold launch with `UserDefaults` cleared — step 0 video loops, "Begin" advances to step 1. |
| iOS today | Plate clip loops at 0.6×, doesn't fight the kcal ring visually. |
| iOS explode sheet | Tap a meal with parsed components — video plays once, chips stagger in. |
| iOS explode sheet | Tap a meal WITHOUT components — single chip, video still plays. |
| iOS reduce-motion | Toggle Reduce Motion → explode sheet skips chip stagger, but plate still loops. |

---

## §9. Risks & open items

1. **License on sotto's videos.** sotto's repo has no LICENSE file. Using `mp_.mp4` and `explode.mp4` in a public product is a judgment call. Mitigations, in order of preference: (a) reach out to upstream for explicit permission, (b) re-render equivalent clips in-house and swap them in, (c) accept the risk for the demo period. Flagged for user decision before public deploy.
2. **Brand collision.** sotto positions in the same niche as VoCal. Mirroring its landing-page IA risks looking derivative. Mitigated by: VoCal copy + voltage palette + serif wordmark replacing sotto's geometric sans logo, which gives a different first impression even with the same structure.
3. **Hero video weight on mobile.** sotto's mp_.mp4 is sized for desktop. We should keep it ≤ 4MB; if upstream's version is larger, transcode with `ffmpeg -i mp_.mp4 -vf scale=1280:-2 -c:v libx264 -crf 26 -preset slow -movflags +faststart mp_.mp4` and commit the transcoded version. To be checked during implementation.
4. **iOS Xcode resource folder.** Folder references in Xcode (blue) are fragile across multi-machine setups. If the resource doesn't bundle, fall back to adding each file individually (yellow group). To be verified during implementation.
5. **Reduce-motion semantics for the explode sheet.** The decision to *still play* the looping plate even under reduce-motion is non-obvious. If user testing shows that bothers people, swap to a static poster frame.
6. **Bento on smaller iPhones.** iPhone SE viewport is narrow; the side-by-side ring + plate-clip row may need to stack on widths < 375pt. To be tested during implementation.

---

## Touched-files summary

**New:**
- `sotto/` (submodule)
- `scripts/sync-sotto-assets.sh`
- `vocal-api/vocal-web/public/mp_.mp4`
- `vocal-api/vocal-web/public/explode.mp4`
- `vocal-api/vocal-web/dist/index.html` (full rewrite; currently empty)
- `vocal-api/vocal-web/dist/terms.html`
- `vocal-api/vocal-web/dist/privacy.html`
- `vocal-api/vocal-web/dist/support.html`
- `vocal-api/vocal-web/dist/beta.html`
- `VoCal/VoCal/Resources/mp_.mp4`
- `VoCal/VoCal/Resources/explode.mp4`
- `VoCal/VoCal/MealExplodeSheet.swift`

**Modified:**
- `VoCal/VoCal/Theme.swift` — add `Theme.Motion` easing tokens
- `VoCal/VoCal/Components.swift` — add `BentoCard`, `AmbientVideoPlayer`, `IngredientChip`
- `VoCal/VoCal/TodayView.swift` — bento layout + meal tap action
- `VoCal/VoCal/OnboardingFlow.swift` — insert step 0 welcome
- `VoCal/VoCal/Item.swift` — add `MealEntry.Component` struct + `MealEntry.components` field
- `VoCal/VoCal/VoCal.xcodeproj/project.pbxproj` — register `Resources/` folder reference, register new `MealExplodeSheet.swift`

**Unchanged:**
- `vocal-api/functions/` and `vocal-api/src/` — backend parser stays as-is
- `prophet-lab/` — out of scope

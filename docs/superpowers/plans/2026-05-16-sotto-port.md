# Sotto Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor sotto as a git submodule, rebuild the VoCal landing page on sotto's full structural system in VoCal's dark editorial palette, and add three iOS surfaces that consume sotto's two scroll videos.

**Architecture:** Single static `dist/index.html` (Tailwind via CDN, embedded styles + JS, no build step) mirroring `sotto/index.html`'s structure with palette + copy + branding mapped to VoCal-dark. iOS uses `AVPlayer` to play the two videos as ambient atmosphere on Today, as an onboarding step-0 welcome, and as the backdrop of a new `MealExplodeSheet` that animates parsed ingredient chips in over the explode video.

**Tech Stack:**
- Submodule: git
- Web: HTML + Tailwind Play CDN + vanilla JS, served by Cloudflare Pages from `vocal-api/vocal-web/dist/`
- iOS: SwiftUI + `AVKit` (`AVPlayer`/`AVPlayerLayer`), Swift Testing (`@Test` / `#expect`) for new logic in `Item.swift` and `Theme.swift`

**Spec:** [docs/superpowers/specs/2026-05-16-sotto-port-design.md](../specs/2026-05-16-sotto-port-design.md)

---

## File Structure

**Phase 1 (submodule + assets):**
- New: `sotto/` (submodule)
- New: `scripts/sync-sotto-assets.sh`
- New: `vocal-api/vocal-web/public/mp_.mp4`, `explode.mp4`
- New: `VoCal/VoCal/Resources/mp_.mp4`, `explode.mp4`

**Phase 2 (website):**
- New: `vocal-api/vocal-web/dist/index.html` (currently empty)
- New: `vocal-api/vocal-web/dist/terms.html`, `privacy.html`, `support.html`, `beta.html`

**Phase 3 (iOS):**
- Modify: `VoCal/VoCal/Theme.swift` — add `Theme.Motion` easing tokens
- Modify: `VoCal/VoCal/Item.swift` — add `MealEntry.Component`, `MealEntry.components`, `AppModel.replaceMeal`
- Modify: `VoCal/VoCal/Components.swift` — add `BentoCard`, `AmbientVideoPlayer`, `IngredientChip`
- New: `VoCal/VoCal/MealExplodeSheet.swift`
- Modify: `VoCal/VoCal/TodayView.swift` — bento layout + meal tap wiring
- Modify: `VoCal/VoCal/OnboardingFlow.swift` — insert step 0 welcome
- Modify: `VoCal/VoCalTests/VoCalTests.swift` — add tests for the Item.swift and Theme.swift additions
- Modify: `VoCal/VoCal.xcodeproj/project.pbxproj` — register `Resources/` folder and `MealExplodeSheet.swift`

---

# Phase 1 — Submodule + asset sync

## Task 1: Add sotto as a git submodule

**Files:**
- Modify: `.gitmodules` (created automatically)
- New: `sotto/` (submodule directory)

- [ ] **Step 1: Add the submodule**

Run:
```bash
git submodule add https://github.com/arjunsrivastava-ai/sotto.git sotto
```

Expected output: `Cloning into '.../sotto'...` followed by a clean exit.

- [ ] **Step 2: Verify the submodule is pinned**

Run:
```bash
git submodule status
```

Expected: one line starting with a SHA, then ` sotto (<some-tag-or-heads/main>)`. No `-` prefix (which would mean uninitialized).

- [ ] **Step 3: Verify sotto's two videos exist locally**

Run:
```bash
ls -lh sotto/mp_.mp4 sotto/explode.mp4
```

Expected: both files listed, both >100KB.

- [ ] **Step 4: Commit**

```bash
git add .gitmodules sotto
git commit -m "$(cat <<'EOF'
chore: add sotto as git submodule for design reference + video assets

Pinned to upstream HEAD. Provides mp_.mp4 (rotating plate hero) and
explode.mp4 (exploding meal view), plus the index.html that informs the
new vocal-web design.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create the asset sync script

**Files:**
- New: `scripts/sync-sotto-assets.sh`

- [ ] **Step 1: Create the script directory**

Run:
```bash
mkdir -p scripts
```

- [ ] **Step 2: Write the script**

Write to `scripts/sync-sotto-assets.sh`:

```bash
#!/usr/bin/env bash
# Sync sotto/*.mp4 → vocal-web/public/ and VoCal/VoCal/Resources/.
# Run after `git submodule update --remote` if upstream re-renders the clips.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOTTO="$ROOT/sotto"
WEB="$ROOT/vocal-api/vocal-web/public"
IOS="$ROOT/VoCal/VoCal/Resources"

if [[ ! -d "$SOTTO" ]]; then
  echo "error: $SOTTO not found. Run 'git submodule update --init' first." >&2
  exit 1
fi

mkdir -p "$WEB" "$IOS"

for f in mp_.mp4 explode.mp4; do
  if [[ ! -f "$SOTTO/$f" ]]; then
    echo "error: $SOTTO/$f missing" >&2
    exit 1
  fi
  cp -v "$SOTTO/$f" "$WEB/$f"
  cp -v "$SOTTO/$f" "$IOS/$f"
done

echo "synced 2 videos to vocal-web/public and VoCal/Resources"
```

- [ ] **Step 3: Make executable + run it**

Run:
```bash
chmod +x scripts/sync-sotto-assets.sh
./scripts/sync-sotto-assets.sh
```

Expected output: four `cp` lines (mp_.mp4 → web, mp_.mp4 → iOS, explode.mp4 → web, explode.mp4 → iOS) and the final summary line.

- [ ] **Step 4: Verify both targets**

Run:
```bash
ls -lh vocal-api/vocal-web/public/*.mp4 VoCal/VoCal/Resources/*.mp4
```

Expected: four files, two in each directory, each >100KB.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-sotto-assets.sh vocal-api/vocal-web/public/ VoCal/VoCal/Resources/
git commit -m "$(cat <<'EOF'
chore: add sync-sotto-assets.sh + vendored videos

scripts/sync-sotto-assets.sh copies the two sotto videos into both
deployment targets (Cloudflare Pages public/ and the iOS bundle's
Resources/). Both committed so deploys don't depend on submodule
init.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 2 — Website rebuild

## Task 3: Write `dist/index.html` shell (head, body skeleton, footer)

**Files:**
- New: `vocal-api/vocal-web/dist/index.html`

This task creates the page chrome (head with embedded Tailwind config + styles, body shell with the floating nav, the empty `<main>`, and the footer). Subsequent tasks insert each section into `<main>`. The page is renderable at the end of this task but will look empty between nav and footer.

- [ ] **Step 1: Write `vocal-api/vocal-web/dist/index.html`**

Use this exact content:

```html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VoCal — Just say what you ate</title>
<meta name="description" content="VoCal is a voice-first nutrition tracker. Speak your meals in plain language and get instant macros — no typing, no searching, no friction." />

<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700,500&display=swap" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />

<script src="https://cdn.tailwindcss.com"></script>
<script>
  tailwind.config = {
    theme: {
      extend: {
        fontFamily: {
          display: ['"Clash Display"', 'system-ui', 'sans-serif'],
          sans: ['"Plus Jakarta Sans"', 'system-ui', 'sans-serif'],
        },
        colors: {
          // VoCal-dark mapping of sotto's roles
          ink:         '#0A0A0B',  // page canvas
          inkRaised:   '#121214',  // card core
          inkElevated: '#1F1F24',  // popovers / chips
          bone:        '#F6F4EC',  // primary text
          ash:         '#BDBBB2',  // secondary text
          smoke:       '#86847B',  // tertiary text
          voltage:     '#E5FF59',  // accent (lime)
          voltageDeep: '#B7D03A',
          pulse:       '#FF5436',  // live-mic / energy
        },
        boxShadow: {
          // Geometry preserved from sotto's "Soft Structuralism", retuned for dark
          float:  '0 1px 0 rgba(255,255,255,0.04) inset, 0 24px 60px -24px rgba(0,0,0,0.6)',
          floatl: '0 1px 0 rgba(255,255,255,0.05) inset, 0 50px 110px -30px rgba(0,0,0,0.7)',
          inset:  'inset 0 1px 0 rgba(255,255,255,0.06), inset 0 -1px 0 rgba(0,0,0,0.3)',
        },
        transitionTimingFunction: {
          fluid:  'cubic-bezier(0.22, 1, 0.36, 1)',
          spring: 'cubic-bezier(0.32, 0.72, 0, 1)',
        },
      },
    },
  };
</script>

<style>
  :root { color-scheme: dark; }
  body { background:#0A0A0B; -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; }
  ::selection { background:#E5FF59; color:#0A0A0B; }

  /* Film grain — white on dark, 3.5% opacity */
  .grain::after{
    content:""; position:fixed; inset:0; z-index:60; pointer-events:none; opacity:.035;
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.82' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' fill='white'/%3E%3C/svg%3E");
    mix-blend-mode:screen;
  }

  /* Scroll-reveal */
  .reveal{ opacity:0; transform:translateY(42px); filter:blur(10px); }
  .reveal.in{ opacity:1; transform:none; filter:blur(0);
    transition:opacity .9s cubic-bezier(0.22,1,0.36,1), transform 1s cubic-bezier(0.22,1,0.36,1), filter 1s cubic-bezier(0.22,1,0.36,1); }

  /* Hamburger morph */
  .bar{ transition:transform .5s cubic-bezier(0.32,0.72,0,1), opacity .35s ease; transform-origin:center; }
  .nav-open .bar-1{ transform:translateY(6px) rotate(45deg); }
  .nav-open .bar-2{ opacity:0; transform:scaleX(0); }
  .nav-open .bar-3{ transform:translateY(-6px) rotate(-45deg); }

  /* Full-screen menu */
  .menu{ opacity:0; visibility:hidden; transition:opacity .6s cubic-bezier(0.22,1,0.36,1), visibility .6s; }
  .menu.show{ opacity:1; visibility:visible; }
  .menu li{ opacity:0; transform:translateY(48px); }
  .menu.show li{ opacity:1; transform:none;
    transition:opacity .8s cubic-bezier(0.22,1,0.36,1), transform .9s cubic-bezier(0.22,1,0.36,1); }
  .menu.show li:nth-child(1){ transition-delay:.10s }
  .menu.show li:nth-child(2){ transition-delay:.16s }
  .menu.show li:nth-child(3){ transition-delay:.22s }
  .menu.show li:nth-child(4){ transition-delay:.28s }
  .menu.show li:nth-child(5){ transition-delay:.34s }

  /* Hero scrub mask */
  .hero-stage{
    -webkit-mask-image:radial-gradient(ellipse 76% 72% at 50% 44%, #000 34%, rgba(0,0,0,0.55) 62%, transparent 84%);
            mask-image:radial-gradient(ellipse 76% 72% at 50% 44%, #000 34%, rgba(0,0,0,0.55) 62%, transparent 84%);
  }
  .hero-stage video{
    filter:saturate(1.05) contrast(1.02);
    -webkit-mask-image:radial-gradient(ellipse 68% 70% at 50% 50%, #000 42%, rgba(0,0,0,0.45) 64%, transparent 84%);
            mask-image:radial-gradient(ellipse 68% 70% at 50% 50%, #000 42%, rgba(0,0,0,0.45) 64%, transparent 84%);
  }
  .hero-copy{ text-shadow:0 1px 2px rgba(10,10,11,0.96), 0 0 14px rgba(10,10,11,0.92), 0 2px 30px rgba(10,10,11,0.88); }

  /* Explode scrub mask */
  .scrub-mask{
    -webkit-mask-image:linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.35) 9%, #000 22%, #000 78%, rgba(0,0,0,0.35) 91%, transparent 100%);
            mask-image:linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.35) 9%, #000 22%, #000 78%, rgba(0,0,0,0.35) 91%, transparent 100%);
  }
  .scrub-mask video{ filter:saturate(1.06) contrast(1.03); }

  .scrub-panel{ opacity:0; transform:translateY(40px); filter:blur(10px);
    transition:opacity .8s cubic-bezier(0.22,1,0.36,1), transform .9s cubic-bezier(0.22,1,0.36,1), filter .9s cubic-bezier(0.22,1,0.36,1); }
  .scrub-panel.active{ opacity:1; transform:none; filter:blur(0); }

  @media (prefers-reduced-motion: reduce){
    .scrub{ height:auto !important; }
    .scrub-stage{ position:static !important; min-height:auto !important; height:auto !important; display:block !important; }
    .scrub-panel{ position:static !important; opacity:1 !important; transform:none !important; filter:none !important; margin-bottom:3rem; }
  }

  /* Vox waveform */
  @keyframes vox { 0%,100%{ transform:scaleY(.18) } 50%{ transform:scaleY(1) } }
  .vox span{ display:block; width:6px; height:64px; border-radius:99px; background:#F6F4EC;
    transform:scaleY(.2); transform-origin:center; animation:vox 1.25s cubic-bezier(0.22,1,0.36,1) infinite; }
  .vox span:nth-child(odd){ background:#E5FF59 }

  /* Marquee */
  @keyframes drift { from{ transform:translate3d(0,0,0) } to{ transform:translate3d(-50%,0,0) } }
  .drift{ animation:drift 32s linear infinite; }

  /* FAQ accordion */
  .faq-body{ display:grid; grid-template-rows:0fr; transition:grid-template-rows .55s cubic-bezier(0.32,0.72,0,1); }
  .faq.open .faq-body{ grid-template-rows:1fr; }
  .faq-body > div{ overflow:hidden; }
  .faq .plus{ transition:transform .5s cubic-bezier(0.32,0.72,0,1); }
  .faq.open .plus{ transform:rotate(135deg); }

  @media (prefers-reduced-motion: reduce){
    .reveal,.reveal.in{ opacity:1!important; transform:none!important; filter:none!important; transition:none!important; }
    .vox span,.drift{ animation:none!important; }
  }
</style>
</head>

<body class="grain font-sans text-bone antialiased overflow-x-hidden">

  <!-- Soft ambient light field -->
  <div aria-hidden="true" class="pointer-events-none fixed inset-0 -z-10">
    <div class="absolute -top-40 left-1/2 h-[640px] w-[1100px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(229,255,89,0.06),transparent)]"></div>
    <div class="absolute top-[55%] -right-40 h-[560px] w-[560px] rounded-full bg-[radial-gradient(closest-side,rgba(255,84,54,0.05),transparent)]"></div>
  </div>

  <!-- Glass-pill nav -->
  <header id="shell" class="fixed inset-x-0 top-0 z-50 flex justify-center px-4">
    <nav class="mt-5 flex w-full max-w-[1180px] items-center justify-between gap-6 rounded-full border border-bone/[0.06] bg-inkRaised/70 px-4 py-2.5 pl-6 shadow-float backdrop-blur-xl transition-all duration-700 ease-fluid">
      <a href="#top" class="flex items-center gap-2.5">
        <span class="grid h-8 w-8 place-items-center rounded-full bg-bone text-ink">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M12 3v10"/><path d="M8 7a4 4 0 0 0 8 0"/><path d="M5 13a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>
        </span>
        <span class="font-display text-[19px] font-semibold tracking-tight italic">VoCal</span>
      </a>
      <div class="hidden items-center gap-9 text-[14px] font-medium text-ash md:flex">
        <a href="#features" class="transition-colors duration-300 ease-fluid hover:text-bone">Features</a>
        <a href="#how" class="transition-colors duration-300 ease-fluid hover:text-bone">How it works</a>
        <a href="#pricing" class="transition-colors duration-300 ease-fluid hover:text-bone">Pricing</a>
        <a href="#faq" class="transition-colors duration-300 ease-fluid hover:text-bone">FAQ</a>
      </div>
      <div class="flex items-center gap-2">
        <a href="#cta" class="group hidden items-center gap-3 rounded-full bg-bone py-2 pl-5 pr-2 text-[14px] font-medium text-ink transition-transform duration-500 ease-spring active:scale-[0.97] sm:flex">
          Get the app
          <span class="grid h-7 w-7 place-items-center rounded-full bg-ink/10 transition-transform duration-500 ease-spring group-hover:translate-x-0.5 group-hover:-translate-y-px group-hover:scale-105">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7"/><path d="M8 7h9v9"/></svg>
          </span>
        </a>
        <button id="burger" aria-label="Open menu" class="grid h-10 w-10 place-items-center rounded-full border border-bone/[0.06] bg-inkRaised/60 md:hidden">
          <span class="relative block h-3 w-5">
            <span class="bar bar-1 absolute left-0 top-0 block h-[2px] w-5 rounded bg-bone"></span>
            <span class="bar bar-2 absolute left-0 top-[5px] block h-[2px] w-5 rounded bg-bone"></span>
            <span class="bar bar-3 absolute left-0 top-[10px] block h-[2px] w-5 rounded bg-bone"></span>
          </span>
        </button>
      </div>
    </nav>
  </header>

  <!-- Mobile full-screen menu -->
  <div id="menu" class="menu fixed inset-0 z-40 bg-ink/85 backdrop-blur-3xl md:hidden">
    <ul class="flex h-full flex-col justify-center gap-2 px-8 font-display text-5xl font-semibold tracking-tight">
      <li><a href="#features" class="menu-link block py-2">Features</a></li>
      <li><a href="#how" class="menu-link block py-2">How it works</a></li>
      <li><a href="#pricing" class="menu-link block py-2">Pricing</a></li>
      <li><a href="#faq" class="menu-link block py-2">FAQ</a></li>
      <li class="pt-6"><a href="#cta" class="menu-link inline-flex items-center gap-3 rounded-full bg-bone px-7 py-4 text-lg text-ink">Get the app
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M7 17 17 7"/><path d="M8 7h9v9"/></svg></a></li>
    </ul>
  </div>

  <main id="top">
    <!-- SECTIONS GO HERE — added in subsequent tasks -->
  </main>

  <!-- Footer -->
  <footer class="mx-auto max-w-[1180px] px-5 pb-14 sm:px-8">
    <div class="flex flex-col gap-10 border-t border-bone/[0.08] pt-12 md:flex-row md:items-end md:justify-between">
      <div>
        <a href="#top" class="flex items-center gap-2.5">
          <span class="grid h-8 w-8 place-items-center rounded-full bg-bone text-ink">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M12 3v10"/><path d="M8 7a4 4 0 0 0 8 0"/><path d="M5 13a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>
          </span>
          <span class="font-display text-[19px] font-semibold tracking-tight italic">VoCal</span>
        </a>
        <p class="mt-4 max-w-[34ch] text-[14px] leading-relaxed text-ash">The voice-first nutrition tracker. Built for people who'd rather live their meals than log them.</p>
      </div>
      <div class="flex flex-wrap gap-x-12 gap-y-6 text-[14px] text-ash">
        <div class="flex flex-col gap-3"><span class="text-[11px] font-semibold uppercase tracking-[0.2em] text-bone">Product</span><a href="#features" class="transition-colors duration-300 ease-fluid hover:text-bone">Features</a><a href="#pricing" class="transition-colors duration-300 ease-fluid hover:text-bone">Pricing</a><a href="#how" class="transition-colors duration-300 ease-fluid hover:text-bone">How it works</a></div>
        <div class="flex flex-col gap-3"><span class="text-[11px] font-semibold uppercase tracking-[0.2em] text-bone">Company</span><a href="/privacy.html" class="transition-colors duration-300 ease-fluid hover:text-bone">Privacy</a><a href="/terms.html" class="transition-colors duration-300 ease-fluid hover:text-bone">Terms</a><a href="/support.html" class="transition-colors duration-300 ease-fluid hover:text-bone">Support</a></div>
      </div>
    </div>
    <p class="mt-10 text-[13px] text-ash/70">© 2026 VoCal. Crafted quietly.</p>
  </footer>

  <!-- JS modules added in Task 11 -->

</body>
</html>
```

- [ ] **Step 2: Open the file in a browser and verify**

Run:
```bash
open vocal-api/vocal-web/dist/index.html
```

Expected: dark page, floating glass-pill nav at the top with "VoCal" wordmark + 4 links + "Get the app" CTA, empty middle, footer at the bottom. No console errors when DevTools is open. Resize to <768px width to confirm the hamburger appears.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "$(cat <<'EOF'
feat(web): rebuild vocal-web shell on sotto structural system

Single static index.html with embedded Tailwind config, dark VoCal
palette mapping of sotto's roles, glass-pill floating nav, hamburger
morph, full-screen mobile menu, and film grain overlay (white-on-dark).
Body main is empty placeholder for next tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add the hero section

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html` (insert into `<main>`)

- [ ] **Step 1: Replace the placeholder comment with the hero section**

In `vocal-api/vocal-web/dist/index.html`, replace:

```html
    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

with:

```html
    <!-- Hero -->
    <section class="relative flex min-h-[100dvh] items-center overflow-hidden px-5 pb-24 pt-40 sm:px-8">
      <div class="hero-stage pointer-events-none absolute inset-0 -z-10 flex items-center justify-center">
        <video id="heroScrubVid" class="h-auto w-[95vw] min-w-[600px] max-w-[1220px] object-contain" muted playsinline preload="auto" aria-hidden="true">
          <source src="/mp_.mp4" type="video/mp4" />
        </video>
        <div class="absolute inset-0 bg-[radial-gradient(ellipse_70%_64%_at_50%_46%,rgba(10,10,11,0.5),rgba(10,10,11,0.2)_54%,rgba(10,10,11,0)_82%)]"></div>
      </div>

      <div class="relative z-10 mx-auto flex w-full max-w-[1180px] flex-col items-center text-center">
        <div class="reveal inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash shadow-float">
          <span class="h-1.5 w-1.5 rounded-full bg-voltage"></span> Vocal nutrition · now in beta
        </div>

        <h1 class="reveal hero-copy mt-7 max-w-[15ch] font-display text-[clamp(2.9rem,9vw,7.5rem)] font-semibold leading-[0.95] tracking-[-0.03em] text-bone">
          Just say what<br/>you ate.
          <span class="text-ash">We do the rest.</span>
        </h1>

        <p class="reveal hero-copy mt-8 max-w-[42ch] text-[clamp(1.2rem,1.8vw,1.5rem)] font-medium leading-relaxed text-bone/85">
          VoCal turns a sentence into a meal. <span class="font-semibold text-bone">"Medium fry from McDonald's"</span> — logged, broken down, tracked before you've put your phone down. No typing. No friction.
        </p>

        <div class="reveal mt-11 flex flex-wrap items-center justify-center gap-3">
          <a href="#cta" class="group flex items-center gap-3 rounded-full bg-bone py-3 pl-7 pr-2.5 text-[15px] font-medium text-ink shadow-floatl transition-transform duration-500 ease-spring active:scale-[0.98]">
            Start tracking by voice
            <span class="grid h-9 w-9 place-items-center rounded-full bg-ink/10 transition-transform duration-500 ease-spring group-hover:translate-x-0.5 group-hover:-translate-y-px group-hover:scale-105">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></svg>
            </span>
          </a>
          <a href="#how" class="flex items-center gap-2.5 rounded-full border border-bone/[0.08] bg-inkRaised/60 px-6 py-3 text-[15px] font-medium text-bone shadow-float transition-colors duration-500 ease-fluid hover:bg-inkRaised">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 5v14l11-7z"/></svg>
            See it work
          </a>
        </div>

        <!-- Double-bezel live capture card -->
        <div class="reveal mt-16 w-full">
          <div class="rounded-[2.25rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-floatl">
            <div class="rounded-[calc(2.25rem-0.5rem)] bg-inkRaised shadow-inset">
              <div class="flex flex-col items-center gap-7 px-6 py-10 sm:flex-row sm:px-12 sm:py-12">
                <div class="vox flex h-20 items-center gap-1.5" aria-hidden="true">
                  <span style="animation-delay:-.9s"></span><span style="animation-delay:-.2s"></span><span style="animation-delay:-.7s"></span><span style="animation-delay:-.35s"></span><span style="animation-delay:-.55s"></span><span style="animation-delay:-.1s"></span><span style="animation-delay:-.8s"></span><span style="animation-delay:-.45s"></span><span style="animation-delay:-.65s"></span><span style="animation-delay:-.25s"></span>
                </div>
                <div class="flex-1 text-center sm:text-left">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.22em] text-voltage">Listening</p>
                  <p class="mt-2 font-display text-2xl font-medium tracking-tight sm:text-3xl">"Chipotle bowl, double chicken, brown rice, black beans, guac."</p>
                </div>
                <div class="grid shrink-0 grid-cols-3 gap-3 sm:gap-4">
                  <div class="rounded-2xl bg-ink px-4 py-3 text-center"><p class="font-display text-xl font-semibold text-bone">820</p><p class="text-[11px] tracking-wide text-ash">kcal</p></div>
                  <div class="rounded-2xl bg-ink px-4 py-3 text-center"><p class="font-display text-xl font-semibold text-bone">62g</p><p class="text-[11px] tracking-wide text-ash">protein</p></div>
                  <div class="rounded-2xl bg-voltage/[0.14] px-4 py-3 text-center"><p class="font-display text-xl font-semibold text-voltage">1.2s</p><p class="text-[11px] tracking-wide text-voltage/80">logged</p></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload the page**

Run:
```bash
open vocal-api/vocal-web/dist/index.html
```

Expected: hero section now visible — the rotating-plate video frame (paused at frame 0 until JS scrub is wired), "Vocal nutrition · now in beta" pill, large display headline, two CTAs, live capture card with animated voltage vox bars and "Listening" eyebrow. Layout stacks on mobile.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add hero section with mp_.mp4 stage + live capture card

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Add the explode section + trust marquee

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with the explode + marquee sections**

In `vocal-api/vocal-web/dist/index.html`, replace:

```html
    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

with:

```html
    <!-- Exploding view -->
    <section id="explode" class="scrub relative bg-ink">
      <div class="scrub-stage sticky top-0 flex min-h-[100dvh] items-center overflow-hidden">
        <div class="scrub-video-wrap scrub-mask pointer-events-none absolute inset-0">
          <video id="scrubVid" class="h-full w-full object-cover" muted playsinline preload="auto" aria-hidden="true">
            <source src="/explode.mp4" type="video/mp4" />
          </video>
          <div class="absolute inset-0 bg-[radial-gradient(ellipse_62%_58%_at_40%_50%,rgba(10,10,11,0.58),rgba(10,10,11,0.24)_46%,rgba(10,10,11,0)_74%)]"></div>
        </div>
        <div aria-hidden="true" class="scrub-plate pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_56%_52%_at_50%_50%,rgba(10,10,11,0.94),rgba(10,10,11,0.74)_36%,rgba(10,10,11,0.32)_60%,rgba(10,10,11,0)_84%)]"></div>

        <div class="relative z-10 mx-auto flex w-full max-w-[1180px] flex-col items-center px-5 text-center sm:px-8">
          <article class="scrub-panel active flex flex-col items-center">
            <p class="hero-copy inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash shadow-float">It sees the whole plate</p>
            <h2 class="hero-copy mt-7 max-w-[18ch] font-display text-[clamp(2.6rem,6.5vw,5.5rem)] font-semibold leading-[0.98] tracking-[-0.03em] text-bone">Every meal, exploded into its parts.</h2>
            <p class="hero-copy mt-6 max-w-[46ch] text-[clamp(1.15rem,1.8vw,1.45rem)] font-medium leading-relaxed text-bone/80">One dish becomes its ingredients — each weighed, tagged and tracked — so you see exactly what you ate, component by component.</p>
          </article>
        </div>
      </div>
    </section>

    <!-- Trust marquee -->
    <section class="reveal overflow-hidden py-10">
      <div class="mx-auto mb-8 max-w-[1180px] px-5 text-center text-[11px] font-semibold uppercase tracking-[0.24em] text-ash/70 sm:px-8">Trusted by people who hate logging food</div>
      <div class="relative flex w-full overflow-hidden [mask-image:linear-gradient(90deg,transparent,#000_12%,#000_88%,transparent)]">
        <div class="drift flex shrink-0 items-center gap-14 pr-14 font-display text-2xl font-medium text-ash/55">
          <span>Runners</span><span class="text-voltage">·</span><span>Strength athletes</span><span class="text-voltage">·</span><span>Busy parents</span><span class="text-voltage">·</span><span>Dietitians</span><span class="text-voltage">·</span><span>Coaches</span><span class="text-voltage">·</span><span>Home cooks</span><span class="text-voltage">·</span>
          <span>Runners</span><span class="text-voltage">·</span><span>Strength athletes</span><span class="text-voltage">·</span><span>Busy parents</span><span class="text-voltage">·</span><span>Dietitians</span><span class="text-voltage">·</span><span>Coaches</span><span class="text-voltage">·</span><span>Home cooks</span><span class="text-voltage">·</span>
        </div>
      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload and verify**

Reload `vocal-api/vocal-web/dist/index.html`. Expected: scroll past the hero, you land on a sticky explode section showing `explode.mp4` first frame (autoplay wired in Task 11). Scroll past it and the marquee starts drifting voltage-dotted audiences.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add explode section + trust marquee

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Add the features bento grid

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with the features bento**

Replace `<!-- SECTIONS GO HERE — added in subsequent tasks -->` with:

```html
    <!-- Features bento -->
    <section id="features" class="mx-auto max-w-[1180px] px-5 py-24 sm:px-8 sm:py-36">
      <div class="reveal max-w-[42ch]">
        <p class="inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash">Why VoCal</p>
        <h2 class="mt-6 font-display text-[clamp(2.2rem,5vw,3.8rem)] font-semibold leading-[1.02] tracking-[-0.03em]">Tracking that gets out of your way.</h2>
      </div>

      <div class="mt-14 grid grid-cols-1 gap-5 md:grid-cols-12">

        <article class="reveal group md:col-span-7 md:row-span-2">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="flex h-full flex-col justify-between rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset sm:p-11">
              <div>
                <span class="grid h-12 w-12 place-items-center rounded-2xl bg-voltage/[0.14] text-voltage">
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>
                </span>
                <h3 class="mt-8 font-display text-3xl font-semibold tracking-tight sm:text-4xl">Speak naturally.<br/>It just understands.</h3>
                <p class="mt-4 max-w-[40ch] leading-relaxed text-ash">No rigid commands. Say it the way you'd tell a friend — "grande iced oat latte from Starbucks" — and VoCal parses portions, brands and modifiers on its own.</p>
              </div>
              <div class="mt-10 rounded-2xl bg-ink p-5">
                <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-ash/70">Heard</p>
                <p class="mt-2 font-display text-lg font-medium leading-snug text-bone">"A handful of almonds and an oat-milk cortado after my run."</p>
                <div class="mt-4 flex flex-wrap gap-2 text-[12px] font-medium text-ash">
                  <span class="rounded-full bg-inkRaised px-3 py-1">Almonds · 28g</span>
                  <span class="rounded-full bg-inkRaised px-3 py-1">Cortado · oat</span>
                  <span class="rounded-full bg-voltage/[0.14] px-3 py-1 text-voltage">+ post-workout tag</span>
                </div>
              </div>
            </div>
          </div>
        </article>

        <article class="reveal md:col-span-5">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="h-full rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
              <span class="grid h-12 w-12 place-items-center rounded-2xl bg-ink text-bone">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg>
              </span>
              <h3 class="mt-7 font-display text-2xl font-semibold tracking-tight">Macros, the moment you finish talking</h3>
              <p class="mt-3 leading-relaxed text-ash">Calories, protein, carbs and fat resolve in real time against the same food graph the iOS app uses — accurate down to the portion.</p>
            </div>
          </div>
        </article>

        <article class="reveal md:col-span-5">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="h-full rounded-[calc(2rem-0.5rem)] bg-bone p-8 text-ink shadow-inset">
              <span class="grid h-12 w-12 place-items-center rounded-2xl bg-ink/[0.08] text-ink">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a4 4 0 0 1 4 4 4 4 0 0 1 0 8 4 4 0 0 1-8 0 4 4 0 0 1 0-8 4 4 0 0 1 4-4Z"/><path d="M12 7v10"/></svg>
              </span>
              <h3 class="mt-7 font-display text-2xl font-semibold tracking-tight">A coach that nudges, gently</h3>
              <p class="mt-3 leading-relaxed text-ink/60">VoCal notices patterns — low protein before noon, salty Fridays — and offers one quiet, specific suggestion. Never a guilt notification.</p>
            </div>
          </div>
        </article>

        <article class="reveal md:col-span-4">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="h-full rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
              <span class="grid h-12 w-12 place-items-center rounded-2xl bg-voltage/[0.14] text-voltage">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>
              </span>
              <h3 class="mt-7 font-display text-xl font-semibold tracking-tight">Private by design</h3>
              <p class="mt-3 text-[15px] leading-relaxed text-ash">Voice is transcribed on-device. Your meals stay yours — no ad graph, ever.</p>
            </div>
          </div>
        </article>

        <article class="reveal md:col-span-4">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="h-full rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
              <span class="grid h-12 w-12 place-items-center rounded-2xl bg-ink text-bone">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18Z"/></svg>
              </span>
              <h3 class="mt-7 font-display text-xl font-semibold tracking-tight">Speaks 30 languages</h3>
              <p class="mt-3 text-[15px] leading-relaxed text-ash">Code-switch mid-sentence. VoCal handles regional dishes and mixed languages fluently.</p>
            </div>
          </div>
        </article>

        <article class="reveal md:col-span-4">
          <div class="h-full rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
            <div class="h-full rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
              <span class="grid h-12 w-12 place-items-center rounded-2xl bg-voltage/[0.14] text-voltage">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><rect x="8" y="3" width="8" height="18" rx="2.5"/><path d="M11 6h2"/></svg>
              </span>
              <h3 class="mt-7 font-display text-xl font-semibold tracking-tight">Lives on your wrist</h3>
              <p class="mt-3 text-[15px] leading-relaxed text-ash">Raise, speak, done. Watch-first logging and Apple Health sync.</p>
            </div>
          </div>
        </article>

      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload and verify**

Expected: 7/5/5/4/4/4 bento grid on desktop, single-column stack on mobile. The 5-col "coach" card is bone-inverted (light card on dark page).

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add features bento (7/5/5/4/4/4)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Add the "How it works" editorial steps

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with the how-it-works section**

Replace `<!-- SECTIONS GO HERE — added in subsequent tasks -->` with:

```html
    <!-- How it works -->
    <section id="how" class="mx-auto max-w-[1180px] px-5 py-24 sm:px-8 sm:py-36">
      <div class="grid gap-14 md:grid-cols-12">
        <div class="reveal md:col-span-5">
          <p class="inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash">Three seconds</p>
          <h2 class="mt-6 font-display text-[clamp(2.2rem,5vw,3.8rem)] font-semibold leading-[1.02] tracking-[-0.03em]">From mouth to macros.</h2>
          <p class="mt-5 max-w-[34ch] leading-relaxed text-ash">The entire loop is shorter than unlocking most apps. That's the whole point — tracking only works if it's effortless enough to actually keep doing.</p>
        </div>

        <div class="reveal md:col-span-7">
          <ol class="flex flex-col gap-4">
            <li class="rounded-[1.75rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
              <div class="flex items-start gap-6 rounded-[calc(1.75rem-0.375rem)] bg-inkRaised p-7 shadow-inset">
                <span class="font-display text-3xl font-semibold text-ash/40">01</span>
                <div><h3 class="font-display text-xl font-semibold tracking-tight">Hold and speak</h3><p class="mt-1.5 leading-relaxed text-ash">One button. Describe the meal however it comes out — fragments, brand names, rough portions.</p></div>
              </div>
            </li>
            <li class="rounded-[1.75rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
              <div class="flex items-start gap-6 rounded-[calc(1.75rem-0.375rem)] bg-inkRaised p-7 shadow-inset">
                <span class="font-display text-3xl font-semibold text-ash/40">02</span>
                <div><h3 class="font-display text-xl font-semibold tracking-tight">VoCal reasons it out</h3><p class="mt-1.5 leading-relaxed text-ash">It infers cooking method, sensible portions and likely brands, then resolves the nutrition graph.</p></div>
              </div>
            </li>
            <li class="rounded-[1.75rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
              <div class="flex items-start gap-6 rounded-[calc(1.75rem-0.375rem)] bg-bone p-7 text-ink shadow-inset">
                <span class="font-display text-3xl font-semibold text-ink/35">03</span>
                <div><h3 class="font-display text-xl font-semibold tracking-tight">Confirm with a glance</h3><p class="mt-1.5 leading-relaxed text-ink/60">A clean card appears. Tap once if it's right — or just say "make it two". Logged.</p></div>
              </div>
            </li>
          </ol>
        </div>
      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload and verify**

Expected: two-column on desktop (5/7), single column on mobile. Step 03 is bone-inverted.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add how-it-works editorial step list

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Add the testimonial + pricing sections

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with testimonial + pricing**

Replace `<!-- SECTIONS GO HERE — added in subsequent tasks -->` with:

```html
    <!-- Testimonial -->
    <section class="mx-auto max-w-[1180px] px-5 py-24 sm:px-8 sm:py-32">
      <div class="reveal rounded-[2.5rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-floatl">
        <div class="rounded-[calc(2.5rem-0.5rem)] bg-inkRaised px-8 py-16 text-center shadow-inset sm:px-16 sm:py-24">
          <svg class="mx-auto mb-8 text-voltage" width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"><path d="M7 7h4v6c0 2-1.5 4-4 4M14 7h4v6c0 2-1.5 4-4 4"/></svg>
          <p class="mx-auto max-w-[24ch] font-display text-[clamp(1.7rem,4vw,3rem)] font-medium leading-[1.12] tracking-[-0.02em] text-bone">I've abandoned every food tracker in a week. VoCal is the first one I still use after eight months.</p>
          <div class="mt-10 flex items-center justify-center gap-4">
            <span class="grid h-11 w-11 place-items-center rounded-full bg-voltage/[0.14] font-display font-semibold text-voltage">MK</span>
            <div class="text-left"><p class="font-medium text-bone">Maya Krishnan</p><p class="text-[14px] text-ash">Sports nutritionist · Brooklyn</p></div>
          </div>
        </div>
      </div>
    </section>

    <!-- Pricing -->
    <section id="pricing" class="mx-auto max-w-[1180px] px-5 py-24 sm:px-8 sm:py-36">
      <div class="reveal mx-auto max-w-[40ch] text-center">
        <p class="inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash">Pricing</p>
        <h2 class="mt-6 font-display text-[clamp(2.2rem,5vw,3.8rem)] font-semibold leading-[1.02] tracking-[-0.03em]">Honest, and quietly priced.</h2>
      </div>

      <div class="mt-14 grid gap-5 md:grid-cols-3">
        <div class="reveal rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
          <div class="flex h-full flex-col rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
            <p class="font-display text-lg font-semibold text-bone">Taste</p>
            <p class="mt-3 font-display text-5xl font-semibold tracking-tight text-bone">Free</p>
            <p class="mt-2 text-[14px] text-ash">Voice logging, daily macros, 7-day history.</p>
            <a href="#cta" class="mt-8 flex items-center justify-center gap-2 rounded-full border border-bone/[0.1] bg-ink py-3 text-[14px] font-medium text-bone transition-colors duration-500 ease-fluid hover:bg-inkElevated">Start free</a>
          </div>
        </div>

        <div class="reveal rounded-[2rem] border border-voltage/20 bg-voltage/[0.04] p-2 shadow-floatl">
          <div class="flex h-full flex-col rounded-[calc(2rem-0.5rem)] bg-bone p-8 text-ink shadow-inset">
            <div class="flex items-center justify-between">
              <p class="font-display text-lg font-semibold">VoCal Pro</p>
              <span class="rounded-full bg-voltage/[0.2] px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.18em] text-voltageDeep">Most loved</span>
            </div>
            <p class="mt-3 font-display text-5xl font-semibold tracking-tight">$6<span class="text-xl text-ink/45">/mo</span></p>
            <p class="mt-2 text-[14px] text-ink/55">Unlimited history, AI coach, micros, watch app, HealthKit, full export.</p>
            <a href="#cta" class="group mt-8 flex items-center justify-center gap-3 rounded-full bg-ink py-3 pl-5 pr-2.5 text-[14px] font-medium text-bone transition-transform duration-500 ease-spring active:scale-[0.98]">
              Go Pro
              <span class="grid h-7 w-7 place-items-center rounded-full bg-bone/[0.08] transition-transform duration-500 ease-spring group-hover:translate-x-0.5 group-hover:-translate-y-px group-hover:scale-105">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></svg>
              </span>
            </a>
          </div>
        </div>

        <div class="reveal rounded-[2rem] border border-bone/[0.05] bg-bone/[0.02] p-2 shadow-float">
          <div class="flex h-full flex-col rounded-[calc(2rem-0.5rem)] bg-inkRaised p-8 shadow-inset">
            <p class="font-display text-lg font-semibold text-bone">Clinic</p>
            <p class="mt-3 font-display text-5xl font-semibold tracking-tight text-bone">Custom</p>
            <p class="mt-2 text-[14px] text-ash">Practitioner dashboards, client sharing, HIPAA terms.</p>
            <a href="#cta" class="mt-8 flex items-center justify-center gap-2 rounded-full border border-bone/[0.1] bg-ink py-3 text-[14px] font-medium text-bone transition-colors duration-500 ease-fluid hover:bg-inkElevated">Talk to us</a>
          </div>
        </div>
      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload and verify**

Expected: editorial quote in a dark card with voltage attribution chip; three-tier pricing with the middle Pro tier bone-inverted and showing "Most loved" pill.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add testimonial + 3-tier pricing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Add the FAQ accordion

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with the FAQ section**

Replace `<!-- SECTIONS GO HERE — added in subsequent tasks -->` with:

```html
    <!-- FAQ -->
    <section id="faq" class="mx-auto max-w-[860px] px-5 py-24 sm:px-8 sm:py-36">
      <div class="reveal text-center">
        <p class="inline-flex w-max items-center gap-2 rounded-full border border-bone/[0.07] bg-inkRaised/70 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ash">Questions</p>
        <h2 class="mt-6 font-display text-[clamp(2rem,5vw,3.4rem)] font-semibold leading-[1.05] tracking-[-0.03em]">The things people ask.</h2>
      </div>

      <div class="reveal mt-12 flex flex-col gap-3">
        <div class="faq rounded-[1.5rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
          <div class="rounded-[calc(1.5rem-0.375rem)] bg-inkRaised shadow-inset">
            <button class="faq-trigger flex w-full items-center justify-between gap-6 px-7 py-6 text-left">
              <span class="font-display text-lg font-medium tracking-tight">How accurate can a spoken estimate really be?</span>
              <span class="plus grid h-7 w-7 shrink-0 place-items-center rounded-full bg-voltage/[0.14] text-voltage"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></span>
            </button>
            <div class="faq-body"><div><p class="px-7 pb-7 leading-relaxed text-ash">Within a few percent for common foods. VoCal models typical portions and cooking methods, and you can correct any item by voice — it learns your defaults over time.</p></div></div>
          </div>
        </div>

        <div class="faq rounded-[1.5rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
          <div class="rounded-[calc(1.5rem-0.375rem)] bg-inkRaised shadow-inset">
            <button class="faq-trigger flex w-full items-center justify-between gap-6 px-7 py-6 text-left">
              <span class="font-display text-lg font-medium tracking-tight">Does it work offline and on the watch?</span>
              <span class="plus grid h-7 w-7 shrink-0 place-items-center rounded-full bg-voltage/[0.14] text-voltage"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></span>
            </button>
            <div class="faq-body"><div><p class="px-7 pb-7 leading-relaxed text-ash">Yes. Capture works fully offline and syncs when you reconnect. The watch app is voice-first, so you can log mid-walk without your phone.</p></div></div>
          </div>
        </div>

        <div class="faq rounded-[1.5rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
          <div class="rounded-[calc(1.5rem-0.375rem)] bg-inkRaised shadow-inset">
            <button class="faq-trigger flex w-full items-center justify-between gap-6 px-7 py-6 text-left">
              <span class="font-display text-lg font-medium tracking-tight">What happens to my voice recordings?</span>
              <span class="plus grid h-7 w-7 shrink-0 place-items-center rounded-full bg-voltage/[0.14] text-voltage"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></span>
            </button>
            <div class="faq-body"><div><p class="px-7 pb-7 leading-relaxed text-ash">Audio is transcribed on-device using Apple Speech, and the raw audio is discarded immediately — only the structured meal is stored. Nothing is sold or used for advertising.</p></div></div>
          </div>
        </div>

        <div class="faq rounded-[1.5rem] border border-bone/[0.05] bg-bone/[0.02] p-1.5 shadow-float">
          <div class="rounded-[calc(1.5rem-0.375rem)] bg-inkRaised shadow-inset">
            <button class="faq-trigger flex w-full items-center justify-between gap-6 px-7 py-6 text-left">
              <span class="font-display text-lg font-medium tracking-tight">Can I export to my dietitian's tools?</span>
              <span class="plus grid h-7 w-7 shrink-0 place-items-center rounded-full bg-voltage/[0.14] text-voltage"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></span>
            </button>
            <div class="faq-body"><div><p class="px-7 pb-7 leading-relaxed text-ash">Pro exports clean CSV and PDF, and Clinic plans add a shared practitioner dashboard with read-only client access.</p></div></div>
          </div>
        </div>
      </div>
    </section>

    <!-- SECTIONS GO HERE — added in subsequent tasks -->
```

- [ ] **Step 2: Reload and verify**

Expected: four questions stacked, "+" icons on the right in voltage chips. Accordion JS wired in Task 11.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add FAQ accordion

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Add the final CTA + remove placeholder

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace the placeholder with the final CTA**

Replace `<!-- SECTIONS GO HERE — added in subsequent tasks -->` with:

```html
    <!-- Final CTA -->
    <section id="cta" class="mx-auto max-w-[1180px] px-5 pb-28 sm:px-8">
      <div class="reveal rounded-[2.75rem] border border-bone/[0.06] bg-bone/[0.02] p-2 shadow-floatl">
        <div class="relative overflow-hidden rounded-[calc(2.75rem-0.5rem)] bg-bone px-8 py-20 text-center text-ink shadow-inset sm:px-16 sm:py-28">
          <div aria-hidden="true" class="pointer-events-none absolute -top-32 left-1/2 h-[420px] w-[720px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(229,255,89,0.4),transparent)]"></div>
          <div class="relative">
            <h2 class="mx-auto max-w-[16ch] font-display text-[clamp(2.2rem,6vw,4.6rem)] font-semibold leading-[1.0] tracking-[-0.03em]">Stop typing your food. Start telling it.</h2>
            <p class="mx-auto mt-6 max-w-[42ch] leading-relaxed text-ink/60">Free on iOS. Your first logged meal takes about three seconds.</p>
            <div class="mt-11 flex flex-wrap justify-center gap-3">
              <a href="#" class="group flex items-center gap-3 rounded-full bg-ink py-3.5 pl-7 pr-2.5 text-[15px] font-medium text-bone transition-transform duration-500 ease-spring active:scale-[0.98]">
                Download VoCal
                <span class="grid h-9 w-9 place-items-center rounded-full bg-bone/10 transition-transform duration-500 ease-spring group-hover:translate-x-0.5 group-hover:-translate-y-px group-hover:scale-105">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v12"/><path d="M7 12l5 5 5-5"/><path d="M5 20h14"/></svg>
                </span>
              </a>
              <a href="#" class="rounded-full border border-ink/15 px-7 py-3.5 text-[15px] font-medium text-ink transition-colors duration-500 ease-fluid hover:bg-ink/5">Watch the 40s demo</a>
            </div>
          </div>
        </div>
      </div>
    </section>
```

(Note: this task is the LAST one inserting a section, so it does NOT re-add the `<!-- SECTIONS GO HERE -->` placeholder — that pattern ends here.)

- [ ] **Step 2: Reload and verify**

Expected: big bone-on-ink CTA card with a voltage radial halo, two action buttons. This is the last content block before the footer.

- [ ] **Step 3: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "feat(web): add final CTA with voltage halo

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Wire JS modules (nav, menu, reveal, hero-scrub, explode, FAQ)

**Files:**
- Modify: `vocal-api/vocal-web/dist/index.html`

- [ ] **Step 1: Replace `<!-- JS modules added in Task 11 -->` with the full script block**

In `vocal-api/vocal-web/dist/index.html`, replace:

```html
  <!-- JS modules added in Task 11 -->
```

with:

```html
  <script>
    // Fluid Island nav condense on scroll
    const nav = document.querySelector('#shell nav');
    let ticking = false;
    function onScroll(){
      const y = window.scrollY;
      nav.classList.toggle('max-w-[980px]', y > 40);
      nav.classList.toggle('shadow-floatl', y > 40);
      ticking = false;
    }
    window.addEventListener('scroll', () => { if(!ticking){ requestAnimationFrame(onScroll); ticking = true; } }, { passive:true });

    // Hamburger morph + full-screen menu
    const burger = document.getElementById('burger');
    const menu = document.getElementById('menu');
    const setMenu = (open) => {
      burger.classList.toggle('nav-open', open);
      menu.classList.toggle('show', open);
      burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
      document.body.style.overflow = open ? 'hidden' : '';
    };
    burger.addEventListener('click', () => setMenu(!menu.classList.contains('show')));
    document.querySelectorAll('.menu-link').forEach(a => a.addEventListener('click', () => setMenu(false)));
    window.addEventListener('keydown', e => { if(e.key === 'Escape') setMenu(false); });

    // Scroll-reveal via IntersectionObserver
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry, i) => {
        if(entry.isIntersecting){
          const delay = entry.target.dataset.d ? +entry.target.dataset.d : Math.min(i * 70, 280);
          setTimeout(() => entry.target.classList.add('in'), delay);
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });

    document.querySelectorAll('.reveal').forEach((el, i) => {
      el.dataset.d = (i % 4) * 80;
      io.observe(el);
    });

    // Hero video scroll-scrub
    (function () {
      const vid = document.getElementById('heroScrubVid');
      if (!vid) return;
      const hero = vid.closest('section');
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const FPS = 24, STEP = 1 / FPS, SCRUB_VH = 3;
      let duration = 0, desired = 0, inView = true, scheduled = false;
      vid.preload = 'auto'; vid.muted = true; vid.pause();
      function warm() {
        duration = vid.duration || 0;
        try { vid.currentTime = 0; } catch (e) {}
        if (!reduce) vid.play().then(() => { vid.pause(); vid.currentTime = 0; }).catch(() => {});
      }
      if (vid.readyState >= 1) warm();
      else vid.addEventListener('loadedmetadata', warm, { once: true });
      if (reduce) return;
      function pump() {
        if (!duration || vid.seeking || vid.readyState < 2) return;
        if (Math.abs(desired - vid.currentTime) < STEP) return;
        try { vid.currentTime = desired; } catch (e) {}
      }
      vid.addEventListener('seeked', pump);
      function compute() {
        const range = window.innerHeight * SCRUB_VH;
        const p = Math.min(1, Math.max(0, window.scrollY / range));
        desired = Math.round(p * duration * FPS) / FPS;
        pump();
      }
      const heroIo = new IntersectionObserver(([e]) => {
        inView = e.isIntersecting;
        if (inView) onHeroScroll();
      }, { threshold: 0 });
      if (hero) heroIo.observe(hero);
      function onHeroScroll() {
        if (!inView || scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => { scheduled = false; compute(); });
      }
      window.addEventListener('scroll', onHeroScroll, { passive: true });
      window.addEventListener('resize', onHeroScroll, { passive: true });
      compute();
    })();

    // Explode video: autoplay once at ≥0.9 visibility
    (function () {
      const section = document.getElementById('explode');
      const vid = document.getElementById('scrubVid');
      if (!section || !vid) return;
      const stage = section.querySelector('.scrub-stage') || section;
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      vid.loop = false; vid.muted = true; vid.playsInline = true; vid.preload = 'auto';
      vid.defaultPlaybackRate = 1.2; vid.playbackRate = 1.2;
      vid.addEventListener('play', () => { vid.playbackRate = 1.2; });
      try { vid.currentTime = 0; } catch (e) {}
      vid.pause();
      if (reduce) return;
      let played = false;
      const explodeIo = new IntersectionObserver((entries) => {
        const e = entries[0];
        if (!played && e.isIntersecting && e.intersectionRatio >= 0.9) {
          played = true;
          vid.play().catch(() => {});
          explodeIo.disconnect();
        }
      }, { threshold: [0, 0.9, 1] });
      explodeIo.observe(stage);
    })();

    // FAQ accordion (single-open)
    document.querySelectorAll('.faq-trigger').forEach(btn => {
      btn.addEventListener('click', () => {
        const item = btn.closest('.faq');
        const isOpen = item.classList.contains('open');
        document.querySelectorAll('.faq').forEach(f => f.classList.remove('open'));
        if(!isOpen) item.classList.add('open');
      });
    });
  </script>
```

- [ ] **Step 2: Reload and test interactively**

Run:
```bash
open vocal-api/vocal-web/dist/index.html
```

Verify each module:
- **Nav condense**: scroll down → nav pill shrinks (`max-w-[980px]`) and gets a deeper shadow.
- **Reveal**: each section fades + un-blurs as it enters viewport.
- **Hero scrub**: slowly scroll within the hero — the plate video frames step forward as you scroll. Open DevTools Network tab and confirm `mp_.mp4` is fetched exactly once.
- **Explode autoplay**: scroll into the `#explode` section — once it fills the viewport (≥90%), `explode.mp4` autoplays at 1.2× and freezes on the last frame.
- **Hamburger**: resize to <768px width, click the hamburger → full-screen menu fades in with staggered links. Press Escape → closes.
- **FAQ**: click a question → it opens. Click another → the first closes, the new one opens.

- [ ] **Step 3: Test reduce-motion**

In Chrome DevTools: cmd-shift-p → "Emulate CSS prefers-reduced-motion: reduce" → reload. Expected: video sits on first frame (no scrub, no autoplay), all sections visible without fade animations, scroll still works.

- [ ] **Step 4: Commit**

```bash
git add vocal-api/vocal-web/dist/index.html
git commit -m "$(cat <<'EOF'
feat(web): wire JS modules — nav, menu, reveal, hero-scrub, explode, FAQ

All six interaction systems from sotto, ported verbatim with no behavior
changes. prefers-reduced-motion short-circuits scroll-scrub and reveals.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Build aux pages (terms / privacy / support / beta)

**Files:**
- New: `vocal-api/vocal-web/dist/terms.html`
- New: `vocal-api/vocal-web/dist/privacy.html`
- New: `vocal-api/vocal-web/dist/support.html`
- New: `vocal-api/vocal-web/dist/beta.html`

These pages reuse the same head + nav + footer shell as `index.html`, with a simple article body. Each needs to return HTTP 200 from Cloudflare Pages for App Store Connect.

- [ ] **Step 1: Write `vocal-api/vocal-web/dist/terms.html`**

```html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VoCal — Terms of Service</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700,500&display=swap" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  :root { color-scheme: dark; }
  body { background:#0A0A0B; color:#F6F4EC; font-family:'Plus Jakarta Sans', system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  a { color:#E5FF59; text-decoration:none; }
  a:hover { text-decoration:underline; }
  h1 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:clamp(2rem, 5vw, 3rem); letter-spacing:-0.03em; }
  h2 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:1.25rem; margin-top:2.5rem; }
  p { color:#BDBBB2; line-height:1.6; margin-top:1rem; }
  main { max-width:680px; margin:0 auto; padding:5rem 1.25rem; }
  header a { color:#F6F4EC; }
  footer { max-width:680px; margin:0 auto; padding:2rem 1.25rem 4rem; border-top:1px solid rgba(246,244,236,0.08); margin-top:5rem; font-size:13px; color:#86847B; }
</style>
</head>
<body>
<main>
  <header><a href="/">← VoCal</a></header>
  <h1>Terms of Service</h1>
  <p>Last updated: May 2026.</p>
  <h2>Use of VoCal</h2>
  <p>VoCal is provided as-is for personal nutrition tracking. You're responsible for the accuracy of what you log; VoCal estimates macros but is not a medical device and shouldn't be used as a substitute for professional dietary advice.</p>
  <h2>Subscriptions</h2>
  <p>VoCal Pro is an auto-renewing subscription managed through your App Store account. You can cancel any time from the App Store settings.</p>
  <h2>Acceptable use</h2>
  <p>Don't attempt to abuse the speech parsing endpoint, reverse-engineer the app, or use VoCal to harass other users.</p>
  <h2>Termination</h2>
  <p>We may suspend accounts that violate these terms. You may delete your account at any time from the in-app settings.</p>
  <h2>Contact</h2>
  <p>Questions? <a href="/support.html">Get in touch</a>.</p>
</main>
<footer>© 2026 VoCal</footer>
</body>
</html>
```

- [ ] **Step 2: Write `vocal-api/vocal-web/dist/privacy.html`**

```html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VoCal — Privacy Policy</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700,500&display=swap" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  :root { color-scheme: dark; }
  body { background:#0A0A0B; color:#F6F4EC; font-family:'Plus Jakarta Sans', system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  a { color:#E5FF59; text-decoration:none; }
  a:hover { text-decoration:underline; }
  h1 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:clamp(2rem, 5vw, 3rem); letter-spacing:-0.03em; }
  h2 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:1.25rem; margin-top:2.5rem; }
  p { color:#BDBBB2; line-height:1.6; margin-top:1rem; }
  main { max-width:680px; margin:0 auto; padding:5rem 1.25rem; }
  header a { color:#F6F4EC; }
  footer { max-width:680px; margin:0 auto; padding:2rem 1.25rem 4rem; border-top:1px solid rgba(246,244,236,0.08); margin-top:5rem; font-size:13px; color:#86847B; }
</style>
</head>
<body>
<main>
  <header><a href="/">← VoCal</a></header>
  <h1>Privacy Policy</h1>
  <p>Last updated: May 2026.</p>
  <h2>What we collect</h2>
  <p>Meals you log (food name, macros, timestamp), your daily totals, and your goal settings. We do not collect raw voice audio — speech is transcribed on-device by Apple Speech and the audio is discarded immediately.</p>
  <h2>How we use it</h2>
  <p>Only to provide the product. The transcript of what you said is sent to our parsing endpoint to resolve macros, then stored alongside your meal. Optionally, with your permission, meals are mirrored to Apple Health.</p>
  <h2>What we don't do</h2>
  <p>We don't sell your data. We don't share it with advertisers. There is no ad graph.</p>
  <h2>Your controls</h2>
  <p>You can delete any meal in-app. Deleting your account from settings removes everything we have on the server within 30 days.</p>
  <h2>Contact</h2>
  <p>Questions? <a href="/support.html">Get in touch</a>.</p>
</main>
<footer>© 2026 VoCal</footer>
</body>
</html>
```

- [ ] **Step 3: Write `vocal-api/vocal-web/dist/support.html`**

```html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VoCal — Support</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700,500&display=swap" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  :root { color-scheme: dark; }
  body { background:#0A0A0B; color:#F6F4EC; font-family:'Plus Jakarta Sans', system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  a { color:#E5FF59; text-decoration:none; }
  a:hover { text-decoration:underline; }
  h1 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:clamp(2rem, 5vw, 3rem); letter-spacing:-0.03em; }
  h2 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:1.25rem; margin-top:2.5rem; }
  p { color:#BDBBB2; line-height:1.6; margin-top:1rem; }
  main { max-width:680px; margin:0 auto; padding:5rem 1.25rem; }
  header a { color:#F6F4EC; }
  footer { max-width:680px; margin:0 auto; padding:2rem 1.25rem 4rem; border-top:1px solid rgba(246,244,236,0.08); margin-top:5rem; font-size:13px; color:#86847B; }
</style>
</head>
<body>
<main>
  <header><a href="/">← VoCal</a></header>
  <h1>Support</h1>
  <p>The fastest way to get help.</p>
  <h2>Email</h2>
  <p><a href="mailto:hello@vocal.best">hello@vocal.best</a> — we read everything.</p>
  <h2>Common questions</h2>
  <p>How accurate is voice logging? See the <a href="/#faq">FAQ</a>.</p>
  <p>How to cancel Pro? Open the App Store → your account → Subscriptions → VoCal.</p>
  <p>Export your data? Settings → Export. Pro tiers get CSV; Free tier gets JSON.</p>
</main>
<footer>© 2026 VoCal</footer>
</body>
</html>
```

- [ ] **Step 4: Write `vocal-api/vocal-web/dist/beta.html`**

```html
<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VoCal — Beta access</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700,500&display=swap" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  :root { color-scheme: dark; }
  body { background:#0A0A0B; color:#F6F4EC; font-family:'Plus Jakarta Sans', system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  a { color:#E5FF59; text-decoration:none; }
  a:hover { text-decoration:underline; }
  h1 { font-family:'Clash Display', system-ui, sans-serif; font-weight:600; font-size:clamp(2rem, 5vw, 3rem); letter-spacing:-0.03em; }
  p { color:#BDBBB2; line-height:1.6; margin-top:1rem; }
  main { max-width:680px; margin:0 auto; padding:5rem 1.25rem; }
  header a { color:#F6F4EC; }
  footer { max-width:680px; margin:0 auto; padding:2rem 1.25rem 4rem; border-top:1px solid rgba(246,244,236,0.08); margin-top:5rem; font-size:13px; color:#86847B; }
  .cta { display:inline-flex; align-items:center; gap:.75rem; background:#F6F4EC; color:#0A0A0B; padding:.875rem 1.5rem; border-radius:9999px; font-weight:500; margin-top:2rem; }
</style>
</head>
<body>
<main>
  <header><a href="/">← VoCal</a></header>
  <h1>Join the beta</h1>
  <p>VoCal is in private beta on TestFlight. We add a small batch of testers each week so we can listen carefully.</p>
  <p>To request access, email <a href="mailto:hello@vocal.best">hello@vocal.best</a> with the subject "beta" and the country you're in.</p>
  <a class="cta" href="mailto:hello@vocal.best?subject=beta">Email for access</a>
</main>
<footer>© 2026 VoCal</footer>
</body>
</html>
```

- [ ] **Step 5: Verify each loads in a browser**

Run:
```bash
open vocal-api/vocal-web/dist/terms.html vocal-api/vocal-web/dist/privacy.html vocal-api/vocal-web/dist/support.html vocal-api/vocal-web/dist/beta.html
```

Expected: four dark-themed pages with a "← VoCal" back link, all readable, all linking back to `/` and `/support.html` where referenced.

- [ ] **Step 6: Commit**

```bash
git add vocal-api/vocal-web/dist/terms.html vocal-api/vocal-web/dist/privacy.html vocal-api/vocal-web/dist/support.html vocal-api/vocal-web/dist/beta.html
git commit -m "$(cat <<'EOF'
feat(web): add aux pages (terms / privacy / support / beta)

Minimal shell — head + back-link + article body + footer. Same dark
palette and font stack as index.html. Required for App Store Connect URLs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Phase 3 — iOS

## Task 13: Add `Theme.Motion` easing tokens (with test)

**Files:**
- Modify: `VoCal/VoCal/Theme.swift`
- Modify: `VoCal/VoCalTests/VoCalTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `VoCal/VoCalTests/VoCalTests.swift` (inside `struct VoCalTests {`, after the last test):

```swift
    // MARK: Theme.Motion — sotto easing curves ported to iOS

    @Test func motionFluidUsesSottoCubicBezier() async throws {
        let curve = Theme.Motion.fluid
        // The four control points come straight from sotto's CSS:
        //   cubic-bezier(0.22, 1, 0.36, 1)
        #expect(curve.p1.x == 0.22)
        #expect(curve.p1.y == 1.0)
        #expect(curve.p2.x == 0.36)
        #expect(curve.p2.y == 1.0)
    }

    @Test func motionSpringUsesSottoCubicBezier() async throws {
        let curve = Theme.Motion.spring
        //   cubic-bezier(0.32, 0.72, 0, 1)
        #expect(curve.p1.x == 0.32)
        #expect(curve.p1.y == 0.72)
        #expect(curve.p2.x == 0.0)
        #expect(curve.p2.y == 1.0)
    }
```

- [ ] **Step 2: Run the test, verify it fails**

Run:
```bash
xcodebuild test -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoCalTests/VoCalTests/motionFluidUsesSottoCubicBezier 2>&1 | tail -20
```

Expected: build failure with "Cannot find 'Theme.Motion' in scope".

- [ ] **Step 3: Add `Theme.Motion` to `Theme.swift`**

Insert into `VoCal/VoCal/Theme.swift` immediately before the `// MARK: Gradients` comment (around line 101):

```swift
    // MARK: Motion — easing curves ported from sotto's CSS

    /// Cubic bezier control points, mirroring sotto's two easing tokens.
    /// We expose the control points (not a pre-baked `Animation`) so that
    /// callers can use them with `Animation.timingCurve(_:_:_:_:duration:)`
    /// at the duration they need, and so the tests can assert exact values.
    enum Motion {
        struct Curve: Equatable {
            let p1: CGPoint
            let p2: CGPoint

            func animation(duration: TimeInterval) -> Animation {
                .timingCurve(p1.x, p1.y, p2.x, p2.y, duration: duration)
            }
        }

        /// Sotto's "fluid" curve: cubic-bezier(0.22, 1, 0.36, 1).
        /// Use for opacity + translation reveals.
        static let fluid = Curve(p1: CGPoint(x: 0.22, y: 1.0),
                                 p2: CGPoint(x: 0.36, y: 1.0))

        /// Sotto's "spring" curve: cubic-bezier(0.32, 0.72, 0, 1).
        /// Use for scale and press-down feedback.
        static let spring = Curve(p1: CGPoint(x: 0.32, y: 0.72),
                                  p2: CGPoint(x: 0.0, y: 1.0))
    }
```

- [ ] **Step 4: Run tests again, verify pass**

Run:
```bash
xcodebuild test -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoCalTests/VoCalTests/motionFluidUsesSottoCubicBezier -only-testing:VoCalTests/VoCalTests/motionSpringUsesSottoCubicBezier 2>&1 | tail -5
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add VoCal/VoCal/Theme.swift VoCal/VoCalTests/VoCalTests.swift
git commit -m "feat(ios): add Theme.Motion easing tokens from sotto

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Add `MealEntry.Component` + `components` field (with tests)

**Files:**
- Modify: `VoCal/VoCal/Item.swift`
- Modify: `VoCal/VoCalTests/VoCalTests.swift`

Edit (replaceMeal) is explicitly out of scope per spec §6 — the sheet only needs read + delete in v1. We add only the data-model pieces consumed by the new sheet.

- [ ] **Step 1: Write the failing tests**

Append to `VoCal/VoCalTests/VoCalTests.swift` (inside `struct VoCalTests {`, after the last test from Task 13):

```swift
    // MARK: MealEntry.Component — ingredient breakdown for the explode sheet

    @Test func mealEntryComponentEncodesAndDecodes() async throws {
        let c = MealEntry.Component(name: "Black beans", grams: 90, kcal: 110)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(MealEntry.Component.self, from: data)
        #expect(back.name == "Black beans")
        #expect(back.grams == 90)
        #expect(back.kcal == 110)
    }

    @Test func mealEntryComponentsFieldIsOptional() async throws {
        // Decoding an old persisted MealEntry that has no `components` key
        // must still succeed. This protects against a stale-snapshot crash
        // after we ship the new field.
        let id = UUID().uuidString
        let ts = Date().timeIntervalSince1970
        let legacyJSON = """
        {
          "id":"\(id)",
          "name":"Apple",
          "detail":"raw, medium",
          "calories":95, "protein":0, "carbs":25, "fat":0,
          "loggedAt":\(ts),
          "slot":"snack",
          "source":"manual"
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        let meal = try dec.decode(MealEntry.self, from: data)
        #expect(meal.components == nil)
    }
```

- [ ] **Step 2: Run, verify fail**

Run:
```bash
xcodebuild test -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoCalTests/VoCalTests/mealEntryComponentEncodesAndDecodes 2>&1 | tail -10
```

Expected: build error mentioning `MealEntry.Component`.

- [ ] **Step 3: Add `Component` and `components` to `MealEntry`**

In `VoCal/VoCal/Item.swift`, the `MealEntry` struct starts at line 15 and ends at line 53. Replace the entire struct definition (lines 15–53) with:

```swift
struct MealEntry: Identifiable, Hashable, Codable {
    enum Source: String, Hashable, Codable { case voice, photo, manual, voicePhoto = "voice+photo", barcode }
    enum Slot: String, Hashable, CaseIterable, Codable { case breakfast, lunch, dinner, snack }

    /// One ingredient parsed out of a meal. Optional fields stay nil when the
    /// parser couldn't pin them down — the MealExplodeSheet renders gracefully
    /// either way.
    struct Component: Hashable, Codable {
        var name: String
        var grams: Double?
        var kcal: Int?
    }

    let id: UUID
    var name: String
    var detail: String
    var calories: Int
    var protein: Int   // grams
    var carbs: Int     // grams
    var fat: Int       // grams
    var loggedAt: Date
    var slot: Slot
    var source: Source
    var components: [Component]?

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        loggedAt: Date,
        slot: Slot,
        source: Source,
        components: [Component]? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.loggedAt = loggedAt
        self.slot = slot
        self.source = source
        self.components = components
    }
}
```

- [ ] **Step 4: Run both tests, verify pass**

Run:
```bash
xcodebuild test -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoCalTests/VoCalTests/mealEntryComponentEncodesAndDecodes -only-testing:VoCalTests/VoCalTests/mealEntryComponentsFieldIsOptional 2>&1 | tail -8
```

Expected: TEST SUCCEEDED for both.

- [ ] **Step 5: Confirm the full app still builds**

Run:
```bash
xcodebuild build -scheme VoCal -destination 'generic/platform=iOS' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. The optional `components` field decoding cleanly from old snapshots is what keeps existing on-disk state from breaking.

- [ ] **Step 6: Commit**

```bash
git add VoCal/VoCal/Item.swift VoCal/VoCalTests/VoCalTests.swift
git commit -m "$(cat <<'EOF'
feat(ios): add MealEntry.Component + components field

MealEntry now carries an optional [Component] array used by the new
MealExplodeSheet to render ingredient chips. components is optional so
old persisted snapshots decode without crashing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Register `Resources/` folder and add videos to the Xcode target

**Files:**
- Modify: `VoCal/VoCal.xcodeproj/project.pbxproj` (via Xcode UI)
- (Resources/*.mp4 already on disk from Task 2)

This task requires Xcode UI to ensure the videos are bundled correctly. Doing pbxproj edits by hand is error-prone for resource folders.

- [ ] **Step 1: Open the project in Xcode**

Run:
```bash
open VoCal/VoCal.xcodeproj
```

- [ ] **Step 2: Add the Resources folder reference**

In Xcode's left sidebar, right-click the **VoCal** group (the inner one under the project root, containing `VoCalApp.swift` etc.) → **Add Files to "VoCal"…** → in the file picker, navigate to `VoCal/VoCal/Resources/` and select the folder itself → ensure these options:
- "Copy items if needed": UNCHECKED
- "Create groups": UNCHECKED
- "Create folder references": CHECKED (blue folder icon)
- "Add to targets: VoCal": CHECKED

Click **Add**. The Resources folder should appear in the sidebar as a blue folder containing `mp_.mp4` and `explode.mp4`.

- [ ] **Step 3: Verify the videos bundle**

Build the app:
```bash
xcodebuild build -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

Then locate the built bundle:
```bash
xcodebuild -showBuildSettings -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>/dev/null | grep -E 'BUILT_PRODUCTS_DIR|PRODUCT_NAME' | head -2
```

Use the BUILT_PRODUCTS_DIR shown to list the built app's contents:
```bash
ls "$(xcodebuild -showBuildSettings -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>/dev/null | awk -F'= ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')/VoCal.app/Resources/"
```

Expected: `mp_.mp4` and `explode.mp4` listed.

- [ ] **Step 4: Commit the pbxproj change**

```bash
git add VoCal/VoCal.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
chore(ios): register Resources/ folder reference for video bundling

Adds the Resources folder (containing mp_.mp4 and explode.mp4 copied
from sotto via scripts/sync-sotto-assets.sh) to the VoCal app target so
the videos ship in the bundle. Folder reference (blue), not a group,
so any future sync adds files automatically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Add `BentoCard`, `AmbientVideoPlayer`, and `IngredientChip` to `Components.swift`

**Files:**
- Modify: `VoCal/VoCal/Components.swift`

Three new pieces, all visual. No unit tests — verification via `#Preview` and a smoke build.

- [ ] **Step 1: Add `import AVKit` to the top of `Components.swift`**

Open `VoCal/VoCal/Components.swift`. Find the existing imports at the top (likely `import SwiftUI`). Add immediately after:

```swift
import AVKit
import AVFoundation
```

- [ ] **Step 2: Append the three new components to the bottom of `Components.swift`**

Add this block at the very end of `Components.swift` (after the last existing component):

```swift
// MARK: - BentoCard (sotto's double-bezel geometry, dark-adapted)

/// View modifier that wraps content in the sotto double-bezel card:
/// outer thin ring (white at 4%) → inner inkRaised fill → inset top
/// highlight. Apply to any view that should sit as a "card" on Today.
///
/// Usage: `MyView().bentoCard()` or `.bentoCard(padding: 18, radius: 24)`.
struct BentoCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.inkRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .blendMode(.plusLighter)
                            .opacity(0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func bentoCard(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(BentoCardModifier(padding: padding, radius: radius))
    }
}

// MARK: - AmbientVideoPlayer (silent looping video on a card)

/// A muted, silent `AVPlayer`-backed view that loops the given bundled
/// resource. Used on Today (mp_.mp4 looping) and as the static-frame
/// backdrop of the onboarding intro and the meal explode sheet.
///
/// Pass `loop: false` and `rate: 1.2` for the explode-sheet single-play.
struct AmbientVideoPlayer: UIViewRepresentable {
    let resource: String        // e.g. "mp_"
    let ext: String             // e.g. "mp4"
    var loop: Bool = true
    var rate: Float = 1.0

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return view
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = loop ? .none : .pause
        view.player = player

        if loop {
            view.looper = AVPlayerLooper(player: player, templateItem: item)
        }

        // Defer play() to next runloop so the layer is sized first.
        DispatchQueue.main.async {
            player.play()
            player.rate = rate
        }
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.player?.rate = rate
    }
}

final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
    var looper: AVPlayerLooper?
}

// MARK: - IngredientChip (one parsed component, used on the explode sheet)

struct IngredientChip: View {
    let component: MealEntry.Component

    var body: some View {
        HStack(spacing: 6) {
            Text(component.name)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Palette.bone)
            if let grams = component.grams {
                Text("· \(Int(grams))g")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.ash)
            }
            if let kcal = component.kcal {
                Text("· \(kcal) kcal")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.voltage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Theme.Palette.inkElevated)
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        )
    }
}
```

- [ ] **Step 3: Build the app to confirm everything compiles**

Run:
```bash
xcodebuild build -scheme VoCal -destination 'generic/platform=iOS' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add VoCal/VoCal/Components.swift
git commit -m "$(cat <<'EOF'
feat(ios): add BentoCard, AmbientVideoPlayer, IngredientChip

BentoCard: sotto's double-bezel geometry adapted to dark — outer 4%
hairline ring, inner inkRaised fill, inset top highlight.

AmbientVideoPlayer: UIViewRepresentable wrapping AVPlayerLayer.
Looping by default for the Today plate clip; can be configured for
single-play + 1.2x rate for the explode-sheet backdrop.

IngredientChip: capsule with name + optional grams + optional kcal,
voltage for the kcal segment.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Create `MealExplodeSheet.swift`

**Files:**
- New: `VoCal/VoCal/MealExplodeSheet.swift`

- [ ] **Step 1: Write the file**

Create `VoCal/VoCal/MealExplodeSheet.swift`:

```swift
//
//  MealExplodeSheet.swift
//  VoCal
//
//  Sheet that "explodes" a logged meal into its parsed components,
//  with explode.mp4 playing once behind staggered ingredient chips.
//

import SwiftUI

struct MealExplodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let meal: MealEntry

    @State private var visibleChipCount: Int = 0

    private var chips: [MealEntry.Component] {
        if let components = meal.components, !components.isEmpty {
            return components
        }
        // Fallback: a single chip with the meal's own name.
        return [MealEntry.Component(name: meal.name,
                                    grams: nil,
                                    kcal: meal.calories)]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Backdrop video — plays once at 1.2x.
            AmbientVideoPlayer(resource: "explode", ext: "mp4",
                               loop: false, rate: 1.2)
                .ignoresSafeArea()
                .opacity(0.55)
                .overlay(
                    LinearGradient(colors: [
                        Theme.Palette.ink.opacity(0.0),
                        Theme.Palette.ink.opacity(0.85)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                )

            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                    .padding(10)
                    .background(Circle().fill(Theme.Palette.inkRaised.opacity(0.7)))
                    .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .padding(.top, 20)
            .padding(.leading, 20)

            // Content panel
            VStack(spacing: 24) {
                Spacer()

                Text("PARSED")
                    .eyebrow(Theme.Palette.voltage)

                Text(meal.name)
                    .font(Theme.Font.serif(40, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Staggered ingredient chips
                FlowLayout(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { idx, comp in
                        if idx < visibleChipCount {
                            IngredientChip(component: comp)
                                .transition(.asymmetric(
                                    insertion: .opacity
                                        .combined(with: .offset(y: 12))
                                        .combined(with: .scale(scale: 0.96, anchor: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Macros readout
                HStack(spacing: 20) {
                    macroChip("\(meal.calories)", "kcal")
                    macroChip("\(meal.protein)g", "protein")
                    macroChip("\(meal.carbs)g", "carbs")
                    macroChip("\(meal.fat)g", "fat")
                }
                .padding(.top, 8)

                // Delete action (Edit deliberately deferred — see spec §6)
                Button(action: {
                    appModel.removeMeal(meal)
                    dismiss()
                }) {
                    Text("Delete")
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Palette.pulse)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().stroke(Theme.Palette.pulse.opacity(0.35),
                                             lineWidth: 1)
                        )
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Palette.ink)
        .preferredColorScheme(.dark)
        .onAppear { startChipReveal() }
    }

    @ViewBuilder
    private func macroChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Font.serif(20, weight: .semibold))
                .foregroundStyle(Theme.Palette.bone)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.ash)
        }
        .frame(minWidth: 56)
    }

    private func startChipReveal() {
        if reduceMotion {
            visibleChipCount = chips.count
            return
        }
        // 80ms stagger, fluid curve.
        for i in 1...chips.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + Double(i - 1) * 0.08) {
                withAnimation(Theme.Motion.fluid.animation(duration: 0.5)) {
                    visibleChipCount = i
                }
            }
        }
    }
}

// MARK: - FlowLayout (simple wrapping HStack for the chips)

/// Minimal flow-layout for chip wrapping. Lays out children left-to-right,
/// wrapping to a new line when the next child would exceed the proposed width.
/// SwiftUI ≥16 has `Layout` protocol — we use it here rather than reaching for
/// a third-party dependency.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        // Center each row horizontally.
        var rowItems: [(LayoutSubview, CGSize)] = []
        func flushRow() {
            let rowWidth = rowItems.reduce(CGFloat(0)) { $0 + $1.1.width } +
                CGFloat(max(0, rowItems.count - 1)) * spacing
            var rx = bounds.minX + (maxWidth - rowWidth) / 2
            for (sub, size) in rowItems {
                sub.place(at: CGPoint(x: rx, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(size))
                rx += size.width + spacing
            }
            y += rowHeight + spacing
            rowItems.removeAll(keepingCapacity: true)
            rowHeight = 0
        }
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, !rowItems.isEmpty {
                flushRow()
                x = bounds.minX
            }
            rowItems.append((sub, size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !rowItems.isEmpty { flushRow() }
    }
}

#if DEBUG
#Preview("With components") {
    MealExplodeSheet(meal: MealEntry(
        name: "Chipotle bowl",
        detail: "Double chicken, brown rice, black beans, guac",
        calories: 820, protein: 62, carbs: 76, fat: 28,
        loggedAt: .now, slot: .lunch, source: .voice,
        components: [
            .init(name: "Brown rice", grams: 100, kcal: 150),
            .init(name: "Double chicken", grams: 170, kcal: 360),
            .init(name: "Black beans", grams: 90, kcal: 110),
            .init(name: "Guacamole", grams: 56, kcal: 130),
            .init(name: "Salsa", grams: 30, kcal: 10)
        ]))
    .environmentObject(AppModel(
        totals: DailyTotals(date: .now, calorieGoal: 2200, caloriesEaten: 820,
                             proteinGoal: 150, proteinEaten: 62,
                             carbsGoal: 250, carbsEaten: 76,
                             fatGoal: 70, fatEaten: 28),
        meals: [],
        profile: UserProfile(displayName: "Preview", streakDays: 0,
                             weightLbs: 170, heightInches: 70,
                             dailyCalorieGoal: 2200)))
}

#Preview("Without components") {
    MealExplodeSheet(meal: MealEntry(
        name: "Apple",
        detail: "raw, medium",
        calories: 95, protein: 0, carbs: 25, fat: 0,
        loggedAt: .now, slot: .snack, source: .manual))
    .environmentObject(AppModel(
        totals: DailyTotals(date: .now, calorieGoal: 2200, caloriesEaten: 95,
                             proteinGoal: 150, proteinEaten: 0,
                             carbsGoal: 250, carbsEaten: 25,
                             fatGoal: 70, fatEaten: 0),
        meals: [],
        profile: UserProfile(displayName: "Preview", streakDays: 0,
                             weightLbs: 170, heightInches: 70,
                             dailyCalorieGoal: 2200)))
}
#endif
```

- [ ] **Step 2: Register the new file in the Xcode target**

Open `VoCal/VoCal.xcodeproj` in Xcode (already open from Task 15). Right-click the **VoCal** group → **Add Files to "VoCal"…** → select `VoCal/VoCal/MealExplodeSheet.swift` → ensure "VoCal" target is checked → click **Add**.

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build -scheme VoCal -destination 'generic/platform=iOS' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. If "Cannot find type 'MealEntry'" appears, the file didn't get added to the target — repeat step 2.

- [ ] **Step 4: Preview both Preview blocks in Xcode**

In Xcode, open `MealExplodeSheet.swift`. The canvas should render two previews ("With components" and "Without components"). The explode video plays in both. Verify the chips wrap nicely and the macros row reads correctly.

- [ ] **Step 5: Commit**

```bash
git add VoCal/VoCal/MealExplodeSheet.swift VoCal/VoCal.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(ios): add MealExplodeSheet — meal detail with exploding video

New sheet presented on meal tap. Plays explode.mp4 once at 1.2x as the
backdrop, fades to ink at the bottom, then staggers in ingredient chips
(80ms gap, fluid easing). Falls back to a single chip when the meal has
no parsed components. Delete button removes the meal via AppModel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Add plate clip + wrap macros in bento + wire meal tap in `TodayView.swift`

**Files:**
- Modify: `VoCal/VoCal/TodayView.swift`

Current `TodayView.swift` (read at plan-writing time): `ScrollView { VStack { topBar, heroBlock, ringBlock, macrosBlock, mealsBlock, Color.clear } }`. The existing `ringBlock` already has its own card chrome (`inkSurface` background + hairline border) so we leave it alone. We insert a small plate clip below it, wrap the macro rows in `.bentoCard()`, and wire each meal row to present the explode sheet.

- [ ] **Step 1: Add the meal-sheet state**

Edit `VoCal/VoCal/TodayView.swift`. Find the existing `@Binding var showingPhoto: Bool` line (line 15). Add immediately after, before the `var body`:

Replace:
```swift
    @Binding var showingPhoto: Bool

    var body: some View {
```

with:

```swift
    @Binding var showingPhoto: Bool
    @State private var explodingMeal: MealEntry?

    var body: some View {
```

- [ ] **Step 2: Insert the `plateBlock` between `ringBlock` and `macrosBlock`**

In `var body` (the inner VStack at lines 19–26), the children are currently:
```
topBar
heroBlock
ringBlock
macrosBlock
mealsBlock
Color.clear.frame(height: 80)
```

Replace the line that reads `ringBlock` with these two lines (insert `plateBlock` after it):

Replace:
```swift
                ringBlock
                macrosBlock
```

with:

```swift
                ringBlock
                plateBlock
                macrosBlock
```

- [ ] **Step 3: Add the `plateBlock` computed property**

In the same file, find the end of `ringBlock`'s computed property (line 116, the `}` that closes `private var ringBlock`). Insert immediately after that closing brace:

```swift

    // MARK: plate clip — sotto's rotating-plate render, looping silently

    private var plateBlock: some View {
        AmbientVideoPlayer(resource: "mp_", ext: "mp4", loop: true, rate: 0.6)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
```

- [ ] **Step 4: Wrap the macro rows in a bento card**

In the same file, find `macrosBlock` (line 138). Replace the whole `private var macrosBlock` definition (lines 138–148) with:

```swift
    private var macrosBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Macros", eyebrow: "Today")
            VStack(spacing: 18) {
                MacroBar(label: "Protein", eaten: appModel.totals.proteinEaten, goal: appModel.totals.proteinGoal, tint: Theme.Palette.protein)
                MacroBar(label: "Carbs",   eaten: appModel.totals.carbsEaten,   goal: appModel.totals.carbsGoal,   tint: Theme.Palette.carbs)
                MacroBar(label: "Fat",     eaten: appModel.totals.fatEaten,     goal: appModel.totals.fatGoal,     tint: Theme.Palette.fat)
            }
            .bentoCard(padding: 18, radius: Theme.Radius.md)
        }
        .padding(.top, 4)
    }
```

- [ ] **Step 5: Wire meal tap → sheet**

In the same file, find `mealsBlock` (line 152). Replace the `ForEach(appModel.meals) { meal in MealCard(meal: meal) }` (lines 163–165) with:

Replace:
```swift
                VStack(spacing: 10) {
                    ForEach(appModel.meals) { meal in
                        MealCard(meal: meal)
                    }
                }
```

with:

```swift
                VStack(spacing: 10) {
                    ForEach(appModel.meals) { meal in
                        Button(action: { explodingMeal = meal }) {
                            MealCard(meal: meal)
                        }
                        .buttonStyle(.plain)
                    }
                }
```

- [ ] **Step 6: Attach the explode sheet to the ScrollView**

In the same file, find the `ScrollView` block in `var body` (line 18). Replace:

```swift
        .background(Color.clear)
        .scrollIndicators(.hidden)
    }
```

with:

```swift
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .sheet(item: $explodingMeal) { meal in
            MealExplodeSheet(meal: meal)
                .environmentObject(appModel)
        }
    }
```

- [ ] **Step 7: Build**

Run:
```bash
xcodebuild build -scheme VoCal -destination 'generic/platform=iOS' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Run in simulator and verify visually**

Open Xcode → press run, or:
```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
xcodebuild -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Once the simulator boots, install + launch the app. Verify:
- Today screen shows ring card → small looping plate clip → macros card (in bento chrome) → meals
- Tap a meal in "Today's log" → MealExplodeSheet presents, video plays, chips stagger in
- Delete on the sheet removes the meal and dismisses

- [ ] **Step 9: Commit**

```bash
git add VoCal/VoCal/TodayView.swift
git commit -m "$(cat <<'EOF'
feat(ios): add plate clip block + bento-wrap macros + meal-tap explode

New plateBlock between ringBlock and macrosBlock plays mp_.mp4 looping
silently at 0.6x in its own hairline-bordered card. Macros are wrapped
in a BentoCard. Meal rows are now Buttons that present MealExplodeSheet.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: Add the onboarding step-0 welcome screen

**Files:**
- Modify: `VoCal/VoCal/OnboardingFlow.swift`

Current `OnboardingFlow.swift` (read at plan-writing time): `enum Step: Int, CaseIterable { case pitch, name, body, goal, ready }` at line 22, initial state `step: Step = .pitch` at line 13, switch over step at lines 36–42, `advance()` method at line 341. The welcome step needs different chrome (no progress dots, no footer) so we conditionally bypass the existing VStack when `step == .welcome`.

- [ ] **Step 1: Add `welcome` as the first case in `Step`**

Find line 22:
```swift
    enum Step: Int, CaseIterable { case pitch, name, body, goal, ready }
```

Replace with:
```swift
    enum Step: Int, CaseIterable { case welcome, pitch, name, body, goal, ready }
```

- [ ] **Step 2: Change the initial step state**

Find line 13:
```swift
    @State private var step: Step = .pitch
```

Replace with:
```swift
    @State private var step: Step = .welcome
```

- [ ] **Step 3: Bypass the standard chrome when on the welcome step**

Find the start of `var body` (line 24). Replace lines 24–66 (the entire `var body` getter and its trailing `.sheet` modifier) with:

```swift
    var body: some View {
        Group {
            if step == .welcome {
                OnboardingWelcomeView(onBegin: {
                    withAnimation(.spring) { step = .pitch }
                })
            } else {
                standardFlow
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(onSubscribe: {
                appModel.upgradeToPro()
                showingPaywall = false
                finish()
            }, onSkip: {
                showingPaywall = false
                finish()
            })
            .presentationDetents([.large])
            .presentationBackground(Theme.Palette.ink)
        }
    }

    private var standardFlow: some View {
        ZStack {
            AmbientBackground()

            VStack(alignment: .leading, spacing: 0) {
                progressDots
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                Group {
                    switch step {
                    case .welcome: EmptyView() // unreachable here
                    case .pitch:   pitchView
                    case .name:    nameView
                    case .body:    bodyView
                    case .goal:    goalView
                    case .ready:   readyView
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
    }
```

- [ ] **Step 4: Filter welcome out of `progressDots`**

The existing `progressDots` iterates `Step.allCases` — now 6 cases. Welcome is a pre-onboarding moment, not a counted step, so it should not get a dot. Find lines 70–81 (the `progressDots` computed property). Replace with:

```swift
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.filter { $0 != .welcome }, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.Palette.voltage : Theme.Palette.hairlineStrong)
                    .frame(width: s == step ? 28 : 14, height: 3)
                    .animation(.easeOut(duration: 0.4), value: step)
            }
            Spacer()
            VoCalWordmark()
        }
    }
```

- [ ] **Step 5: Append `OnboardingWelcomeView` to the file**

Find the `#Preview` block at line 368. Insert the following BEFORE the `#Preview`:

```swift
// MARK: - Welcome step (cinematic pre-onboarding)

private struct OnboardingWelcomeView: View {
    let onBegin: () -> Void

    var body: some View {
        ZStack {
            AmbientVideoPlayer(resource: "mp_", ext: "mp4",
                               loop: true, rate: 1.0)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(colors: [
                        Theme.Palette.ink.opacity(0.55),
                        Theme.Palette.ink.opacity(0.92)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                )

            VStack {
                Text("VoCal")
                    .font(Theme.Font.wordmark)
                    .foregroundStyle(Theme.Palette.bone)
                    .padding(.top, 60)

                Spacer()

                VStack(spacing: 14) {
                    Text("Just say what\nyou ate.")
                        .font(Theme.Font.serif(48, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bone)
                        .multilineTextAlignment(.center)
                    Text("We do the rest.")
                        .font(Theme.Font.serif(28, weight: .regular, italic: true))
                        .foregroundStyle(Theme.Palette.ash)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: onBegin) {
                    HStack(spacing: 10) {
                        Text("Begin")
                            .font(Theme.Font.bodyBold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Theme.Palette.bone))
                }
                .padding(.bottom, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 6: Build**

Run:
```bash
xcodebuild build -scheme VoCal -destination 'generic/platform=iOS' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Run + verify**

In the simulator, reset to fresh onboarding: either delete the app from the home screen, or `xcrun simctl uninstall booted dev.spencer.VoCal` (substitute the actual bundle ID). Cold-launch.

Expected:
- Welcome screen appears first: looping plate video tinted toward ink, VoCal wordmark at top, "Just say what you ate. / We do the rest." headline, "Begin →" CTA at bottom.
- Tap "Begin" → springs into the existing pitch step ("INTRODUCING / The first calorie tracker that actually listens.").
- Progress dots show 5 dots (one per pitch/name/body/goal/ready) — welcome doesn't get a dot.
- Remaining steps work as before.

- [ ] **Step 8: Commit**

```bash
git add VoCal/VoCal/OnboardingFlow.swift
git commit -m "$(cat <<'EOF'
feat(ios): add onboarding welcome step with looping plate video

Inserted as Step.welcome ahead of the existing 5 steps. Full-bleed
mp_.mp4 loop tinted toward ink, wordmark + serif headline + 'Begin'
CTA. Excluded from progressDots so users still see 5 counted steps.
Springs into the existing pitch step on tap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 20: Final verification across all surfaces

**Files:**
- None modified.

End-to-end smoke test of everything. No commit on this task unless something breaks.

- [ ] **Step 1: Clean build**

```bash
xcodebuild clean build -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Run tests**

```bash
xcodebuild test -scheme VoCal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -8
```

Expected: all tests pass, including the three added in Tasks 13–14.

- [ ] **Step 3: Manual iOS QA**

Launch the simulator, delete the app, cold-launch:

| Surface | Check |
|---|---|
| Onboarding step 0 | Plate video loops, "Begin" advances |
| Onboarding flow | Remaining steps still work and complete |
| Today bento | Ring + plate clip side-by-side, plate loops at 0.6× |
| Today macro card | Wrapped in bento card, hairline visible |
| Meal tap → explode | Explode video plays once at 1.2×, chips stagger in over ~1.2s |
| Explode delete | Removes meal, sheet dismisses, totals decrement |
| Reduce-motion | Settings → Accessibility → Motion → Reduce Motion ON. Re-open explode sheet — chips appear instantly, video still plays. Today plate still loops. |

- [ ] **Step 4: Manual web QA**

```bash
open vocal-api/vocal-web/dist/index.html
```

Walk through:

| Section | Check |
|---|---|
| Nav | Pill condenses on scroll; hamburger shows ≤768px width |
| Hero | Plate video scrubs with scroll; "Listening" card with animated vox |
| Explode | Section sticks; video autoplays once at ≥0.9 ratio |
| Marquee | Drifts horizontally with voltage separators |
| Features | Bento 7/5/5/4/4/4 on desktop; "Heard" sample renders |
| How | Three numbered steps; #03 is bone-inverted |
| Testimonial | Large display quote with voltage attribution chip |
| Pricing | Three tiers; Pro is bone-inverted with "Most loved" pill |
| FAQ | Click → opens; click another → first closes |
| Final CTA | Bone card with voltage radial halo |
| Footer | Wordmark + columns + 2026 line |
| Aux pages | `/terms.html`, `/privacy.html`, `/support.html`, `/beta.html` all open and read correctly |
| Mobile (≤768px) | Bento stacks; hamburger menu reveals with staggered links; Escape closes |
| Reduce-motion | DevTools emulate reduce-motion → scroll, no scrub, all sections still visible |

- [ ] **Step 5: If anything failed, file a fix task; otherwise the plan is green**

No commit needed here. The previous commits already represent the change set.

---

## Out-of-scope / explicit non-tasks

- Replacing sotto's videos with VoCal-rendered originals (see Spec §9 risk #1)
- Splitting Phase 2/3 into independently shippable PRs (single PR for the full port is intentional — the iOS bento depends on the synced video assets)
- Re-encoding `mp_.mp4` for mobile bandwidth (will revisit if `du -h sotto/mp_.mp4` shows > 4 MB during implementation; the spec's transcode command is at §9 risk #3)
- Adding a build step to vocal-web (Tailwind via CDN is intentional for the static-page lifestyle)
- Any prophet-lab changes

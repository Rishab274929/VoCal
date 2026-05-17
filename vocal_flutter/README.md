# VoCal — Flutter (Android + iOS)

A cross-platform Flutter port of the SwiftUI **VoCal** iOS app — *the first
calorie tracker that actually listens.* Full feature parity: onboarding,
voice logging, the killer parse→follow-up→review flow, Today / Progress /
Coach / Profile, photo logging, body-fat baseline, paywall, and the same
editorial dark design system.

It reuses the **already-deployed backend** at `https://vocal.best/api`
(food parsing via LLM + chain canon, etc.), so this client is UI +
speech-to-text + on-device canon + local persistence + HTTP.

```
lib/
  main.dart                 app entry + onboarding gate (VoCalApp.swift)
  theme/theme.dart          design system (Theme.swift)
  models/models.dart        domain models + snapshot (Item.swift)
  state/app_model.dart      ChangeNotifier state (AppModel)
  services/
    persistence.dart        Documents JSON + macros snapshot (Persistence.swift)
    voice_api.dart          /api/voice/parse client (APIConfig + VoiceAPIClient)
    food_canon.dart         on-device Tier-0 canon (FoodCanon.swift)
    offline_fallback.dart   offline matcher (OfflineFallback.swift)
    speech_recorder.dart    STT wrapper (SpeechRecorder.swift)
  data/mock_data.dart       demo seed / prompts (MockData.swift)
  widgets/components.dart    component library (Components.swift)
  screens/                  Today / Progress / Coach / Profile / Paywall / Onboarding / shell
  sheets/                   Voice capture / Meal photo / Body-fat photo
assets/food_canon.json      ~100-entry on-device canon (copied from iOS bundle)
```

## What does NOT carry over (platform-specific iOS APIs)

- **HealthKit** writes (`VoCalHealth.swift`) — no Android equivalent. The
  fire-and-forget mirror is dropped; everything else (totals, persistence)
  is intact. Add `health` / Health Connect later if desired.
- **App Intents / Siri** (`AppIntents.swift`) — iOS-only OS integration.
  The same parse pipeline is reachable in-app; OS voice shortcuts are out
  of scope for the cross-platform client.

## Prerequisites

This machine does **not** have the Flutter SDK installed, so the native
Android/iOS project shells (Gradle, Info.plist, etc.) aren't generated yet.
On a machine with Flutter:

1. Install Flutter — https://docs.flutter.dev/get-started/install
   (`flutter doctor` should be green for Android; Xcode for iOS).
2. Android Studio / Android SDK + an emulator or a USB device with
   developer mode on.

## Setup (one command)

From this directory (`vocal_flutter/`):

**Windows (PowerShell):**
```powershell
./setup.ps1
```

**macOS / Linux:**
```bash
bash setup.sh
```

The script runs `flutter create .` (generates the android/ + ios/ shells
**without** touching `lib/` or `pubspec.yaml`), patches in the runtime
permissions (microphone, speech, camera, photos, internet), then
`flutter pub get`. It is idempotent — safe to re-run.

If you'd rather do it by hand, see [`tool/permissions.md`](tool/permissions.md)
for the exact AndroidManifest / Info.plist blocks.

## Run

```bash
flutter run                         # default backend: https://vocal.best/api
```

Build a shareable Android APK:

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

### Pointing at a local backend

```bash
flutter run --dart-define=VOCAL_API_BASE_URL=http://10.0.2.2:8788/api
```
`10.0.2.2` is the Android emulator's alias for your host machine (run the
Cloudflare Pages dev server with `cd ../vocal-api && npx wrangler pages dev`).

## Notes

- Display serif uses **Newsreader** via `google_fonts` (a New York-like
  transitional serif). It's fetched + cached at first run; offline it
  falls back to the platform serif gracefully. To guarantee an offline
  serif, bundle a TTF and switch `AppType.serif` to a local `fontFamily`.
- Speech-to-text uses the `speech_to_text` plugin (Android
  `SpeechRecognizer`, iOS `Speech`/`SFSpeechRecognizer`) — the direct
  analogue of the iOS `SFSpeechRecognizer` recorder.
- State persists to a single JSON file in the app documents directory and
  a `shared_preferences` macros snapshot, mirroring `Persistence.swift`.

#!/usr/bin/env bash
# VoCal Flutter — macOS/Linux setup.
# Generates native android/ + ios/ shells around the existing lib/ and
# pubspec.yaml, patches in runtime permissions, then fetches packages.
# Idempotent: safe to re-run.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 'flutter' not found on PATH."
  echo "Install: https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "==> flutter create (android + ios shells)..."
flutter create . --platforms=android,ios --org best.vocal --project-name vocal

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ] && ! grep -q "RECORD_AUDIO" "$MANIFEST"; then
  perl -0pi -e 's{(\s*<application)}{
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
    </queries>
$1}' "$MANIFEST"
  echo "==> AndroidManifest.xml patched."
else
  echo "==> AndroidManifest.xml already patched or missing, skipping."
fi

PLIST="ios/Runner/Info.plist"
if [ -f "$PLIST" ] && ! grep -q "NSMicrophoneUsageDescription" "$PLIST"; then
  perl -0pi -e 's{</dict>\s*</plist>\s*$}{\t<key>NSMicrophoneUsageDescription</key>
\t<string>VoCal listens while you say what you ate, then logs it for you.</string>
\t<key>NSSpeechRecognitionUsageDescription</key>
\t<string>VoCal transcribes your meal on-device so you can log by voice.</string>
\t<key>NSCameraUsageDescription</key>
\t<string>VoCal uses the camera for photo meal logging and body-fat baseline photos.</string>
\t<key>NSPhotoLibraryUsageDescription</key>
\t<string>VoCal lets you pick a meal photo from your library.</string>
</dict>
</plist>
}' "$PLIST"
  echo "==> Info.plist patched."
else
  echo "==> Info.plist already patched or missing, skipping."
fi

echo "==> flutter pub get..."
flutter pub get

echo ""
echo "Done. Next:"
echo "  flutter run                       # run on a device/emulator"
echo "  flutter build apk --release       # shareable Android APK"

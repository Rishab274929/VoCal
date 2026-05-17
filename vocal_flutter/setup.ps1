# VoCal Flutter — Windows setup.
# Generates the native android/ + ios/ shells around the existing lib/ and
# pubspec.yaml, patches in runtime permissions, then fetches packages.
# Idempotent: safe to re-run.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

# 1. Flutter present?
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'flutter' not found on PATH." -ForegroundColor Red
    Write-Host "Install: https://docs.flutter.dev/get-started/install" -ForegroundColor Yellow
    exit 1
}

# 2. Generate native scaffolding (skips existing lib/ + pubspec.yaml).
Write-Host "==> flutter create (android + ios shells)..." -ForegroundColor Cyan
flutter create . --platforms=android,ios --org best.vocal --project-name vocal

# 3. Patch AndroidManifest.xml
$manifest = Join-Path $root "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
    $m = Get-Content $manifest -Raw
    if ($m -notmatch "RECORD_AUDIO") {
        $perms = @"
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
    </queries>

"@
        # Insert the block immediately before the <application ...> tag.
        $m = $m -replace "(\s*)(<application)", ("`r`n" + $perms + '$1$2')
        Set-Content -Path $manifest -Value $m -Encoding utf8
        Write-Host "==> AndroidManifest.xml patched (mic/camera/internet/queries)." -ForegroundColor Green
    } else {
        Write-Host "==> AndroidManifest.xml already patched, skipping." -ForegroundColor DarkGray
    }
} else {
    Write-Host "WARN: $manifest not found." -ForegroundColor Yellow
}

# 4. Patch ios/Runner/Info.plist
$plist = Join-Path $root "ios\Runner\Info.plist"
if (Test-Path $plist) {
    $p = Get-Content $plist -Raw
    if ($p -notmatch "NSMicrophoneUsageDescription") {
        $keys = @"
	<key>NSMicrophoneUsageDescription</key>
	<string>VoCal listens while you say what you ate, then logs it for you.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>VoCal transcribes your meal on-device so you can log by voice.</string>
	<key>NSCameraUsageDescription</key>
	<string>VoCal uses the camera for photo meal logging and body-fat baseline photos.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>VoCal lets you pick a meal photo from your library.</string>
</dict>
</plist>
"@
        # Replace the final </dict></plist> with our keys + the closers.
        $p = $p -replace "</dict>\s*</plist>\s*$", $keys
        Set-Content -Path $plist -Value $p -Encoding utf8
        Write-Host "==> Info.plist patched (mic/speech/camera/photos)." -ForegroundColor Green
    } else {
        Write-Host "==> Info.plist already patched, skipping." -ForegroundColor DarkGray
    }
} else {
    Write-Host "WARN: $plist not found (ok if you only target Android)." -ForegroundColor Yellow
}

# 5. Packages
Write-Host "==> flutter pub get..." -ForegroundColor Cyan
flutter pub get

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  flutter run                       # run on a device/emulator"
Write-Host "  flutter build apk --release       # shareable Android APK"

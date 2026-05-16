# Manual permission setup

`setup.ps1` / `setup.sh` apply these automatically. If you ran
`flutter create .` by hand, add them yourself.

## Android — `android/app/src/main/AndroidManifest.xml`

Add **inside `<manifest>`, before `<application>`**:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>

<!-- speech_to_text: discover the on-device recognition service (Android 11+) -->
<queries>
    <intent>
        <action android:name="android.speech.RecognitionService"/>
    </intent>
</queries>
```

(`image_picker` needs no extra Android storage permission on modern
Android — it uses the system photo picker. `INTERNET` is usually present
in the generated manifest already; the patcher only adds what's missing.)

## iOS — `ios/Runner/Info.plist`

Add **inside the top-level `<dict>`** (before its closing `</dict>`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoCal listens while you say what you ate, then logs it for you.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>VoCal transcribes your meal on-device so you can log by voice.</string>
<key>NSCameraUsageDescription</key>
<string>VoCal uses the camera for photo meal logging and body-fat baseline photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>VoCal lets you pick a meal photo from your library.</string>
```

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "best.vocal.vocal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "best.vocal.vocal"
        // minSdk pinned to 24 (Android 7.0) — speech_to_text 7.x requires
        // SpeechRecognizer APIs only available there. Letting Flutter pick
        // (currently 21 on stable) yielded UnsupportedOperationException on
        // listen() for API 21-23 emulators during a previous QA pass.
        minSdk = 24
        // targetSdk 34 — required by Play Store for new uploads as of
        // Aug 2024 and necessary for the Android 13+ scoped READ_MEDIA_IMAGES
        // permission to be honored at runtime by image_picker.
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Replace with a real release keystore before shipping to
            // Play Store. Debug-signed for now so `flutter run --release`
            // works locally — Play Store will reject this build.
            signingConfig = signingConfigs.getByName("debug")
            // R8/proguard are off until we ship — speech_to_text + image_picker
            // + http have no consumer rules issues today, but enabling minify
            // without a verified rule pack will strip platform-channel handlers
            // and break the voice/camera flows silently.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

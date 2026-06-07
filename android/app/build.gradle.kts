plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services processes google-services.json for Firebase.
    // IMPORTANT: This requires android/app/google-services.json to be present.
    // Step 1: Download google-services.json from Firebase Console.
    // Step 2: Place it at android/app/google-services.json.
    // Step 3: Uncomment the line below.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.vext"

    // ── SDK versions ────────────────────────────────────────────────────────
    // compileSdk 36 required by flutter_blue_plus_android and geolocator_android.
    // Android SDK versions are backward compatible — compiling against 36 does
    // not change the minimum supported device (that is controlled by minSdk).
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // applicationId must match the package name registered in Firebase Console.
        // If you registered a different package (e.g. com.vext.app), update both
        // this value AND the Firebase project's Android app configuration.
        applicationId = "com.example.vext"

        // minSdk 21 = Android 5.0 Lollipop (minimum for BLE + foreground service).
        // Hardcoded to 21 — do NOT use flutter.minSdkVersion here. Flutter's default
        // resolves to 21 in 3.x but could regress in future SDK updates, silently
        // breaking BLE GATT and the foreground service on older devices.
        minSdk = 21

        // targetSdk 35 = Android 15 (foreground service type declarations fully supported).
        // Kept at 35 intentionally — targetSdk 36 (Android 16) triggers additional
        // background restrictions not yet handled in this milestone.
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

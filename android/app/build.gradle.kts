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
    // compileSdk must be >= 34 to use FOREGROUND_SERVICE_CONNECTED_DEVICE
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
        // Hardcoded — do NOT use flutter.minSdkVersion here. Flutter's default
        // resolves to 21 in 3.x but could regress in future SDK updates, silently
        // breaking BLE GATT and the foreground service on older devices.
        minSdk = flutter.minSdkVersion

        // targetSdk 34 = Android 14 (required for foreground service type declarations).
        targetSdk = 36

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

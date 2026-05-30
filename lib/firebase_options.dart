// ⚠️  AUTO-GENERATED FILE — DO NOT EDIT MANUALLY unless you know what you're doing.
//
// To regenerate properly:
//   1. Install FlutterFire CLI:        dart pub global activate flutterfire_cli
//   2. Log in to Firebase:             firebase login
//   3. Run in project root:            flutterfire configure --project=vext-vigilantmesh-57551
//
// That will overwrite this file with the correct values for your project.
//
// If you prefer to fill in values manually, go to:
//   Firebase Console → vext-vigilantmesh-57551 → Project Settings → Your apps → Android app
//   Copy each field from google-services.json into the placeholders below.
//
// IMPORTANT: Never commit real API keys to public repos.
//            Add lib/firebase_options.dart to .gitignore after filling in values.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'VEXT does not support web. Use Android target only.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'VEXT does not support iOS. Use Android target only.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'VEXT does not support macOS. Use Android target only.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Android options ───────────────────────────────────────────────────────
  // Get these values from Firebase Console → Project Settings → Android app
  // OR run: flutterfire configure --project=vext-vigilantmesh-57551

  static const FirebaseOptions android = FirebaseOptions(
    // From google-services.json → client[0].api_key[0].current_key
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',

    // Always: https://<project-id>.firebaseapp.com
    authDomain: 'vext-vigilantmesh-57551.firebaseapp.com',

    // From google-services.json → project_info.project_id
    projectId: 'vext-vigilantmesh-57551',

    // From google-services.json → project_info.storage_bucket
    storageBucket: 'vext-vigilantmesh-57551.firebasestorage.app',

    // From google-services.json → project_info.firebase_url (optional — for Realtime DB)
    // Leave empty string if you're only using Firestore.
    databaseURL: '',

    // From google-services.json → project_info.project_number
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',

    // From google-services.json → client[0].client_info.mobilesdk_app_id
    appId: 'REPLACE_WITH_YOUR_APP_ID',

    // From Firebase Console → Cloud Messaging → Server key (not the web key)
    // OR leave empty for now; FCM works without this in most setups
    measurementId: '',
  );
}

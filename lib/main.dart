import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_router.dart';
import 'core/app_theme.dart';
import 'firebase_options.dart';
import 'services/mesh_foreground_service.dart';

// ── FCM background message handler ────────────────────────────────────────────
//
// Must be a top-level function (not a class method or closure) — Flutter spawns
// a SEPARATE isolate for background messages, so it cannot capture any
// instance state from the main isolate.
//
// Firebase.initializeApp() MUST be called inside the handler because the
// background isolate has a fresh Dart VM with no prior Firebase state.
//
// For VEXT: the handleSOSAlert Cloud Function sends notification+data messages.
// Android automatically shows notification-type messages when the app is in
// background — this handler exists for completeness and future data-only
// messages (e.g. silent peer-key rotation).
//
// @pragma('vm:entry-point') prevents the Dart tree-shaker from removing this
// function in release builds (required by firebase_messaging).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] Background message received: '
      'id=${message.messageId} type=${message.data['type']}');
  // Notification-type messages are displayed automatically by the system.
  // No manual display logic needed here.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the FCM background message handler BEFORE Firebase.initializeApp().
  // firebase_messaging requires this to be set early so the plugin can wire it
  // up to the Android WorkManager/JobIntentService before the main isolate is
  // fully initialised.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Lock to portrait mode.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar — dark theme bleeds through.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialise Firebase before runApp.
  //
  // WHY try-catch instead of if (Firebase.apps.isEmpty):
  //   Firebase.apps is a Dart-side list populated only by Dart-level calls to
  //   initializeApp(). It is ALWAYS empty on a fresh cold start because the
  //   Google Services Gradle plugin initialises Firebase at the native Android
  //   layer BEFORE any Dart code runs. The isEmpty guard therefore always
  //   evaluates to true, always calls initializeApp(), and always hits the
  //   already-initialised native app — producing the [core/duplicate-app]
  //   exception. A try-catch is the correct FlutterFire production pattern.
  //
  //   On hot-restart the Dart isolate is torn down but the native layer is not,
  //   so the same situation arises — this catch handles that case too.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
    // duplicate-app: Firebase is already initialised at the native layer.
    // All Firebase services (Auth, Firestore, FCM) are fully available.
    // Safe to continue — no action needed.
  }

  // Request notification permission (Android 13+ / iOS).
  //
  // Android 13+ (API 33+) requires an explicit runtime permission grant for
  // POST_NOTIFICATIONS — declaring it in AndroidManifest.xml is NOT enough.
  // Without this grant, FCM push notifications (SOS alerts) are silently
  // dropped by the OS before reaching the app's notification channel.
  //
  // FirebaseMessaging.requestPermission() handles both platforms:
  //   Android 13+: triggers the POST_NOTIFICATIONS runtime dialog
  //   Android < 13: no-op (permission is implicitly granted)
  //   iOS:          triggers the standard iOS notification permission dialog
  //
  // We request at startup rather than on first SOS because the app should be
  // ready to RECEIVE alerts even before the user ever triggers one.
  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
  } catch (e) {
    // Permission request failure must never crash the app.
    debugPrint('[FCM] requestPermission failed: $e');
  }

  // Configure the Android foreground service BEFORE runApp.
  // This registers the notification channel and entry point with the plugin.
  // The service is NOT started here — BleStateNotifier calls start() when
  // BLE scanning begins (startIdle / startSession / startSos).
  //
  // Wrapped in try-catch: a foreground service configuration failure must NEVER
  // crash the app. The mesh will still function; it just won't survive screen-off
  // until the configuration issue is resolved.
  try {
    await MeshForegroundService.configure();
  } catch (e, st) {
    debugPrint('[FGService] configure() failed — app continues without '
        'foreground service.\nError: $e\n$st');
  }

  runApp(
    // ProviderScope is the Riverpod root container — wraps everything.
    const ProviderScope(
      child: VextApp(),
    ),
  );
}

class VextApp extends ConsumerWidget {
  const VextApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'VEXT VigilantMesh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}

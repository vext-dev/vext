import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_router.dart';
import 'core/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

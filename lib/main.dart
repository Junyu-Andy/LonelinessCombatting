import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_settings.dart';
import 'features/analytics/data/analytics_service.dart';
import 'features/auth/data/auth_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e, st) {
    // firebase_options.dart is still the placeholder — see SETUP_FIREBASE.md.
    // Launch anyway so the rest of the demo (theme, language) works.
    if (kDebugMode) {
      debugPrint('Firebase init skipped: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  runApp(
    MyApp(
      settings: AppSettings(
        locale: const Locale('zh'),
      ),
      authService: AuthService(available: firebaseReady),
      analytics: AnalyticsService(firebaseReady: firebaseReady),
    ),
  );
}

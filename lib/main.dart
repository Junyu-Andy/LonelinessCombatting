import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_settings.dart';
import 'core/llm/llm_gateway.dart';
import 'core/memory/cross_module_memory.dart';
import 'core/memory/memory_store.dart';
import 'core/safety/distress_detector.dart';
import 'core/safety/distress_state.dart';
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

  const detector = DistressDetector();
  final distressState = DistressState();
  final memory = MemoryStore(available: firebaseReady);
  final crossModuleMemory = CrossModuleMemoryService(
    memory: memory,
    firestoreAvailable: firebaseReady,
  );
  runApp(
    MyApp(
      settings: AppSettings(
        locale: const Locale('zh'),
      ),
      authService: AuthService(available: firebaseReady),
      analytics: AnalyticsService(firebaseReady: firebaseReady),
      llm: LlmGateway(detector: detector),
      memory: memory,
      distress: detector,
      distressState: distressState,
      crossModuleMemory: crossModuleMemory,
    ),
  );
}

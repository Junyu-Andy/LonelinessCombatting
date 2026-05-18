import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_settings.dart';
import 'core/agent_context/agent_context_service.dart';
import 'core/agent_context/shared_context_service.dart';
import 'core/agents/persona_resolver.dart';
import 'core/cross_referral/handoff_executor.dart';
import 'core/cross_referral/referral_routing_service.dart';
import 'core/fcm/fcm_service.dart';
import 'core/llm/llm_gateway.dart';
import 'core/memory/cross_module_memory.dart';
import 'core/memory/memory_store.dart';
import 'core/safety/distress_detector.dart';
import 'core/safety/distress_router.dart';
import 'core/safety/distress_state.dart';
import 'core/safety/safety_event_writer.dart';
import 'features/analytics/data/analytics_service.dart';
import 'features/auth/data/auth_service.dart';
import 'features/llm_features/data/llm_turn_features.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // B.11 — App Check.
    // Debug builds use the debug provider so local emulators and dev devices
    // aren't locked out.  Release builds use platform attestation:
    //   iOS  → DeviceCheck  (works on device from iOS 11+)
    //   Android → Play Integrity (supersedes SafetyNet)
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck,
      webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
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
  final distressRouter = DistressRouter(state: distressState);
  final safetyWriter = SafetyEventWriter(available: firebaseReady);
  final llmFeaturesRepo = LlmTurnFeaturesRepository(available: firebaseReady);
  final memory = MemoryStore(available: firebaseReady);
  final crossModuleMemory = CrossModuleMemoryService(
    memory: memory,
    firestoreAvailable: firebaseReady,
  );
  final agentContext = AgentContextService(available: firebaseReady);
  final sharedContext = SharedContextService(available: firebaseReady);
  final personaResolver = PersonaResolver(
    agentContext: agentContext,
    sharedContext: sharedContext,
  );
  final analytics = AnalyticsService(firebaseReady: firebaseReady);
  // Wire per-layer cross-referral telemetry into analytics so Phase A
  // can calibrate keyword-filter recall + LLM SURFACE/DEFER/SKIP rates.
  // The routing service has no AnalyticsService dependency by design;
  // the telemetry callback bridges the two.
  final referralRouting = ReferralRoutingService(
    sharedContext: sharedContext,
    telemetry: (phase, params) {
      analytics.logEvent('cross_referral_$phase', params);
    },
  );
  final handoffExecutor = HandoffExecutor(sharedContext: sharedContext);
  final fcm = FcmService(available: firebaseReady);

  runApp(
    MyApp(
      settings: AppSettings(
        locale: const Locale('zh'),
      ),
      authService: AuthService(available: firebaseReady),
      analytics: analytics,
      llm: LlmGateway(
        detector: detector,
        safetyWriter: safetyWriter,
        featuresRepo: llmFeaturesRepo,
      ),
      memory: memory,
      distress: detector,
      distressState: distressState,
      distressRouter: distressRouter,
      crossModuleMemory: crossModuleMemory,
      agentContext: agentContext,
      sharedContext: sharedContext,
      personaResolver: personaResolver,
      referralRouting: referralRouting,
      handoffExecutor: handoffExecutor,
      fcm: fcm,
    ),
  );
}

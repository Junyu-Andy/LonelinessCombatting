import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/agent_context/agent_context_service.dart';
import '../core/agent_context/shared_context_service.dart';
import '../core/agents/persona_resolver.dart';
import '../core/core_services_scope.dart';
import '../core/cross_referral/handoff_executor.dart';
import '../core/cross_referral/referral_routing_service.dart';
import '../core/llm/llm_gateway.dart';
import '../core/memory/cross_module_memory.dart';
import '../core/memory/memory_store.dart';
import '../core/safety/distress_detector.dart';
import '../core/safety/distress_router.dart';
import '../core/safety/distress_state.dart';
import '../core/safety/safety_overlay.dart';
import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/auth_service_scope.dart';
import '../features/auth/presentation/pages/auth_gate.dart';
import '../l10n/app_localizations.dart';
import 'app_settings.dart';
import 'app_settings_scope.dart';
import 'app_theme.dart';

class MyApp extends StatefulWidget {
  final AppSettings settings;
  final AuthService authService;
  final AnalyticsService analytics;
  final LlmGateway llm;
  final MemoryStore memory;
  final DistressDetector distress;
  final DistressState distressState;
  final DistressRouter distressRouter;
  final CrossModuleMemoryService crossModuleMemory;
  final AgentContextService agentContext;
  final SharedContextService sharedContext;
  final PersonaResolver personaResolver;
  final ReferralRoutingService referralRouting;
  final HandoffExecutor handoffExecutor;

  const MyApp({
    super.key,
    required this.settings,
    required this.authService,
    required this.analytics,
    required this.llm,
    required this.memory,
    required this.distress,
    required this.distressState,
    required this.distressRouter,
    required this.crossModuleMemory,
    required this.agentContext,
    required this.sharedContext,
    required this.personaResolver,
    required this.referralRouting,
    required this.handoffExecutor,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChange);
    _onSettingsChange();
    widget.analytics.startSession(platform: _currentPlatform());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChange);
    // Best-effort — flush a session_end on teardown.
    widget.analytics.endSession();
    super.dispose();
  }

  void _onSettingsChange() {
    setState(() {});
    widget.analytics.setEnvironment(
      locale: widget.settings.locale.languageCode,
      highContrast: widget.settings.highContrast,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.analytics.startSession(platform: _currentPlatform());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        widget.analytics.endSession();
        break;
    }
  }

  String _currentPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    return AnalyticsScope(
      analytics: widget.analytics,
      child: AuthServiceScope(
        authService: widget.authService,
        child: CoreServicesScope(
          llm: widget.llm,
          memory: widget.memory,
          distress: widget.distress,
          distressState: widget.distressState,
          distressRouter: widget.distressRouter,
          crossModuleMemory: widget.crossModuleMemory,
          agentContext: widget.agentContext,
          sharedContext: widget.sharedContext,
          personaResolver: widget.personaResolver,
          referralRouting: widget.referralRouting,
          handoffExecutor: widget.handoffExecutor,
          child: AppSettingsScope(
          settings: widget.settings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Companion Demo',
            theme: widget.settings.highContrast
                ? AppTheme.highContrast
                : AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: widget.settings.locale,
            builder: (context, child) {
              // P4.1: apply the user's elderly-friendly font scale by
              // overriding MediaQuery before anything paints text. This
              // affects every Text widget in the subtree without forcing
              // each widget to read settings.fontScale directly.
              final base = MediaQuery.of(context);
              final scaled = base.copyWith(
                textScaler: TextScaler.linear(
                  base.textScaler.scale(1.0) *
                      widget.settings.fontScale.multiplier,
                ),
              );
              return MediaQuery(
                data: scaled,
                child: SafetyOverlay(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: AuthGate(
              authService: widget.authService,
              analytics: widget.analytics,
            ),
          ),
          ),
        ),
      ),
    );
  }
}

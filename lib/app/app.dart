import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  const MyApp({
    super.key,
    required this.settings,
    required this.authService,
    required this.analytics,
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
            home: AuthGate(
              authService: widget.authService,
              analytics: widget.analytics,
            ),
          ),
        ),
      ),
    );
  }
}

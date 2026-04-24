import 'package:flutter/material.dart';

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

  const MyApp({
    super.key,
    required this.settings,
    required this.authService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AuthServiceScope(
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
          home: AuthGate(authService: widget.authService),
        ),
      ),
    );
  }
}

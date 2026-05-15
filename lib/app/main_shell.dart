import 'package:flutter/material.dart';

import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../l10n/app_localizations.dart';

/// Top-level shell. Phase 0 leaves only the Home surface; the Today /
/// My Story / Me tabs will be wired up in Phase 1. Settings still lives
/// in the AppBar gear so it's reachable from every screen.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  DateTime _tabEnteredAt = DateTime.now();
  AnalyticsService? _analytics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  @override
  void dispose() {
    _analytics?.logTabView(
      tab: 'dashboard',
      durationSeconds: DateTime.now().difference(_tabEnteredAt).inSeconds,
    );
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const SettingsPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        toolbarHeight: 76,
        actions: [
          IconButton(
            tooltip: l10n.settingsTab,
            icon: const Icon(Icons.settings_outlined, size: 28),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const HomePage(),
    );
  }
}

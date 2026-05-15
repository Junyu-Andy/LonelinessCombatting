import 'package:flutter/material.dart';

import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/data/navigation_telemetry.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/me/presentation/pages/me_page.dart';
import '../features/my_story/presentation/pages/my_story_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/today/presentation/pages/today_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_app_bar.dart';

enum AppTab { today, myStory, me, settings }

/// Top-level shell. Four bottom-nav tabs (Today / My Story / Me /
/// Settings) hosted inside an [IndexedStack] so per-tab scroll position
/// survives switches.
class MainShell extends StatefulWidget {
  /// The trigger that brought the user to the shell on this app
  /// session — propagated by main.dart so [NavigationTelemetry] can
  /// open a measurement window for the assessment protocol (P5.1).
  /// Defaults to 'cold_start' which records no nav_to_tab events.
  final String launchTrigger;
  final Map<String, dynamic>? notificationPayload;

  const MainShell({
    super.key,
    this.launchTrigger = 'cold_start',
    this.notificationPayload,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppTab _current = AppTab.today;
  DateTime _tabEnteredAt = DateTime.now();
  AnalyticsService? _analytics;
  NavigationTelemetry? _navTelemetry;

  static const _analyticsKeys = {
    AppTab.today: 'today',
    AppTab.myStory: 'my_story',
    AppTab.me: 'me',
    AppTab.settings: 'settings',
  };

  static const _navIntents = {
    AppTab.today: NavIntent.today,
    AppTab.myStory: NavIntent.myStory,
    AppTab.me: NavIntent.me,
    AppTab.settings: NavIntent.settings,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final analytics = AnalyticsScope.of(context);
    if (_analytics == analytics) return;
    _analytics = analytics;
    final telemetry = NavigationTelemetry(analytics: analytics);
    _navTelemetry = telemetry;
    telemetry.startNavigationSession(
      intent: NavigationTelemetry.inferIntent(
        trigger: widget.launchTrigger,
        notificationPayload: widget.notificationPayload,
      ),
      source: widget.launchTrigger,
    );
  }

  void _switchTab(int index) {
    final next = AppTab.values[index];
    if (next == _current) return;
    final now = DateTime.now();
    _analytics?.logTabView(
      tab: _analyticsKeys[_current]!,
      durationSeconds: now.difference(_tabEnteredAt).inSeconds,
    );
    _navTelemetry?.onTabChanged(_navIntents[next]!);
    setState(() {
      _current = next;
      _tabEnteredAt = now;
    });
  }

  @override
  void dispose() {
    _analytics?.logTabView(
      tab: _analyticsKeys[_current]!,
      durationSeconds: DateTime.now().difference(_tabEnteredAt).inSeconds,
    );
    _navTelemetry?.onSessionEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final titles = {
      AppTab.today: l10n.tabToday,
      AppTab.myStory: l10n.tabMyStory,
      AppTab.me: l10n.tabMe,
      AppTab.settings: l10n.settingsTab,
    };

    return Scaffold(
      appBar: AppAppBar(title: titles[_current]!),
      body: IndexedStack(
        index: _current.index,
        children: const [
          TodayPage(),
          MyStoryPage(),
          MePage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current.index,
        onDestinationSelected: _switchTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.tabToday,
            tooltip: l10n.tabToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.tabMyStory,
            tooltip: l10n.tabMyStory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.tabMe,
            tooltip: l10n.tabMe,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTab,
            tooltip: l10n.settingsTab,
          ),
        ],
      ),
    );
  }
}

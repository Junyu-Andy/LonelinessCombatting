import 'package:flutter/material.dart';

import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/data/navigation_telemetry.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/me/presentation/pages/me_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/talk/presentation/pages/talk_page.dart';
import '../features/today/presentation/pages/today_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_app_bar.dart';
import 'app_theme.dart';

/// Top-level shell.  Four bottom-nav tabs per Product Overview §3.2:
///
///   AppTab.today    → 睇今日 (Today)     · TodayPage
///   AppTab.myStory  → 搵人傾 (Talk)      · TalkPage   (3 agent rooms)
///   AppTab.me       → 做啲嘢 (Do)        · MePage     (tools)
///   AppTab.settings → 自己 (Self)        · SettingsPage (Progress / Profile /
///                                          Emergency / Display / Language /
///                                          Notifications / 今日休息 /
///                                          Boundaries / FAQ / Privacy /
///                                          Research)
///
/// The AppTab enum names are kept (myStory / me / settings) for
/// telemetry-backwards-compat — the analytics keys + NavIntent map
/// would break if renamed.  Internally each enum value now points at
/// the spec-correct surface.
enum AppTab { today, myStory, me, settings }

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

  // Analytics keys updated to the new IA labels so analysts read
  // "talk"/"do"/"self" instead of the legacy "my_story"/"me"/"settings".
  static const _analyticsKeys = {
    AppTab.today: 'today',
    AppTab.myStory: 'talk',
    AppTab.me: 'do',
    AppTab.settings: 'self',
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
      AppTab.today: l10n.tabToday,       // 睇今日
      AppTab.myStory: l10n.tabMyStory,   // 搵人傾
      AppTab.me: l10n.tabMe,             // 做啲嘢
      AppTab.settings: l10n.settingsTab, // 自己
    };

    return Scaffold(
      appBar: AppAppBar(title: titles[_current]!),
      body: IndexedStack(
        index: _current.index,
        children: const [
          TodayPage(),
          TalkPage(),     // ← was MyStoryPage; now 搵人傾 (3 agent rooms)
          MePage(),       // ← repurposed as 做啲嘢 (tools)
          SettingsPage(), // ← repurposed as 自己 (Progress + Profile + admin)
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [AppTheme.navTopShadow],
        ),
        child: NavigationBar(
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
            // 搵人傾 — door to the three agent rooms.
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.tabMyStory,
            tooltip: l10n.tabMyStory,
          ),
          NavigationDestination(
            // 做啲嘢 — tools (Action Loop / TE / Education / Social).
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: l10n.tabMe,
            tooltip: l10n.tabMe,
          ),
          NavigationDestination(
            // 自己 — Progress + Profile + Emergency + Settings sections.
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.settingsTab,
            tooltip: l10n.settingsTab,
          ),
        ],
        ),
      ),
    );
  }
}

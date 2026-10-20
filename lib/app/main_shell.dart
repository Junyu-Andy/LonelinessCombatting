import 'package:flutter/material.dart';

import '../core/feature_flags/remote_feature_flags.dart';
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
import 'home_tab_switcher.dart';

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

/// 1020l §一 (1): the switches that decide how the tabs are laid out
/// (1020 D page 1 / page 2 and the 做啲嘢 pictures, E the mood row, F the
/// 小欣 window).  The tabs are rebuilt when this changes after a re-read.
@visibleForTesting
String homeSwitchesKey(RemoteFeatureFlags f) => 'home_switches_'
    '${f.homeLayoutV2Enabled ? 1 : 0}'
    '${f.moodRowV2Enabled ? 1 : 0}'
    '${f.checkInChatV2Enabled ? 1 : 0}';

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
      // 1020 D (4): page 1's 「去搵人傾」 switches to the 搵人傾 tab.
      body: HomeTabSwitcher(
        goToTalk: () => _switchTab(AppTab.myStory.index),
        // 1020l §一 (1): the tabs read the home switches when they are
        // built.  After sign-in the App reads app_config/feature_flags
        // again (AuthGate) — usually after this shell is already up.  When
        // that read changes a home switch (the start-up read was refused
        // before sign-in, or timed out), the four tabs are rebuilt from
        // scratch so page 1 / page 2 follow the switches without killing
        // the App.  Same switches as before → same key → nothing rebuilt.
        child: ValueListenableBuilder<int>(
          valueListenable: RemoteFeatureFlags.reads,
          builder: (context, _, __) => IndexedStack(
            key: ValueKey<String>(
                homeSwitchesKey(RemoteFeatureFlags.current)),
            index: _current.index,
            children: const [
              TodayPage(),
              TalkPage(),     // ← was the My Story tab (deleted 1020o); now 搵人傾
              MePage(),       // ← repurposed as 做啲嘢 (tools)
              SettingsPage(), // ← repurposed as 自己 (Progress + Profile + admin)
            ],
          ),
        ),
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

import 'package:flutter/material.dart';

import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/me/presentation/pages/me_page.dart';
import '../features/my_story/presentation/pages/my_story_page.dart';
import '../features/today/presentation/pages/today_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_app_bar.dart';

enum AppTab { today, myStory, me }

/// Top-level shell. Three bottom-nav tabs (Today / My Story / Me) hosted
/// inside an [IndexedStack] so per-tab scroll position survives switches.
/// Settings is reached via the AppBar gear, not as a tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppTab _current = AppTab.today;
  DateTime _tabEnteredAt = DateTime.now();
  AnalyticsService? _analytics;

  static const _analyticsKeys = {
    AppTab.today: 'today',
    AppTab.myStory: 'my_story',
    AppTab.me: 'me',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  void _switchTab(int index) {
    final next = AppTab.values[index];
    if (next == _current) return;
    final now = DateTime.now();
    _analytics?.logTabView(
      tab: _analyticsKeys[_current]!,
      durationSeconds: now.difference(_tabEnteredAt).inSeconds,
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final titles = {
      AppTab.today: l10n.tabToday,
      AppTab.myStory: l10n.tabMyStory,
      AppTab.me: l10n.tabMe,
    };

    return Scaffold(
      appBar: AppAppBar(title: titles[_current]!),
      body: IndexedStack(
        index: _current.index,
        children: const [
          TodayPage(),
          MyStoryPage(),
          MePage(),
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
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../features/action_support/presentation/pages/action_support_page.dart';
import '../features/analytics/data/analytics_service.dart';
import '../features/analytics/presentation/analytics_scope.dart';
import '../features/chat/presentation/pages/chat_landing_page.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/personalization/presentation/pages/personalization_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../l10n/app_localizations.dart';

/// Bottom-nav shell. Order: Home / Activities / Chat / About-You.
/// Settings sits in the AppBar gear so it's reachable from every tab
/// without burning a destination slot.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  DateTime _tabEnteredAt = DateTime.now();
  AnalyticsService? _analytics;

  static const _tabKeys = ['home', 'activities', 'chat', 'about_you'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  void _switchTab(int index) {
    final now = DateTime.now();
    _analytics?.logTabView(
      tab: _tabKeys[_currentIndex],
      durationSeconds: now.difference(_tabEnteredAt).inSeconds,
    );
    setState(() {
      _currentIndex = index;
      _tabEnteredAt = now;
    });
  }

  @override
  void dispose() {
    _analytics?.logTabView(
      tab: _tabKeys[_currentIndex],
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

    final pages = const [
      HomePage(),
      ActionSupportPage(),
      ChatLandingPage(),
      PersonalizationPage(),
    ];

    final titles = [
      l10n.homeTab,
      l10n.actionTab,
      l10n.chatTab,
      l10n.contextTab,
    ];

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            titles[_currentIndex],
            key: ValueKey(_currentIndex),
          ),
        ),
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _switchTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.homeTab,
            tooltip: l10n.homeTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.spa_outlined),
            selectedIcon: const Icon(Icons.spa),
            label: l10n.actionTab,
            tooltip: l10n.actionTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.chatTab,
            tooltip: l10n.chatTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_pin_circle_outlined),
            selectedIcon: const Icon(Icons.person_pin_circle),
            label: l10n.contextTab,
            tooltip: l10n.contextTab,
          ),
        ],
      ),
    );
  }
}

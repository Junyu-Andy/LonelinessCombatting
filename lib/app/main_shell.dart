import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/context/presentation/pages/context_page.dart';
import '../features/action_support/presentation/pages/action_support_page.dart';
import '../features/follow_up/presentation/pages/follow_up_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final pages = const [
      HomePage(),
      ContextPage(),
      ActionSupportPage(),
      FollowUpPage(),
      SettingsPage(),
    ];

    final titles = [
      l10n.homeTab,
      l10n.contextTab,
      l10n.actionTab,
      l10n.followUpTab,
      l10n.settingsTab,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
        toolbarHeight: 76,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.homeTab,
            tooltip: l10n.homeTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: l10n.contextTab,
            tooltip: l10n.contextTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.lightbulb_outline),
            selectedIcon: const Icon(Icons.lightbulb),
            label: l10n.actionTab,
            tooltip: l10n.actionTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_note_outlined),
            selectedIcon: const Icon(Icons.event_note),
            label: l10n.followUpTab,
            tooltip: l10n.followUpTab,
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

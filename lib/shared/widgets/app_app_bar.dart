import 'package:flutter/material.dart';

import '../../features/settings/presentation/pages/settings_page.dart';
import '../../l10n/app_localizations.dart';

/// Unified AppBar used by every top-level tab. Exposes the global
/// Settings gear in the trailing slot so Settings is always one tap
/// away from any tab (per spec: Settings is *not* a bottom-nav slot).
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const AppAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
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
        child: Text(title, key: ValueKey(title)),
      ),
      toolbarHeight: 76,
      actions: [
        IconButton(
          tooltip: l10n.settingsTab,
          icon: const Icon(Icons.settings_outlined, size: 28),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

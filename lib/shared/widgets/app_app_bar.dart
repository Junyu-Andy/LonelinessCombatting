import 'package:flutter/material.dart';

/// Unified AppBar used by every top-level tab. Title fades + slides
/// between tab switches so the AppBar feels alive without the user
/// losing context. Settings has its own bottom-nav tab — no gear icon
/// in the trailing slot.
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const AppAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
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
    );
  }
}

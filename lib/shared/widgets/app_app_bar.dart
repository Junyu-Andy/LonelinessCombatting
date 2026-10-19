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
        // 10/19: keep both titles at the start edge while they cross-fade.
        // The default layout centres them in a box as wide as the longer
        // one, so 「自己」 appeared centred and then jumped left once the old
        // title was gone.
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, if (current != null) current],
        ),
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

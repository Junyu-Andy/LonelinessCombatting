/// 1020 D (4) — lets page 1's 「去搵人傾」 button switch the bottom tab to
/// page 2 「搵人傾」 (the same as tapping the tab, telemetry included).
/// [MainShell] provides it; outside the shell (tests) it is absent and the
/// button does nothing.
library;

import 'package:flutter/widgets.dart';

class HomeTabSwitcher extends InheritedWidget {
  const HomeTabSwitcher({
    super.key,
    required this.goToTalk,
    required super.child,
  });

  /// Switch to 搵人傾.
  final VoidCallback goToTalk;

  static HomeTabSwitcher? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeTabSwitcher>();

  @override
  bool updateShouldNotify(HomeTabSwitcher oldWidget) => false;
}

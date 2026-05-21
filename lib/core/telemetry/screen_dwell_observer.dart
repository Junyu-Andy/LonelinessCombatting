/// NavigatorObserver that drives [ScreenDwellTracker] on route changes.
///
/// Routes without a `settings.name` are skipped — anonymous modals
/// don't produce dwell metrics.

import 'package:flutter/widgets.dart';

import 'screen_dwell_tracker.dart';

class ScreenDwellObserver extends NavigatorObserver {
  String? _nameOf(Route<dynamic>? route) => route?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final to = _nameOf(route);
    final from = _nameOf(previousRoute);
    if (from != null) {
      ScreenDwellTracker.instance.exit(from, exitReason: 'forward_nav', toScreenName: to);
    }
    if (to != null) {
      ScreenDwellTracker.instance.enter(to, fromScreenName: from);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final popped = _nameOf(route);
    final back = _nameOf(previousRoute);
    if (popped != null) {
      ScreenDwellTracker.instance
          .exit(popped, exitReason: 'back_nav', toScreenName: back);
    }
    if (back != null) {
      ScreenDwellTracker.instance.enter(back, fromScreenName: popped);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final from = _nameOf(oldRoute);
    final to = _nameOf(newRoute);
    if (from != null) {
      ScreenDwellTracker.instance
          .exit(from, exitReason: 'replace_nav', toScreenName: to);
    }
    if (to != null) {
      ScreenDwellTracker.instance.enter(to, fromScreenName: from);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    if (name != null) {
      ScreenDwellTracker.instance.exit(name, exitReason: 'remove');
    }
  }
}

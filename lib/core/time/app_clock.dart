/// Simulated clock for schedule testing (2026-09-23).
///
/// Only the *scheduling* decisions read this clock: which surveys the home
/// page offers (Weekly PR window, Week 2 / Week 4 batteries, first-week
/// nudge, daily mood prompt).  Firestore timestamps, analytics timestamps,
/// session durations and the Cloud Function crons always use real time.
///
/// Set from 設定 → 測試員工具 → 日程模擬 (requires the tester PIN).  Held in
/// memory only: an app restart returns to real time, so a forgotten
/// simulation can never leak into a participant session.
library;

import 'package:flutter/foundation.dart';

class AppClock extends ChangeNotifier {
  AppClock._();
  static final AppClock instance = AppClock._();

  Duration _offset = Duration.zero;

  bool get isSimulated => _offset != Duration.zero;

  /// Current (possibly simulated) wall-clock time.  Keeps ticking.
  static DateTime now() => DateTime.now().add(instance._offset);

  /// Jump so that "now" reads [target]; time keeps moving from there.
  void simulate(DateTime target) {
    _offset = target.difference(DateTime.now());
    notifyListeners();
  }

  void clear() {
    if (_offset == Duration.zero) return;
    _offset = Duration.zero;
    notifyListeners();
  }
}

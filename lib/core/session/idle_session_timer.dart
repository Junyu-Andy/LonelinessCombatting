/// B.6 — 60-second idle session-end timer with mobile-lifecycle awareness
/// (Sprint 2.3, sprint-plan risk R9).
///
/// Design points the sprint plan flags:
///   - When the app goes to background (paused/inactive/hidden), the timer
///     MUST pause so a locked phone for 5 minutes doesn't fire a phantom
///     session-end.
///   - When the app foregrounds again, the timer restarts from zero — the
///     user has had the screen off and any "idle" semantics should reset.
///   - Tapping or speaking (any [bumpActivity] call) resets the countdown.
///
/// Usage:
/// ```dart
/// final timer = IdleSessionTimer(
///   idleDuration: const Duration(seconds: 60),
///   onIdle: () => _endSession('idle_60s'),
/// );
/// timer.start();          // when session begins
/// timer.bumpActivity();   // on every user turn / tap
/// timer.dispose();        // when session ends or page disposed
/// ```
///
/// Tested via the `idle_timer_test.dart` harness using an injected clock.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

class IdleSessionTimer with WidgetsBindingObserver {
  IdleSessionTimer({
    required this.idleDuration,
    required this.onIdle,
    Duration Function()? now,
  }) : _now = now ?? _wallClock;

  final Duration idleDuration;
  final void Function() onIdle;
  final Duration Function() _now;

  static Duration _wallClock() =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  Duration? _backgroundedAt;

  /// Whether [onIdle] has already fired for this start cycle.
  bool _firedThisSession = false;

  /// Start the timer.  Safe to call repeatedly — re-invoking restarts.
  void start() {
    if (_started) {
      _restartCountdown();
      return;
    }
    _started = true;
    _firedThisSession = false;
    WidgetsBinding.instance.addObserver(this);
    _restartCountdown();
  }

  /// Called by the page on any user activity (typing a turn, tapping a
  /// button, voice input).  Resets the countdown if foregrounded; no-op
  /// when backgrounded so a stray background timer can't reset state.
  void bumpActivity() {
    if (!_started || !_foreground) return;
    _restartCountdown();
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  void _restartCountdown() {
    _timer?.cancel();
    _timer = Timer(idleDuration, _fire);
  }

  void _fire() {
    if (_firedThisSession) return;
    if (!_foreground) return; // belt-and-braces: never fire from background
    _firedThisSession = true;
    onIdle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        break;
    }

    if (wasForeground && !_foreground) {
      // Going to background: pause the timer.
      _backgroundedAt = _now();
      _timer?.cancel();
      _timer = null;
    } else if (!wasForeground && _foreground) {
      // Coming back to foreground: reset countdown from zero.
      // (Spec: don't continue the pre-background countdown — the screen
      // was off and any 60s idle assumption is invalid.)
      _backgroundedAt = null;
      if (_started && !_firedThisSession) _restartCountdown();
    }
  }

  // -- testing-only hooks ----------------------------------------------------

  @visibleForTesting
  bool get isForegroundForTest => _foreground;

  @visibleForTesting
  bool get hasArmedTimerForTest => _timer != null;
}

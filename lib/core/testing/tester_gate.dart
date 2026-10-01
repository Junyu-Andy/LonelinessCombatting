/// Tester-tools unlock (2026-09-23).
///
/// Tester tools (survey previews, schedule simulator, test pushes, data
/// reset, the tester-account switch, and the direct survey entries) are
/// hidden from everyone — debug builds and `isTester` accounts included —
/// until someone enters the PIN compiled into the build:
///
///     flutter run --dart-define=TESTER_PIN=246810
///
/// A build without `TESTER_PIN` cannot be unlocked at all, which is the
/// safe default for participant builds.  Unlock lasts for the app process
/// only; killing the app locks it again and clears any simulated clock.
/// Five wrong attempts lock the dialog for the rest of the process.
///
/// Entry point: tap the version line on 設定 → 關於同支援 seven times.
library;

import 'package:flutter/foundation.dart';

import '../time/app_clock.dart';

class TesterGate {
  TesterGate._();

  static const String _pin = String.fromEnvironment('TESTER_PIN');
  static const int maxAttempts = 5;

  static final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);
  static int _failures = 0;

  /// False when the build carries no PIN — the dialog explains how to add one.
  static bool get isConfigured => _pin.isNotEmpty;
  static bool get isLockedOut => _failures >= maxAttempts;
  static int get attemptsLeft => maxAttempts - _failures;

  /// Returns true and unlocks when [candidate] matches the build PIN.
  static bool tryUnlock(String candidate) {
    if (!isConfigured || isLockedOut) return false;
    if (candidate.trim() == _pin) {
      _failures = 0;
      unlocked.value = true;
      return true;
    }
    _failures++;
    return false;
  }

  static void lock() {
    unlocked.value = false;
    AppClock.instance.clear();
  }

  @visibleForTesting
  static void resetForTest() {
    _failures = 0;
    unlocked.value = false;
  }

  @visibleForTesting
  static void forceUnlockForTest() => unlocked.value = true;
}

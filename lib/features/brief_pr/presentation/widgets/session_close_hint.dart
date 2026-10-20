/// T46 (C16) — "already explained" marker for the S9 close button's
/// first-use note.
///
/// T25 showed the note the first time the button appeared in each process,
/// so every App start showed it again.  T46 keeps the marker on the device
/// with `shared_preferences` (the same store T37 uses for the display
/// settings), so one phone sees the note once.  Same in both arms; the
/// wording is untouched.
///
/// The marker is a device setting, not research data: it is not written to
/// Firestore and is not restored from the server.  Uninstalling the App
/// clears it (the note shows once more after a reinstall).
///
/// [restore] runs once in `main()` before the first frame.  If the store
/// cannot be read the marker falls back to T25's once-per-process
/// behaviour; it never throws and never blocks the UI.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionCloseHint {
  SessionCloseHint._();

  /// Key in the device store (bool; `true` = the note has been shown).
  static const String key = 'session.closeHintShown';

  /// 1020d 8 (3) — the 「離開」 note (`leaveButtonV2Enabled`) has its own
  /// marker: shown once per phone even when the old note was.
  static const String leaveKey = 'session.leaveHintShown';

  static SharedPreferences? _store;
  static bool _shown = false;
  static bool _leaveShown = false;

  /// Whether the note has already been shown (on this phone, or — when the
  /// store is unavailable — in this process).
  static bool get alreadyShown => _shown;

  /// Read the marker from the device.  Never throws: an unreadable store
  /// leaves [_store] null and [alreadyShown] false, i.e. T25 behaviour.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bind(prefs);
    } catch (e) {
      if (kDebugMode) debugPrint('[SessionCloseHint] restore failed: $e');
      _store = null;
      _shown = false;
    }
  }

  /// The pure part of [restore]: take a store (null = none available) and
  /// read the marker from it.
  static void bind(SharedPreferences? prefs) {
    _store = prefs;
    try {
      _shown = prefs?.getBool(key) ?? false;
    } catch (_) {
      _shown = false;
    }
    try {
      _leaveShown = prefs?.getBool(leaveKey) ?? false;
    } catch (_) {
      _leaveShown = false;
    }
  }

  /// Called when the close button is about to appear.  Returns `true`
  /// exactly once per phone (per process when the store is unavailable)
  /// and records the marker; every later call returns `false`.
  static bool claimFirstUse() {
    if (_shown) return false;
    _shown = true;
    final store = _store;
    if (store == null) return true;
    try {
      store.setBool(key, true).catchError((Object e) {
        if (kDebugMode) debugPrint('[SessionCloseHint] persist failed: $e');
        return false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SessionCloseHint] persist failed: $e');
    }
    return true;
  }

  /// [claimFirstUse] for the 「離開」 note (`leaveButtonV2Enabled`).
  static bool claimLeaveFirstUse() {
    if (_leaveShown) return false;
    _leaveShown = true;
    final store = _store;
    if (store == null) return true;
    try {
      store.setBool(leaveKey, true).catchError((Object e) {
        if (kDebugMode) debugPrint('[SessionCloseHint] persist failed: $e');
        return false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SessionCloseHint] persist failed: $e');
    }
    return true;
  }

  /// Forget the marker in memory and in the given store (tests only).
  @visibleForTesting
  static void resetForTest({SharedPreferences? store}) {
    _store = store;
    _shown = false;
    _leaveShown = false;
  }
}

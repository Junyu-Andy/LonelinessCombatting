/// Phase B-only runtime parameters (T18, decision 0027).
///
/// Every key here belongs to Phase B only.  Read from the Firestore
/// document `app_config/phase_b` (clients read, nobody writes from the App;
/// the research team edits it from the console).  The Cloud Functions read
/// the same document (functions/djg_w2.js `readConfig`).  A missing
/// document, a failed read or a bad value keeps the default below; the
/// switch is ON only when its field is literally `true`.
///
///   - [djgW2InAppEnabled]   — W2 DJG in the App (6 items).  Default OFF.
///                             The App also requires a Phase B build
///                             (`--dart-define=PHASE_B=true`); see
///                             [DjgW2Gate].  T21 will move the phase test
///                             to the participant's study-phase field.
///   - [djgW2DayOffset]      — first day of the window (W0 = day 1).  14.
///   - [djgW2WindowDays]     — window length in days (14–20).  7.
///   - [djgW2PushHour]       — HK hour of the day-14 push (server).  10.
///   - [djgW2ReminderHours]  — reminder this long after the push if not
///                             submitted (server).  24.
///
/// Call [PhaseBConfig.load] once at startup; read via [current].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PhaseBConfig {
  const PhaseBConfig({
    this.djgW2InAppEnabled = false,
    this.djgW2DayOffset = 14,
    this.djgW2WindowDays = 7,
    this.djgW2PushHour = 10,
    this.djgW2ReminderHours = 24,
  });

  final bool djgW2InAppEnabled;
  final int djgW2DayOffset;
  final int djgW2WindowDays;
  final int djgW2PushHour;
  final int djgW2ReminderHours;

  static PhaseBConfig _current = const PhaseBConfig();

  /// The active configuration (defaults until [load] reads the document).
  static PhaseBConfig get current => _current;

  /// Test / tooling hook.
  @visibleForTesting
  static set current(PhaseBConfig value) => _current = value;

  /// Firestore document holding the Phase B keys.  Read-only for clients.
  static const String remotePath = 'app_config/phase_b';

  /// Read the document.  Never throws; on any failure the defaults (switch
  /// off) stay in force.
  static Future<PhaseBConfig> load({bool available = true}) async {
    if (!available) return _current = const PhaseBConfig();
    try {
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      _current = fromMap(snap.data() ?? const {});
    } catch (e) {
      if (kDebugMode) debugPrint('[PhaseBConfig] load failed: $e');
      _current = const PhaseBConfig();
    }
    return _current;
  }

  /// Pure parse used by [load] and tests.  Same rules as the server.
  static PhaseBConfig fromMap(Map<String, dynamic> map) {
    const d = PhaseBConfig();
    int n(String k, int def, int min) {
      final v = map[k];
      return v is num && v.isFinite && v >= min ? v.floor() : def;
    }

    return PhaseBConfig(
      djgW2InAppEnabled: map['djgW2InAppEnabled'] == true,
      djgW2DayOffset: n('djgW2DayOffset', d.djgW2DayOffset, 1),
      djgW2WindowDays: n('djgW2WindowDays', d.djgW2WindowDays, 1),
      djgW2PushHour: n('djgW2PushHour', d.djgW2PushHour, 0),
      djgW2ReminderHours: n('djgW2ReminderHours', d.djgW2ReminderHours, 1),
    );
  }
}

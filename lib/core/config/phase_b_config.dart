/// Phase B-only runtime parameters (T18, decision 0027; T25 session /
/// Brief PR v2).
///
/// Every key here belongs to Phase B (and the pilot, which runs the same
/// PHASE_B build).  Read from the Firestore document `app_config/phase_b`
/// (clients read, nobody writes from the App; the research team edits it
/// from the console).  The Cloud Functions read the same document
/// (functions/djg_w2.js `readConfig`).  A missing document, a failed read
/// or a bad value keeps the default below; a switch is ON only when its
/// field is literally `true`.
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
/// T25 (registry C14 / C16) — session definition and Brief PR v2.  All
/// behind [sessionBriefPrV2Enabled]; with it OFF every chat page behaves
/// exactly as before (10-minute idle, popup Brief PR on page exit, anchor
/// rule).  The other keys only matter while the switch is ON:
///
///   - [sessionBriefPrV2Enabled]           — master switch.  Default OFF.
///   - [sessionIdleTimeoutMinV2]           — a session ends after this many
///                                           minutes without a new message
///                                           (`endReason = timeout`).  30.
///   - [briefPrDailyCapPerAgent]           — Brief PR invitations per
///                                           companion per local day.  1.
///   - [briefPrCatchUpExpiryHours]         — an invitation expires this
///                                           long after the session's last
///                                           complete reply.  2.
///   - [freeChatValidMinUserMessages]      — free chat (Tung Tung, Hybrid
///                                           reflective dialogue, Ah Jan /
///                                           Ah Bak free chat) is a valid
///                                           session once this many user
///                                           messages each got a reply.  3.
///   - [hybridCheckInValidRequiresMood]    — Hybrid check-in: the mood must
///                                           be recorded.  true.
///   - [hybridCheckInValidMinUserMessages] — Hybrid check-in: this many
///                                           replied user messages.  1.
///   - [hybridReminiscenceValidRequiresSave] — Hybrid reminiscence: the
///                                           weekly summary must be saved
///                                           via 儲存.  true.
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
    this.sessionBriefPrV2Enabled = false,
    this.sessionIdleTimeoutMinV2 = 30,
    this.briefPrDailyCapPerAgent = 1,
    this.briefPrCatchUpExpiryHours = 2,
    this.freeChatValidMinUserMessages = 3,
    this.hybridCheckInValidRequiresMood = true,
    this.hybridCheckInValidMinUserMessages = 1,
    this.hybridReminiscenceValidRequiresSave = true,
  });

  final bool djgW2InAppEnabled;
  final int djgW2DayOffset;
  final int djgW2WindowDays;
  final int djgW2PushHour;
  final int djgW2ReminderHours;

  // T25 — session definition and Brief PR v2 (see the library comment).
  final bool sessionBriefPrV2Enabled;
  final int sessionIdleTimeoutMinV2;
  final int briefPrDailyCapPerAgent;
  final int briefPrCatchUpExpiryHours;
  final int freeChatValidMinUserMessages;
  final bool hybridCheckInValidRequiresMood;
  final int hybridCheckInValidMinUserMessages;
  final bool hybridReminiscenceValidRequiresSave;

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

    bool b(String k, bool def) => map[k] is bool ? map[k] as bool : def;

    return PhaseBConfig(
      djgW2InAppEnabled: map['djgW2InAppEnabled'] == true,
      djgW2DayOffset: n('djgW2DayOffset', d.djgW2DayOffset, 1),
      djgW2WindowDays: n('djgW2WindowDays', d.djgW2WindowDays, 1),
      djgW2PushHour: n('djgW2PushHour', d.djgW2PushHour, 0),
      djgW2ReminderHours: n('djgW2ReminderHours', d.djgW2ReminderHours, 1),
      // T25 — the switch is on only when literally `true`.
      sessionBriefPrV2Enabled: map['sessionBriefPrV2Enabled'] == true,
      sessionIdleTimeoutMinV2:
          n('sessionIdleTimeoutMinV2', d.sessionIdleTimeoutMinV2, 1),
      briefPrDailyCapPerAgent:
          n('briefPrDailyCapPerAgent', d.briefPrDailyCapPerAgent, 0),
      briefPrCatchUpExpiryHours:
          n('briefPrCatchUpExpiryHours', d.briefPrCatchUpExpiryHours, 1),
      freeChatValidMinUserMessages:
          n('freeChatValidMinUserMessages', d.freeChatValidMinUserMessages, 1),
      hybridCheckInValidRequiresMood: b(
          'hybridCheckInValidRequiresMood', d.hybridCheckInValidRequiresMood),
      hybridCheckInValidMinUserMessages: n('hybridCheckInValidMinUserMessages',
          d.hybridCheckInValidMinUserMessages, 0),
      hybridReminiscenceValidRequiresSave: b(
          'hybridReminiscenceValidRequiresSave',
          d.hybridReminiscenceValidRequiresSave),
    );
  }
}

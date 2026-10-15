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
///                                           via 儲存.  **false** since
///                                           dev-tasks-1014e §2.7 (10/15):
///                                           like free chat, ≥ 3 replied
///                                           user messages count; 儲存 is
///                                           no longer required.
///
/// T24 (registry C15 / C17) — study weeks and the weekly questionnaire
/// bundle.  All behind [weeklyScheduleV2Enabled]; with it OFF the Sunday
/// calendar-week window and T18's day-14 DJG stay exactly as before.  The
/// server reads the same keys (functions/weekly_schedule.js).
///
///   - [weeklyScheduleV2Enabled]     — master switch.  Default OFF.
///   - [weeklyBundleDays]            — study days of the W1–W4 pushes
///                                     (W0 = day 0).  [7, 14, 21, 26].
///   - [weeklyWindowDays]            — days to answer after the push
///                                     (W1–W3, W5–W7).  3.
///   - [week4CloseDay]               — W4 closes at the end of this study
///                                     day (or the W4 visit day, later).  29.
///   - [djgWeeks]                    — bundles that start with DJG-ES.
///                                     [1, 2, 3].
///   - [pgicOnlyDays]                — PGIC-only pushes (W5–W7).
///                                     [35, 42, 49].
///   - [weeklyPushHour]              — HK hour of the push.  20 (today's
///                                     Sunday weekly reminder hour).
///   - [socialContactProbeEnabled]   — 4th part, S12.  Default OFF.
///   - [pilotBundleDays]             — pilot (cohort `pilot`) pushes, W1–W4.
///                                     [1, 3, 5, 7].
///   - [pilotWindowDays]             — pilot answer window.  1.
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
    this.hybridReminiscenceValidRequiresSave = false,
    this.weeklyScheduleV2Enabled = false,
    this.weeklyBundleDays = const [7, 14, 21, 26],
    this.weeklyWindowDays = 3,
    this.week4CloseDay = 29,
    this.djgWeeks = const [1, 2, 3],
    this.pgicOnlyDays = const [35, 42, 49],
    this.weeklyPushHour = 20,
    this.socialContactProbeEnabled = false,
    this.pilotBundleDays = const [1, 3, 5, 7],
    this.pilotWindowDays = 1,
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

  // T24 — study weeks and the weekly bundle (see the library comment).
  final bool weeklyScheduleV2Enabled;
  final List<int> weeklyBundleDays;
  final int weeklyWindowDays;
  final int week4CloseDay;
  final List<int> djgWeeks;
  final List<int> pgicOnlyDays;
  final int weeklyPushHour;
  final bool socialContactProbeEnabled;
  final List<int> pilotBundleDays;
  final int pilotWindowDays;

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

    // T24: a strictly increasing list of whole numbers >= min, else def
    // (same rule as functions/weekly_schedule.js dayList).
    List<int> days(String k, List<int> def, int min) {
      final v = map[k];
      if (v is! List || v.isEmpty) return def;
      final out = <int>[];
      for (final x in v) {
        if (x is! num || !x.isFinite || x < min) return def;
        final n = x.floor();
        if (out.isNotEmpty && n <= out.last) return def;
        out.add(n);
      }
      return out;
    }

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
      // T24 — switches on only when literally `true`.
      weeklyScheduleV2Enabled: map['weeklyScheduleV2Enabled'] == true,
      weeklyBundleDays: days('weeklyBundleDays', d.weeklyBundleDays, 1),
      weeklyWindowDays: n('weeklyWindowDays', d.weeklyWindowDays, 1),
      week4CloseDay: n('week4CloseDay', d.week4CloseDay, 1),
      djgWeeks: days('djgWeeks', d.djgWeeks, 1),
      pgicOnlyDays: days('pgicOnlyDays', d.pgicOnlyDays, 1),
      weeklyPushHour: n('weeklyPushHour', d.weeklyPushHour, 0) % 24,
      socialContactProbeEnabled: map['socialContactProbeEnabled'] == true,
      pilotBundleDays: days('pilotBundleDays', d.pilotBundleDays, 0),
      pilotWindowDays: n('pilotWindowDays', d.pilotWindowDays, 1),
    );
  }
}

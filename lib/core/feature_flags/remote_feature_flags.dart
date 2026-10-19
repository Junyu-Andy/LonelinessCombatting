/// Runtime feature flags read from Firestore (decision 0019, SPEC:C18).
///
/// Unlike [FeatureFlags] (compile-time dart-defines), these live in the
/// `app_config/feature_flags` document so the research team can switch
/// them from the console without a new build, and the Cloud Functions
/// read the same document (functions/feature_flags.js) — turning a flag
/// off closes both the app entry point and the server endpoint.
///
/// Every flag is OFF unless its field is literally `true`.  A missing
/// document, a failed read or any other value keeps it off.
///
///   - [webSearchEnabled]      — Tung Tung "搜一搜" (Hybrid arm only).
///   - [voiceInputEnabled]     — mic button on every input page, both
///                               arms.  **Important feature: switch back
///                               on once HREC approves the STT amendment.**
///   - [searchOffReplyEnabled] — while search is off, Tung Tung answers
///                               search-type questions with one fixed
///                               line ([TungTungSearchIntent]).  The line
///                               is a placeholder until the research team
///                               signs it off.
///   - [enrollmentGateEnabled] — T21: an account that is not registered
///                               (no cohort) and is not a tester sees only
///                               the waiting page S8; the server refuses
///                               its LLM calls and research-data writes.
///   - [memoryLayersNoticeEnabled] — T31 (decision 0035): the S7 notice
///                               about shared / private memory at the top
///                               of 「我記得嘅嘢」.  Switch on together with
///                               `meta/memory_config.layersEnabled`.
///   - [replyFeedbackEnabled]  — 10/14 lead's decision: in a `PHASE_B=true`
///                               build the 👍/👎 reply feedback
///                               ([ThumbsFeedback]) is hidden in both arms
///                               unless this is true (it existed only on
///                               Hybrid chat pages, an unregistered
///                               between-arm difference; Phase B does not
///                               collect single-reply feedback).  Phase A
///                               builds are unaffected.
///   - [week1NudgeEnabled]     — same decision: the Phase A first-week
///                               「你仲未同 X 傾過」 home banner
///                               ([Week1NudgeBanner], enrolment days 3 and
///                               6) is hidden in a `PHASE_B=true` build
///                               unless this is true.
///   - [onboardingAfterEnrollmentFix] — T37: 「介紹三個夥伴」 runs until the
///                               onboarding-completed marker
///                               (`users/{uid}.onboardingCompletedAt`) is
///                               set, instead of "until a pairing exists" —
///                               the researcher's registration writes the
///                               pairing too, so register-first skipped the
///                               slides.  Also logs a pairing change
///                               (`events` row `ah_jan_ah_bak_changed`).
///   - [assessorViewEnabled]   — T30: a `blinded` account (the W4 outcome
///                               assessors) opens the assessor view only —
///                               W4 due list and paper DJG-ES entry — before
///                               the enrolment gate and consent; off, the
///                               account sees the participant App as before.
///                               The server's callables check the same
///                               flag (functions/assessor.js).
///   - [outcomeCompletionSummaryEnabled] — T30: the dashboard shows the
///                               `unblinded` role pooled completion rates
///                               per outcome instrument per timepoint (all
///                               participants together, hidden under n < 5).
///   - [usageEventsEnabled]    — T40 (registry C23): write a usage event
///                               (`users/{uid}/usage_events`) when the App
///                               comes to the foreground and goes to the
///                               background, for an enrolled account only;
///                               both arms, nothing visible.  Off = no row.
///   - [opsDashboardEnabled]   — T39 (registry C19): the operations
///                               dashboard (per person per day, follow-up
///                               stage, CSV) for the `unblinded` role; the
///                               server callables check the same flag.
///   - [researcherIntakeEnabled] — T47: the researcher records the five
///                               intake answers at the W0 visit
///                               (`recordResearcherIntake`); the elder's App
///                               no longer shows an intake questionnaire.
///                               Off = the elder answers the short five-
///                               question page.  Both arms identical.
///   - [testerArmSwitchEnabled] — a tester account (`isTester`) may switch
///                               its own arm in 測試員工具 (`setTesterArm`,
///                               functions/tester_arm.js; the server checks
///                               the same flag).  Participants unaffected.
///   - [s1aEventLogEnabled]    — T49c: each time Tung Tung shows the fixed
///                               search-off line S1a ([TungTungSearchIntent])
///                               one `users/{uid}/events` row
///                               `s1a_fixed_reply` (agentId, sessionId, arm,
///                               matchedVersion, clientTime — never the
///                               elder's words or the matched keyword).
///                               Both arms identical, nothing visible.
///   - [homeMoodOpensCheckInEnabled] — 10/19 (Junyu): the first mood pick
///                               of the day on the home pad opens the
///                               check-in page itself (Hybrid: Siu Yan,
///                               rule arm: the form) with that face chosen,
///                               instead of the 5-second snackbar.  Both
///                               arms; the pick is still one daily_mood row.
///   - [suggestionsUseProfileEnabled] — 10/19 (Junyu): 今日嘅小邀請 (Hybrid)
///                               gives the model the people the elder
///                               shared, the ones to reconnect with, the
///                               interests and 唔想提起, and asks the server
///                               for Siu Yan's memory block.  Rule arm
///                               unchanged (static pool).
///   - [appFontScaleOnlyEnabled] — 10/19 (Junyu): the App's own 字號 (標準 /
///                               大 / 特大) is the only text scale; the
///                               phone's system font size is ignored, so
///                               every page scales the same way.  Off: the
///                               two multiply, capped at 特大 (app.dart).
///   - [briefPrHomeBannerEnabled] — 10/19 (Junyu): the Brief PR invitation
///                               card also sits at the top of 睇今日, under
///                               the greeting, not only on the companion
///                               list page.  Same card, same scheduler.
///   - [testerToolsEnabled]    — 10/19: a tester account (`isTester`, set
///                               by the admin only) unlocks 測試員工具 by
///                               tapping the version line 7× — no PIN, no
///                               special build.  Participants never can.
///   - [transcriptRetentionToggleEnabled] — 10/19: show the participant's
///                               「保留對話紀錄」 switch in 自己 (decision
///                               0020).  Off (default) = the row is hidden;
///                               the stored consent value is untouched.
///   - [weeklyReminderV2Enabled] — 1020 G / 1020e 二.1–二.2 (batch 4): the
///                               weekly questionnaire's v2 windows — weeks
///                               1–3 open day 7 00:00 → end of day 9 (14–16,
///                               21–23); week 4 opens day 26 00:00 and closes
///                               at the end of the day the W4 visit was
///                               recorded (`users/{uid}.w4RecordedOn`), at
///                               the latest the end of day 42
///                               (`WeeklySchedule`).  The server reads the
///                               same flag for the pushes, the missed marks
///                               and the research lead's e-mail
///                               (functions/weekly_schedule.js).  Both arms.
///
/// Call [RemoteFeatureFlags.load] once at startup; read via [current].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'feature_flags.dart';

class RemoteFeatureFlags {
  const RemoteFeatureFlags({
    this.webSearchEnabled = false,
    this.voiceInputEnabled = false,
    this.searchOffReplyEnabled = false,
    this.enrollmentGateEnabled = false,
    this.memoryLayersNoticeEnabled = false,
    this.replyFeedbackEnabled = false,
    this.week1NudgeEnabled = false,
    this.onboardingAfterEnrollmentFix = false,
    this.assessorViewEnabled = false,
    this.outcomeCompletionSummaryEnabled = false,
    this.usageEventsEnabled = false,
    this.opsDashboardEnabled = false,
    this.researcherIntakeEnabled = false,
    this.testerArmSwitchEnabled = false,
    this.s1aEventLogEnabled = false,
    this.homeMoodOpensCheckInEnabled = false,
    this.suggestionsUseProfileEnabled = false,
    this.appFontScaleOnlyEnabled = false,
    this.briefPrHomeBannerEnabled = false,
    this.testerToolsEnabled = false,
    this.transcriptRetentionToggleEnabled = false,
    this.weeklyReminderV2Enabled = false,
  });

  final bool webSearchEnabled;
  final bool voiceInputEnabled;
  final bool searchOffReplyEnabled;
  final bool enrollmentGateEnabled;
  final bool memoryLayersNoticeEnabled;
  final bool replyFeedbackEnabled;
  final bool week1NudgeEnabled;
  final bool onboardingAfterEnrollmentFix;
  final bool assessorViewEnabled;
  final bool outcomeCompletionSummaryEnabled;
  final bool usageEventsEnabled;
  final bool opsDashboardEnabled;
  final bool researcherIntakeEnabled;
  final bool testerArmSwitchEnabled;
  final bool s1aEventLogEnabled;
  final bool homeMoodOpensCheckInEnabled;
  final bool suggestionsUseProfileEnabled;
  final bool appFontScaleOnlyEnabled;
  final bool briefPrHomeBannerEnabled;
  final bool testerToolsEnabled;
  final bool transcriptRetentionToggleEnabled;
  final bool weeklyReminderV2Enabled;

  static RemoteFeatureFlags _current = const RemoteFeatureFlags();

  /// The active flags (all off until [load] reads the document).
  static RemoteFeatureFlags get current => _current;

  /// Test / tooling hook.
  @visibleForTesting
  static set current(RemoteFeatureFlags value) => _current = value;

  /// Firestore document holding the flags.  Read-only for clients.
  static const String remotePath = 'app_config/feature_flags';

  /// Read the flags.  Never throws; on any failure every flag is off.
  static Future<RemoteFeatureFlags> load({bool available = true}) async {
    if (!available) return _current = const RemoteFeatureFlags();
    try {
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      _current = fromMap(snap.data() ?? const {});
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteFeatureFlags] load failed: $e');
      _current = const RemoteFeatureFlags();
    }
    return _current;
  }

  /// Pure parse used by [load] and tests: only `true` turns a flag on.
  static RemoteFeatureFlags fromMap(Map<String, dynamic> map) =>
      RemoteFeatureFlags(
        webSearchEnabled: map['webSearchEnabled'] == true,
        voiceInputEnabled: map['voiceInputEnabled'] == true,
        searchOffReplyEnabled: map['searchOffReplyEnabled'] == true,
        enrollmentGateEnabled: map['enrollmentGateEnabled'] == true,
        memoryLayersNoticeEnabled: map['memoryLayersNoticeEnabled'] == true,
        replyFeedbackEnabled: map['replyFeedbackEnabled'] == true,
        week1NudgeEnabled: map['week1NudgeEnabled'] == true,
        onboardingAfterEnrollmentFix:
            map['onboardingAfterEnrollmentFix'] == true,
        assessorViewEnabled: map['assessorViewEnabled'] == true,
        outcomeCompletionSummaryEnabled:
            map['outcomeCompletionSummaryEnabled'] == true,
        usageEventsEnabled: map['usageEventsEnabled'] == true,
        opsDashboardEnabled: map['opsDashboardEnabled'] == true,
        researcherIntakeEnabled: map['researcherIntakeEnabled'] == true,
        testerArmSwitchEnabled: map['testerArmSwitchEnabled'] == true,
        s1aEventLogEnabled: map['s1aEventLogEnabled'] == true,
        homeMoodOpensCheckInEnabled:
            map['homeMoodOpensCheckInEnabled'] == true,
        suggestionsUseProfileEnabled:
            map['suggestionsUseProfileEnabled'] == true,
        appFontScaleOnlyEnabled: map['appFontScaleOnlyEnabled'] == true,
        briefPrHomeBannerEnabled: map['briefPrHomeBannerEnabled'] == true,
        testerToolsEnabled: map['testerToolsEnabled'] == true,
        transcriptRetentionToggleEnabled:
            map['transcriptRetentionToggleEnabled'] == true,
        weeklyReminderV2Enabled: map['weeklyReminderV2Enabled'] == true,
      );

  /// Phase B (`PHASE_B=true` build) hides the Hybrid-only 👍/👎 reply
  /// feedback in both arms unless [replyFeedbackEnabled] (10/14).
  static bool get hideReplyFeedback =>
      FeatureFlags.phaseB && !_current.replyFeedbackEnabled;

  /// Phase B hides the Phase A first-week nudge banner unless
  /// [week1NudgeEnabled] (10/14).
  static bool get hideWeek1Nudge =>
      FeatureFlags.phaseB && !_current.week1NudgeEnabled;
}

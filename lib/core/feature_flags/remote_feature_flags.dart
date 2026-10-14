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
  });

  final bool webSearchEnabled;
  final bool voiceInputEnabled;
  final bool searchOffReplyEnabled;
  final bool enrollmentGateEnabled;
  final bool memoryLayersNoticeEnabled;
  final bool replyFeedbackEnabled;
  final bool week1NudgeEnabled;
  final bool onboardingAfterEnrollmentFix;

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

/// T25 (registry C16) — what a session is, how it ends and when it counts.
///
/// Pure rules, no Firestore: [ChatSessionRecorder] applies them on the
/// chat pages, [BriefPrScheduler] uses them to decide invitations, and the
/// app-start sweep uses them to classify sessions a process kill left open.
///
/// Everything new is behind `app_config/phase_b.sessionBriefPrV2Enabled`
/// ([SessionRules.v2]).  With the switch off, [SessionRules.current] still
/// describes today's behaviour (10-minute idle timeout from
/// `PhaseAConfig`, no validity rule) so call sites have one object to read.
library;

import '../config/phase_a_config.dart';
import '../config/phase_b_config.dart';

/// Session end reasons.  `user_left` / `app_killed` are the pre-T25 values
/// and stay in use while the v2 switch is off; the others are the v2 set
/// (C16) plus `submitted` for the rule arm's one-submission sessions
/// (decision 0015).
class SessionEndReason {
  SessionEndReason._();

  // Pre-T25 (switch off).
  static const userLeft = 'user_left';
  static const appKilled = 'app_killed';

  // Both before and after T25.
  static const timeout = 'timeout';
  static const crisis = 'crisis';

  // T25 v2.
  /// S9 「今日傾到呢度」 at the top left of the chat page.
  static const closeButton = 'close_button';

  /// Back key, back gesture or the AppBar back arrow.
  static const back = 'back';

  /// Another companion's chat started while this one was still open.
  static const switchAgent = 'switch_agent';

  /// Left open by a process kill / crash; closed by the app-start sweep
  /// from the stored messages and timestamps.
  static const recovered = 'recovered';

  /// Rule arm check-in B / reminiscence B: one submission is one session
  /// (decision 0015).  Not in the C16 list — see the T25 report.
  static const submitted = 'submitted';

  /// Reasons after which the Brief PR invitation goes to the catch-up card
  /// (S10b) on the next app open rather than the list-page card (S10a).
  static bool isCatchUp(String reason) =>
      reason == timeout || reason == recovered;
}

/// Session type (C16): free chat, structured check-in, structured
/// reminiscence.  Both arms use the same three values.
enum SessionType {
  freeChat,
  checkIn,
  reminiscence;

  String get code => switch (this) {
        SessionType.freeChat => 'free_chat',
        SessionType.checkIn => 'check_in',
        SessionType.reminiscence => 'reminiscence',
      };

  static SessionType? tryParse(String? code) {
    for (final t in SessionType.values) {
      if (t.code == code) return t;
    }
    return null;
  }

  /// Derived from the existing `moduleId` values so no page needs a new
  /// parameter: `m2_check_in` → check-in, `m3_reminiscence_w{N}` →
  /// reminiscence, everything else (Tung Tung, reflective dialogue) →
  /// free chat.
  static SessionType forModule(String moduleId) {
    if (moduleId == 'm2_check_in') return SessionType.checkIn;
    if (moduleId.startsWith('m3_reminiscence')) return SessionType.reminiscence;
    return SessionType.freeChat;
  }
}

/// The counts and marks a validity decision needs.  Built by the recorder
/// from live state, or by the sweep from a stored `sessions` document.
class SessionTally {
  const SessionTally({
    required this.sessionType,
    required this.userMessageCount,
    required this.replyCount,
    this.moodRecorded = false,
    this.summarySaved = false,
    this.isRuleSubmission = false,
    this.ruleSubmissionCompleted = false,
    this.endReason,
    this.checkInCompleted = false,
  });

  final SessionType sessionType;

  /// Every message the participant sent in this session.
  final int userMessageCount;

  /// User messages that received a real reply (fallback and crisis
  /// short-circuit turns excluded).
  final int replyCount;

  /// Hybrid check-in: today's mood was recorded.
  final bool moodRecorded;

  /// Hybrid reminiscence: the weekly summary was saved via 儲存.
  final bool summarySaved;

  /// Rule arm form pages (check-in B, reminiscence B).
  final bool isRuleSubmission;

  /// Rule arm: required fields filled, submitted and the response page
  /// shown.
  final bool ruleSubmissionCompleted;
  final String? endReason;

  /// 1020 F (3) — the chat check-in (`checkInChatV2Enabled`, both arms)
  /// was answered to the end (Q5).  Written to the row only when true, so
  /// rows from the old pages look exactly as before.
  final bool checkInCompleted;

  Map<String, dynamic> toMap() => {
        'sessionType': sessionType.code,
        'userMessageCount': userMessageCount,
        'replyCount': replyCount,
        'moodRecorded': moodRecorded,
        'summarySaved': summarySaved,
        'isRuleSubmission': isRuleSubmission,
        'ruleSubmissionCompleted': ruleSubmissionCompleted,
        if (checkInCompleted) 'checkInCompleted': true,
      };

  /// Rebuild from a stored `sessions` document (app-start sweep).  Missing
  /// fields read as 0 / false so pre-T25 rows classify as not valid.
  static SessionTally fromMap(Map<String, dynamic> m, {String? endReason}) {
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    bool b(String k) => m[k] == true;
    return SessionTally(
      sessionType: SessionType.tryParse(m['sessionType'] as String?) ??
          SessionType.forModule((m['moduleId'] as String?) ?? ''),
      userMessageCount: n('userMessageCount'),
      replyCount: n('replyCount'),
      moodRecorded: b('moodRecorded'),
      summarySaved: b('summarySaved'),
      isRuleSubmission: b('isRuleSubmission'),
      ruleSubmissionCompleted: b('ruleSubmissionCompleted'),
      endReason: endReason ?? m['endReason'] as String?,
      checkInCompleted: b('checkInCompleted'),
    );
  }
}

/// The rule set in force.  [SessionRules.current] reads the configs; tests
/// construct one directly.
class SessionRules {
  const SessionRules({
    required this.v2,
    required this.idleTimeoutMin,
    this.briefPrDailyCapPerAgent = 1,
    this.briefPrCatchUpExpiryHours = 2,
    this.freeChatValidMinUserMessages = 3,
    this.checkInValidRequiresMood = true,
    this.checkInValidMinUserMessages = 1,
    this.reminiscenceValidRequiresSave = false,
  });

  /// `app_config/phase_b.sessionBriefPrV2Enabled`.  Off = pre-T25
  /// behaviour everywhere.
  final bool v2;

  /// Minutes without a new message before the session ends (`timeout`).
  /// v2: `sessionIdleTimeoutMinV2` (30); off: `PhaseAConfig` (10).
  final int idleTimeoutMin;
  final int briefPrDailyCapPerAgent;
  final int briefPrCatchUpExpiryHours;
  final int freeChatValidMinUserMessages;
  final bool checkInValidRequiresMood;
  final int checkInValidMinUserMessages;
  final bool reminiscenceValidRequiresSave;

  /// Pre-T25 behaviour, used while the switch is off.
  static SessionRules legacy({int? idleTimeoutMin}) => SessionRules(
        v2: false,
        idleTimeoutMin:
            idleTimeoutMin ?? PhaseAConfig.current.sessionIdleTimeoutMin,
      );

  static SessionRules fromConfig(PhaseBConfig b, {PhaseAConfig? a}) {
    if (!b.sessionBriefPrV2Enabled) {
      return legacy(idleTimeoutMin: (a ?? PhaseAConfig.current).sessionIdleTimeoutMin);
    }
    return SessionRules(
      v2: true,
      idleTimeoutMin: b.sessionIdleTimeoutMinV2,
      briefPrDailyCapPerAgent: b.briefPrDailyCapPerAgent,
      briefPrCatchUpExpiryHours: b.briefPrCatchUpExpiryHours,
      freeChatValidMinUserMessages: b.freeChatValidMinUserMessages,
      checkInValidRequiresMood: b.hybridCheckInValidRequiresMood,
      checkInValidMinUserMessages: b.hybridCheckInValidMinUserMessages,
      reminiscenceValidRequiresSave: b.hybridReminiscenceValidRequiresSave,
    );
  }

  /// The rules in force now.  `app_config/phase_b` is only read in a
  /// PHASE_B build (lib/main.dart), so a Phase A build never turns v2 on.
  static SessionRules current() => fromConfig(PhaseBConfig.current);

  Duration get idleTimeout => Duration(minutes: idleTimeoutMin);
  Duration get catchUpExpiry => Duration(hours: briefPrCatchUpExpiryHours);

  /// "完成一个互动单元" (C16).  Same rule in both arms; the rule arm's form
  /// pages are the one-submission case of decision 0015.
  bool isValid(SessionTally t) {
    if (t.isRuleSubmission) {
      return t.ruleSubmissionCompleted && t.endReason != SessionEndReason.crisis;
    }
    switch (t.sessionType) {
      case SessionType.freeChat:
        return t.replyCount >= freeChatValidMinUserMessages;
      case SessionType.checkIn:
        // 1020 F (3): a completed chat check-in is one valid session (both
        // arms); chatting on in the same window stays in this session.
        if (t.checkInCompleted) return true;
        if (checkInValidRequiresMood && !t.moodRecorded) return false;
        return t.replyCount >= checkInValidMinUserMessages;
      case SessionType.reminiscence:
        if (reminiscenceValidRequiresSave) return t.summarySaved;
        return t.replyCount >= freeChatValidMinUserMessages;
    }
  }

  /// `scheduleVersion` written on every `sessions` row so analysts can tell
  /// old rows (1) from v2 rows (2).
  int get scheduleVersion => v2 ? 2 : 1;
}

/// What a finished session hands to the Brief PR scheduler (T25).  Built by
/// [ChatSessionRecorder.end] from live state, or by the app-start sweep
/// from a stored `sessions` row (`endReason = recovered`).
class SessionEndSummary {
  const SessionEndSummary({
    required this.uid,
    required this.sessionId,
    required this.agentId,
    required this.tally,
    required this.isValid,
    required this.endReason,
    required this.startedAt,
    required this.endedAt,
    this.lastReplyAt,
  });

  final String uid;
  final String sessionId;
  final String agentId;
  final SessionTally tally;
  final bool isValid;
  final String endReason;
  final DateTime startedAt;
  final DateTime endedAt;

  /// When the last complete reply was shown; the catch-up expiry clock
  /// (C14 "距最后一条完整回复超过 2 小时") starts here.  Null when the
  /// session had no reply — such a session is never valid.
  final DateTime? lastReplyAt;

  SessionType get sessionType => tally.sessionType;
}

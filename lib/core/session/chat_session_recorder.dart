/// Phase A baseline logging layer (Dev spec v1 2026-09 §L-1 / §L-3 / §M-7).
///
/// Three Firestore surfaces, all under the participant's own user doc so
/// the existing owner-only rule covers them:
///
///   • `users/{uid}/sessions/{sessionId}`  — one per agent session or tool
///     session (see [ChatSessionRecorder] / [ToolSessionScope]).
///   • `users/{uid}/turns/{turnId}`        — one per user message + reply
///     (see [TurnRecord]).
///   • `users/{uid}/events/{auto}`         — the existing analytics stream;
///     spec event *types* are written as the event `name` with the spec
///     `payload` as `params`.
///
/// Session definition (M-7): an **agent session** starts when the first
/// user message is sent on a chat page and ends when the participant leaves
/// the page (`user_left`), goes [PhaseAConfig.sessionIdleTimeoutMin] minutes
/// without a user message (`timeout`), or trips acute (`crisis`).  A session
/// that was still open when the process died is closed as `app_killed` by
/// [ChatSessionRecorder.sweepUnclosed] on the next app start.  **Tool
/// sessions** start on page entry and end on page exit.
///
/// T25 (registry C16, `app_config/phase_b.sessionBriefPrV2Enabled`): with
/// the switch ON the idle timeout comes from `sessionIdleTimeoutMinV2`
/// (30 min), the end reasons are `close_button` / `back` / `switch_agent` /
/// `timeout` / `recovered` / `crisis`, every row carries `sessionType`,
/// `userMessageCount`, `replyCount`, `isValid`, `lastReplyAt` and
/// `scheduleVersion: 2`, and a session left open by a process kill is
/// closed as `recovered` (not `app_killed`).  OFF = everything above as
/// before, `scheduleVersion: 1`.  See [SessionRules].
///
/// All Firestore writes are fire-and-forget (SDK offline queue); nothing
/// here ever blocks the UI or throws into the page.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_settings_scope.dart';
import '../../features/analytics/data/analytics_service.dart';
import '../../features/analytics/presentation/analytics_scope.dart';
import '../../features/auth/presentation/auth_service_scope.dart';
import '../config/phase_a_config.dart';
import '../llm/llm_gateway.dart';
import '../safety/distress_detector.dart';
import '../voice/voice_input_button.dart';
import 'idle_session_timer.dart';
import 'session_rules.dart';

// T25: end reasons, session types and validity rules live in
// session_rules.dart; re-exported so existing imports keep working.
export 'session_rules.dart'
    show SessionEndReason, SessionEndSummary, SessionRules, SessionTally, SessionType;

/// Spec event types (L-1).  Written via [AnalyticsService.logEvent] with
/// the payload as `params`.
class PhaseAEvents {
  PhaseAEvents._();
  static const teOffer = 'te_offer';
  static const teAccept = 'te_accept';
  static const teDecline = 'te_decline';
  static const teModuleOpen = 'te_module_open';
  static const teModuleComplete = 'te_module_complete';
  static const crisisPageShown = 'crisis_page_shown';
  static const crisisCallTapped = 'crisis_call_tapped';
  static const moderateSheetShown = 'moderate_sheet_shown';
  static const moderateSheetOpenedResources = 'moderate_sheet_opened_resources';
  static const referralOffered = 'referral_offered';
  static const agentSwitch = 'agent_switch';
  static const weeklyPrPushed = 'weekly_pr_pushed';
  static const weeklyPrCompleted = 'weekly_pr_completed';
  static const weeklyPrMissed = 'weekly_pr_missed';
  static const moodCheckin = 'mood_checkin';
  static const w2PushSent = 'w2_push_sent';
  static const w2Completed = 'w2_completed';
  static const notificationReceived = 'notification_received';
  static const notificationOpened = 'notification_opened';
  static const screenView = 'screen_view';
  static const appForeground = 'app_foreground';
  static const appBackground = 'app_background';
  static const llmFallback = 'llm_fallback';
  static const week1NudgeShown = 'week1_nudge_shown';
  static const appStart = 'app_start';
  static const sessionStart = 'agent_session_start';
  static const sessionEnd = 'agent_session_end';
}

/// Input modality of one user message.
enum InputModality {
  text,
  voice;

  String get code => name;
}

/// Everything the page knows about one user message + its reply, turned
/// into the L-1 `turns/{turnId}` document by [toMap].
class TurnRecord {
  final String agentId;
  final String moduleId;
  final String? theme;
  final DateTime userSent;
  final DateTime replyShown;
  final InputModality modality;
  final int? voiceDurationMs;

  /// Length of the raw user message (before any PII stripping).
  final int charCount;
  final DistressMatch detector;
  final bool shortCircuited;

  /// Whether the moderate / acute template was displayed.
  final bool ackShown;
  final LlmResponse response;

  /// Referral card surfaced by the routing service this turn (target id).
  final String? referralCardTarget;

  /// The exact Thought Exercise invitation shown this turn, if any (L-3).
  final String? teOfferText;

  /// Tung Tung only: `A` (article Q&A) / `B` (chitchat + search).
  final String? tungTungMode;
  final String? tungTungArticleId;
  final bool tungTungSearchInvoked;

  const TurnRecord({
    required this.agentId,
    required this.moduleId,
    this.theme,
    required this.userSent,
    required this.replyShown,
    required this.modality,
    this.voiceDurationMs,
    required this.charCount,
    required this.detector,
    required this.shortCircuited,
    required this.ackShown,
    required this.response,
    this.referralCardTarget,
    this.teOfferText,
    this.tungTungMode,
    this.tungTungArticleId,
    this.tungTungSearchInvoked = false,
  });

  bool get isFallback => response.isFallback;

  Map<String, dynamic> toMap({
    required String participantId,
    required String sessionId,
  }) {
    final replyText = response.text;
    final referral = ReferralScanner.scan(replyText);
    final referralTarget = referralCardTarget ?? referral;
    final teFromReply = TeOfferScanner.scan(replyText);
    final teText = teOfferText ?? teFromReply;
    final flags = _fiveFlags(response);
    return {
      'participantId': participantId,
      'sessionId': sessionId,
      'agentId': agentId,
      'moduleId': moduleId,
      'theme': theme,
      'ts': {
        'userSent': Timestamp.fromDate(userSent),
        'replyShown': Timestamp.fromDate(replyShown),
      },
      'input': {
        'modality': modality.code,
        'voiceDurationMs': voiceDurationMs,
        'charCount': charCount,
      },
      'detector': {
        'tier': detector.level.tierCode,
        'matchedTerm': detector.matchedTerm,
        'category': detector.category?.code,
        'lexiconVersion': DistressDetector.wordlistVersion,
        'shortCircuited': shortCircuited,
        'ackShown': ackShown,
      },
      'llm': {
        'status': response.status.code,
        'error': response.error,
        'model': response.model,
        'latencyMs': response.latencyMs,
        'systemPromptHash': response.metadata.systemPromptHash,
        'promptVersion': response.promptVersion,
        'temperature': response.temperature,
      },
      'flags': flags,
      'referral': {
        'offered': referralTarget != null,
        'target': referralTarget,
      },
      'te': {
        'offered': teText != null,
        'offerText': teText,
      },
      'tungtung': {
        'mode': tungTungMode,
        'articleId': tungTungArticleId,
        'searchInvoked': tungTungSearchInvoked,
      },
      'feedback': {'thumb': null, 'reason': null},
      // T26 (decision 0033) — the safety turn id: the same id as
      // `safety_events.turnId` and `safety_classifier_calls.turn_id`, so a
      // safety record can be traced to its message.  Both arms.
      'safetyTurnId': response.turnId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// F1…F5 = the five CF flags in spec order; all null on fallback /
  /// short-circuit (spec §S-6) or when the CF did not return them.
  static Map<String, bool?> _fiveFlags(LlmResponse r) {
    const order = [
      'specific_content_engagement',
      'cross_session_memory',
      'honest_unfamiliarity',
      'mixed_content_routing',
      'generative_summary',
    ];
    final usable = r.status == LlmStatus.ok && r.llmFlags.isNotEmpty;
    return {
      for (var i = 0; i < order.length; i++)
        'F${i + 1}': usable ? (r.llmFlags[order[i]] as bool?) : null,
    };
  }
}

/// Detects a cross-referral phrasing in an agent reply (mirrors the
/// `REFERRAL_MARKERS` regex family in `functions/llm_flags.js`) and maps it
/// to a target agent id.
class ReferralScanner {
  ReferralScanner._();

  static final _names = <RegExp, String>{
    RegExp(r'小欣|siu yan', caseSensitive: false): 'siu_yan',
    RegExp(r'阿珍|阿伯|ah jan|ah bak', caseSensitive: false): 'ah_jan_ah_bak',
    RegExp(r'通通|tung tung', caseSensitive: false): 'tung_tung',
  };

  /// A hand-off verb / invitation must accompany the name so a mere
  /// mention ("小欣話過…") does not count as an offer.
  static final _invite = RegExp(
    r'搵|過去|傾下|傾吓|傾傾|要唔要|去同|talk to|chat with|find|reach out',
    caseSensitive: false,
  );

  static String? scan(String reply) {
    if (reply.isEmpty || !_invite.hasMatch(reply)) return null;
    String? best;
    var bestIdx = reply.length;
    for (final e in _names.entries) {
      final m = e.key.firstMatch(reply);
      if (m != null && m.start < bestIdx) {
        bestIdx = m.start;
        best = e.value;
      }
    }
    return best;
  }
}

/// L-3 — finds the locked Thought Exercise invitation sentence in a reply
/// and returns the *whole* sentence including the filled thought summary.
class TeOfferScanner {
  TeOfferScanner._();

  /// Locked prefix from `siu_yan_v1.txt` / [NamingThoughtCard].
  static const lockedPrefix = '你頭先講咗一句令我有少少 stuck';

  static String? scan(String reply) {
    final idx = reply.indexOf(lockedPrefix);
    if (idx < 0) return null;
    // Take from the locked prefix to the end of the invitation ("要唔要都得。")
    // or the end of the paragraph, whichever comes first.
    final rest = reply.substring(idx);
    final endMarker = rest.indexOf('要唔要都得');
    if (endMarker >= 0) {
      final cut = endMarker + '要唔要都得'.length;
      final tail = rest.length > cut && rest[cut] == '。' ? cut + 1 : cut;
      return rest.substring(0, tail).trim();
    }
    final nl = rest.indexOf('\n');
    return (nl >= 0 ? rest.substring(0, nl) : rest).trim();
  }
}

/// Owns the lifecycle of ONE agent session on a chat page.  Create in
/// `initState`, call [ensureStarted] before the first LLM call, [logTurn]
/// after each reply, [end] from the PopScope / crisis path, and [dispose]
/// from the page's `dispose`.
class ChatSessionRecorder {
  ChatSessionRecorder({
    required this.uid,
    required this.agentId,
    required this.moduleId,
    required this.analytics,
    this.available = true,
    this.theme,
    this.onIdleTimeout,
    this.onSwitchedAway,
    this.reminiscenceV2 = false,
    SessionRules? rules,
    DateTime Function()? clock,
    FirebaseFirestore? db,
    IdleSessionTimer Function(Duration, void Function())? timerFactory,
  })  : _rules = rules,
        _clock = clock ?? DateTime.now,
        _db = db,
        _timerFactory = timerFactory;

  final String? uid;
  final String agentId;
  final String moduleId;
  final String? theme;
  final AnalyticsService analytics;
  final bool available;

  /// Called after the idle timeout closes the session so the page can run
  /// its end-of-session flow (Brief PR) without waiting for a pop.
  final void Function()? onIdleTimeout;

  /// T25 v2 — called after another companion's session started while this
  /// one was open and closed it as `switch_agent`, so the page can run its
  /// end-of-session flow (Brief PR scheduler) for the closed session.
  final void Function()? onSwitchedAway;

  /// 1020d (回憶 v2) — the v2 reminiscence page: validity counts the
  /// week's questions answered in the session
  /// ([markReminiscenceQuestionAnswered]).
  final bool reminiscenceV2;

  final SessionRules? _rules;
  final DateTime Function() _clock;
  final FirebaseFirestore? _db;
  final IdleSessionTimer Function(Duration, void Function())? _timerFactory;

  String? _sessionId;
  DateTime? _startedAt;
  DateTime? _lastActivityAt;
  int _userTurnCount = 0;
  int _fallbackCount = 0;
  // T25 — v2 tally.  `_userMessageCount` counts every user message,
  // `_replyCount` only those that got a real reply (no fallback, no crisis
  // short-circuit).
  int _userMessageCount = 0;
  int _replyCount = 0;
  DateTime? _lastReplyAt;
  DateTime? _endedAt;
  bool _moodRecorded = false;
  bool _summarySaved = false;
  bool _ruleSubmission = false;
  bool _ruleSubmissionCompleted = false;
  bool _checkInCompleted = false;
  int _reminiscenceQuestionsAnswered = 0;
  bool _ended = false;
  String? _endReason;
  IdleSessionTimer? _idle;

  /// The rules this recorder applies (fixed at construction or read from
  /// the configs on first use so a session never changes rules midway).
  SessionRules get rules => _rulesInUse ??= _rules ?? SessionRules.current();
  SessionRules? _rulesInUse;

  String? get sessionId => _sessionId;
  DateTime? get startedAt => _startedAt;
  bool get isOpen => _sessionId != null && !_ended;
  bool get hasEnded => _ended;
  String? get endReason => _endReason;

  /// User turns that reached the model (fallback turns excluded, S-6).
  int get userTurnCount => _userTurnCount;
  int get fallbackCount => _fallbackCount;

  /// T25 — every user message in this session.
  int get userMessageCount => _userMessageCount;

  /// T25 — user messages that received a real reply.
  int get replyCount => _replyCount;
  DateTime? get lastReplyAt => _lastReplyAt;
  DateTime? get endedAt => _endedAt;
  SessionType get sessionType => SessionType.forModule(moduleId);

  /// T25 — the counts and marks the validity rule reads.
  SessionTally get tally => SessionTally(
        sessionType: sessionType,
        userMessageCount: _userMessageCount,
        replyCount: _replyCount,
        moodRecorded: _moodRecorded,
        summarySaved: _summarySaved,
        isRuleSubmission: _ruleSubmission,
        ruleSubmissionCompleted: _ruleSubmissionCompleted,
        endReason: _endReason,
        checkInCompleted: _checkInCompleted,
        reminiscenceV2: reminiscenceV2,
        reminiscenceQuestionsAnswered: _reminiscenceQuestionsAnswered,
      );

  /// T25 — "完成一个互动单元" (C16) under [rules].  Under the legacy rules
  /// (switch off) this is still computed and stored, so analysts can
  /// re-classify old rows, but nothing in the App reads it then.
  bool get isValid => rules.isValid(tally);

  /// Hybrid check-in: today's mood is recorded (gate, home pad or save).
  void markMoodRecorded() => _moodRecorded = true;

  /// Hybrid reminiscence: the weekly summary was saved via 儲存.
  void markSummarySaved() => _summarySaved = true;

  /// Rule arm form pages (decision 0015): one submission is one session;
  /// [completed] = required fields filled, submitted, response shown.
  void markRuleSubmission({required bool completed}) {
    _ruleSubmission = true;
    _ruleSubmissionCompleted = completed;
  }

  /// 1020 F (3) — the chat check-in (`checkInChatV2Enabled`) was answered
  /// to the end in this session: the session counts as valid
  /// ([SessionRules.isValid]) and stays open for the chat that follows.
  /// Marks the row at once so a session recovered after a process kill
  /// keeps it.
  void markCheckInCompleted() {
    _checkInCompleted = true;
    final ref = _sessionRef;
    if (ref == null || _ended) return;
    unawaited(_guard(
        () => ref.set({'checkInCompleted': true}, SetOptions(merge: true))));
  }

  bool get checkInCompleted => _checkInCompleted;

  /// 1020d (2)(5) — one of the week's questions was answered in this
  /// session (v2 reminiscence page, both arms).  Marks the row at once, as
  /// [markCheckInCompleted] does.
  void markReminiscenceQuestionAnswered() {
    _reminiscenceQuestionsAnswered++;
    final ref = _sessionRef;
    if (ref == null || _ended) return;
    final n = _reminiscenceQuestionsAnswered;
    unawaited(_guard(() => ref.set({
          'reminiscenceV2': true,
          'reminiscenceQuestionsAnswered': n,
        }, SetOptions(merge: true))));
  }

  int get reminiscenceQuestionsAnswered => _reminiscenceQuestionsAnswered;

  /// T25 — what the Brief PR scheduler needs once the session has ended.
  /// Null while the session is open or when there is no signed-in user.
  SessionEndSummary? get endSummary {
    final u = uid;
    final s = _sessionId;
    final r = _endReason;
    if (u == null || s == null || r == null || !_ended) return null;
    return SessionEndSummary(
      uid: u,
      sessionId: s,
      agentId: agentId,
      tally: tally,
      isValid: isValid,
      endReason: r,
      startedAt: _startedAt ?? _endedAt ?? _clock(),
      endedAt: _endedAt ?? _clock(),
      lastReplyAt: _lastReplyAt,
    );
  }

  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>>? get _sessionRef {
    final u = uid;
    final s = _sessionId;
    if (!available || u == null || s == null) return null;
    return _firestore.collection('users').doc(u).collection('sessions').doc(s);
  }

  /// Last agent whose session started in this process — drives the
  /// `agent_switch(from, to)` event (L-1) regardless of how the participant
  /// reached the new agent (home tile, referral card, continue-chat card).
  static String? _lastAgentId;

  /// T25 — every recorder with an open session in this process.  Starting
  /// a session with another companion closes these as `switch_agent` (v2).
  static final Set<ChatSessionRecorder> _open = <ChatSessionRecorder>{};

  @visibleForTesting
  static void resetProcessStateForTest() {
    _lastAgentId = null;
    _open.clear();
  }

  /// Start the session if it is not already open.  Safe to call on every
  /// send.  A session that has ended (timeout) is replaced by a new one.
  Future<void> ensureStarted() async {
    if (isOpen) return;
    final previous = _lastAgentId;
    _lastAgentId = agentId;
    if (previous != null && previous != agentId) {
      unawaited(analytics.logEvent(PhaseAEvents.agentSwitch, {
        'from': previous,
        'to': agentId,
      }));
    }
    // T25 v2 — switching companion ends the other companion's session.
    if (rules.v2) {
      for (final other in _open.toList()) {
        if (other.agentId == agentId || !other.isOpen) continue;
        await other.end(SessionEndReason.switchAgent);
        other.onSwitchedAway?.call();
      }
    }
    _sessionId = _newId();
    _startedAt = _clock();
    _lastActivityAt = _startedAt;
    _userTurnCount = 0;
    _fallbackCount = 0;
    _userMessageCount = 0;
    _replyCount = 0;
    _lastReplyAt = null;
    _endedAt = null;
    _ended = false;
    _endReason = null;
    _checkInCompleted = false;
    _reminiscenceQuestionsAnswered = 0;
    _open.add(this);
    _startIdleTimer();
    unawaited(analytics.logEvent(PhaseAEvents.sessionStart, {
      'sessionId': _sessionId,
      'agentId': agentId,
      'moduleId': moduleId,
      if (theme != null) 'theme': theme,
    }));
    final ref = _sessionRef;
    if (ref == null) return;
    unawaited(_guard(() => ref.set({
          'participantId': uid,
          'sessionId': _sessionId,
          'kind': 'agent',
          'agentId': agentId,
          'toolId': null,
          'moduleId': moduleId,
          'theme': theme,
          'startedAt': Timestamp.fromDate(_startedAt!),
          'lastActivityAt': Timestamp.fromDate(_startedAt!),
          'endedAt': null,
          'endReason': null,
          'userTurnCount': 0,
          'fallbackCount': 0,
          'briefPR': {'shown': false, 'completed': null, 'items': null},
          'sessionSummaryShown': false,
          'sessionSummaryHasTEPointer': false,
          'lexiconVersion': DistressDetector.wordlistVersion,
          // T25 (C16) — v2 fields, written from the start so the app-start
          // sweep can classify a row left open by a process kill.
          'scheduleVersion': rules.scheduleVersion,
          'sessionType': sessionType.code,
          'userMessageCount': 0,
          'replyCount': 0,
          'lastReplyAt': null,
          'isValid': false,
          'moodRecorded': _moodRecorded,
          'summarySaved': _summarySaved,
          'isRuleSubmission': _ruleSubmission,
          'ruleSubmissionCompleted': _ruleSubmissionCompleted,
          'briefPrInvitedTodayAlready': null,
          'briefPrSkippedByCap': false,
          if (reminiscenceV2) 'reminiscenceV2': true,
          if (reminiscenceV2) 'reminiscenceQuestionsAnswered': 0,
        })));
  }

  void _startIdleTimer() {
    _idle?.dispose();
    final d = rules.idleTimeout;
    void fire() {
      if (!isOpen) return;
      unawaited(end(SessionEndReason.timeout));
      onIdleTimeout?.call();
    }

    _idle = _timerFactory != null
        ? _timerFactory(d, fire)
        : IdleSessionTimer(idleDuration: d, onIdle: fire);
    _idle!.start();
  }

  /// Any user activity (typing, tapping, voice) resets the idle clock.
  void bumpActivity() {
    _idle?.bumpActivity();
  }

  /// Persist one turn.  Returns the turn doc id (null when logging is
  /// unavailable) so the page can attach thumbs feedback to it later.
  Future<String?> logTurn(TurnRecord turn) async {
    await ensureStarted();
    _lastActivityAt = _clock();
    bumpActivity();
    _userMessageCount++;
    if (turn.isFallback) {
      _fallbackCount++;
      unawaited(analytics.logEvent(PhaseAEvents.llmFallback, {
        'sessionId': _sessionId,
        'agentId': agentId,
        'error': turn.response.error,
      }));
    } else {
      _userTurnCount++;
    }
    // T25 — a "reply" is a real answer: not a fallback, not the crisis
    // short-circuit template.
    if (!turn.isFallback && !turn.shortCircuited) {
      _replyCount++;
      _lastReplyAt = turn.replyShown;
    }
    final u = uid;
    final s = _sessionId;
    if (!available || u == null || s == null) return null;
    final turnRef = _firestore.collection('users').doc(u).collection('turns').doc();
    unawaited(_guard(() => turnRef.set(turn.toMap(participantId: u, sessionId: s))));
    unawaited(_guard(() => _sessionRef!.set({
          'userTurnCount': _userTurnCount,
          'fallbackCount': _fallbackCount,
          'lastActivityAt': Timestamp.fromDate(_lastActivityAt!),
          'userMessageCount': _userMessageCount,
          'replyCount': _replyCount,
          'lastReplyAt':
              _lastReplyAt == null ? null : Timestamp.fromDate(_lastReplyAt!),
          'moodRecorded': _moodRecorded,
          'summarySaved': _summarySaved,
        }, SetOptions(merge: true))));
    return turnRef.id;
  }

  /// Record that the moderate_interrupt sheet / crisis page was shown.
  void logEvent(String type, [Map<String, dynamic> payload = const {}]) {
    unawaited(analytics.logEvent(type, {
      'sessionId': _sessionId,
      'agentId': agentId,
      ...payload,
    }));
  }

  /// Close the session.  Idempotent — the first reason wins.
  Future<void> end(String reason) async {
    if (_sessionId == null || _ended) return;
    _ended = true;
    _endReason = reason;
    _endedAt = _clock();
    _open.remove(this);
    _idle?.dispose();
    _idle = null;
    unawaited(analytics.logEvent(PhaseAEvents.sessionEnd, {
      'sessionId': _sessionId,
      'agentId': agentId,
      'endReason': reason,
      'userTurnCount': _userTurnCount,
      'fallbackCount': _fallbackCount,
      'durationSeconds':
          _endedAt!.difference(_startedAt ?? _endedAt!).inSeconds,
      'isValid': isValid,
    }));
    final ref = _sessionRef;
    if (ref == null) return;
    unawaited(_guard(() => ref.set({
          'endedAt': FieldValue.serverTimestamp(),
          'endReason': reason,
          'userTurnCount': _userTurnCount,
          'fallbackCount': _fallbackCount,
          // T25 (C16).
          'userMessageCount': _userMessageCount,
          'replyCount': _replyCount,
          'lastReplyAt':
              _lastReplyAt == null ? null : Timestamp.fromDate(_lastReplyAt!),
          'isValid': isValid,
          'moodRecorded': _moodRecorded,
          'summarySaved': _summarySaved,
          'isRuleSubmission': _ruleSubmission,
          'ruleSubmissionCompleted': _ruleSubmissionCompleted,
          if (_checkInCompleted) 'checkInCompleted': true,
          if (reminiscenceV2) 'reminiscenceV2': true,
          if (reminiscenceV2)
            'reminiscenceQuestionsAnswered': _reminiscenceQuestionsAnswered,
        }, SetOptions(merge: true))));
  }

  /// T25 — the Brief PR scheduler's marks on the session row
  /// (`briefPrInvitedTodayAlready`, `briefPrSkippedByCap`).  Static because
  /// the scheduler may run after the page (and recorder) is gone.
  static Future<void> patchSession({
    required String uid,
    required String sessionId,
    required Map<String, dynamic> patch,
    FirebaseFirestore? db,
  }) =>
      _guard(() => (db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .set(patch, SetOptions(merge: true)));

  /// M-1 — Brief PR outcome for this session.  [items] null = skipped.
  Future<void> recordBriefPr({
    required bool shown,
    bool? completed,
    Map<String, int?>? items,
  }) async {
    final u = uid;
    final s = _sessionId;
    if (!available || u == null || s == null) return;
    await recordBriefPrFor(
        uid: u, sessionId: s, shown: shown, completed: completed, items: items);
  }

  /// Static form used by [BriefPrPage], which may outlive the recorder.
  static Future<void> recordBriefPrFor({
    required String uid,
    required String sessionId,
    required bool shown,
    bool? completed,
    Map<String, int?>? items,
  }) async {
    unawaited(_guard(() => FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .set({
          'briefPR': {'shown': shown, 'completed': completed, 'items': items},
        }, SetOptions(merge: true))));
  }

  /// Patch a turn doc after the fact (e.g. a referral card that surfaced
  /// once the routing service's LLM judgement returned).
  Future<void> updateTurn(String? turnId, Map<String, dynamic> patch) async {
    final u = uid;
    if (!available || u == null || turnId == null) return;
    unawaited(_guard(() => _firestore
        .collection('users')
        .doc(u)
        .collection('turns')
        .doc(turnId)
        .set(patch, SetOptions(merge: true))));
  }

  /// Ah Jan end-of-session summary flags.
  Future<void> recordSessionSummary({
    required bool shown,
    required String summaryText,
  }) async {
    final ref = _sessionRef;
    if (ref == null) return;
    unawaited(_guard(() => ref.set({
          'sessionSummaryShown': shown,
          'sessionSummaryHasTEPointer': hasTePointer(summaryText),
        }, SetOptions(merge: true))));
  }

  /// String match for the soft pointer sentence the Ah Jan prompt allows
  /// in the end-of-session summary (spec §5: "望一望心入面").
  static bool hasTePointer(String summary) => summary.contains('望一望心入面');

  /// Whether the Brief PR should be offered for this session (M-1).
  bool get briefPrEligible =>
      _endReason != SessionEndReason.crisis &&
      _userTurnCount >= PhaseAConfig.current.briefPRMinTurns;

  void dispose() {
    _idle?.dispose();
    _idle = null;
  }

  /// M-6 — attach thumbs feedback to a turn doc.
  static Future<void> updateFeedback({
    required String uid,
    required String turnId,
    required String thumb,
    String? reason,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('turns')
          .doc(turnId)
          .set({
        'feedback': {
          'thumb': thumb,
          'reason': reason,
          'at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatSessionRecorder] feedback failed: $e');
    }
  }

  /// M-7 — on app start, close any session left open by a process kill.
  /// `endedAt` is set to the last recorded activity so durations stay
  /// honest.
  ///
  /// T25 v2: the row is closed as `recovered`, its validity is judged from
  /// the stored counts ([classifyRecovered]) and, when it is valid,
  /// [onRecovered] hands it to the Brief PR scheduler (catch-up card).
  /// Rows written before v2 (no `scheduleVersion`) are still closed as
  /// `app_killed` and never produce an invitation.
  static Future<void> sweepUnclosed(
    String uid, {
    SessionRules? rules,
    DateTime Function()? clock,
    Future<void> Function(SessionEndSummary summary)? onRecovered,
  }) async {
    final r = rules ?? SessionRules.current();
    final now = (clock ?? DateTime.now)();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .where('endedAt', isNull: true)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final patch = classifyRecovered(data, r, now: now);
        await d.reference.set(patch, SetOptions(merge: true));
        if (onRecovered == null || !r.v2) continue;
        final summary = recoveredSummary(uid, d.id, data, r, now: now);
        if (summary != null) await onRecovered(summary);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatSessionRecorder] sweep failed: $e');
    }
  }

  /// The patch the sweep writes for one open row.  Pure, so it is tested
  /// without Firestore.  Pre-v2 rows (no `scheduleVersion`), or any row
  /// while the switch is off, get the pre-T25 `app_killed` close; v2 rows
  /// get `recovered` plus `isValid` from the stored counts.
  static Map<String, dynamic> classifyRecovered(
    Map<String, dynamic> data,
    SessionRules rules, {
    required DateTime now,
  }) {
    final last = data['lastActivityAt'];
    final endedAt = last is Timestamp ? last : Timestamp.fromDate(now);
    final isV2Row = data['scheduleVersion'] == 2;
    if (!rules.v2 || !isV2Row) {
      return {'endedAt': endedAt, 'endReason': SessionEndReason.appKilled};
    }
    final tally =
        SessionTally.fromMap(data, endReason: SessionEndReason.recovered);
    return {
      'endedAt': endedAt,
      'endReason': SessionEndReason.recovered,
      'isValid': rules.isValid(tally),
    };
  }

  /// The [SessionEndSummary] for a recovered v2 row, or null when the row
  /// is pre-v2 / has no timestamps.
  static SessionEndSummary? recoveredSummary(
    String uid,
    String sessionId,
    Map<String, dynamic> data,
    SessionRules rules, {
    required DateTime now,
  }) {
    if (!rules.v2 || data['scheduleVersion'] != 2) return null;
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    final tally =
        SessionTally.fromMap(data, endReason: SessionEndReason.recovered);
    final started = ts(data['startedAt']) ?? now;
    final ended = ts(data['lastActivityAt']) ?? started;
    return SessionEndSummary(
      uid: uid,
      sessionId: (data['sessionId'] as String?) ?? sessionId,
      agentId: (data['agentId'] as String?) ?? '',
      tally: tally,
      isValid: rules.isValid(tally),
      endReason: SessionEndReason.recovered,
      startedAt: started,
      endedAt: ended,
      lastReplyAt: ts(data['lastReplyAt']),
    );
  }

  static Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatSessionRecorder] write failed: $e');
    }
  }

  static String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = (DateTime.now().hashCode & 0xffffff).toRadixString(36);
    return 's_$now$noise';
  }
}

/// Wraps a tool page (Action Loop / Thought Exercise / Education / Progress)
/// so a `users/{uid}/sessions` doc with `kind: tool` opens on entry and
/// closes on exit (M-7).  Resolves uid / analytics / availability from the
/// inherited scopes itself so call sites are a one-line wrap.
class ToolSessionScope extends StatefulWidget {
  final String toolId;
  final Widget child;

  const ToolSessionScope({super.key, required this.toolId, required this.child});

  @override
  State<ToolSessionScope> createState() => _ToolSessionScopeState();
}

class _ToolSessionScopeState extends State<ToolSessionScope> {
  DocumentReference<Map<String, dynamic>>? _ref;
  AnalyticsService? _analytics;
  String? _sessionId;
  DateTime? _startedAt;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _analytics = AnalyticsScope.of(context);
    final uid = AppSettingsScope.read(context).profile?.uid;
    final available = AuthServiceScope.of(context).available;
    _sessionId = ChatSessionRecorder._newId();
    _startedAt = DateTime.now();
    unawaited(_analytics!.logEvent(PhaseAEvents.sessionStart, {
      'sessionId': _sessionId,
      'toolId': widget.toolId,
    }));
    if (!available || uid == null) return;
    _ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(_sessionId);
    unawaited(ChatSessionRecorder._guard(() => _ref!.set({
          'participantId': uid,
          'sessionId': _sessionId,
          'kind': 'tool',
          'agentId': null,
          'toolId': widget.toolId,
          'startedAt': Timestamp.fromDate(_startedAt!),
          'lastActivityAt': Timestamp.fromDate(_startedAt!),
          'endedAt': null,
          'endReason': null,
        })));
  }

  @override
  void dispose() {
    final analytics = _analytics;
    if (analytics != null) {
      unawaited(analytics.logEvent(PhaseAEvents.sessionEnd, {
        'sessionId': _sessionId,
        'toolId': widget.toolId,
        'endReason': SessionEndReason.userLeft,
        'durationSeconds':
            DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds,
      }));
    }
    final ref = _ref;
    if (ref != null) {
      unawaited(ChatSessionRecorder._guard(() => ref.set({
            'endedAt': FieldValue.serverTimestamp(),
            'endReason': SessionEndReason.userLeft,
          }, SetOptions(merge: true))));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// T27 (SPEC:C18) — `voice_transcription_failed` in the session log.  Kept
/// as an extension at the end of the file so it merges cleanly with other
/// session work.  Payload: session id, companion, failure category, time.
/// No audio, no text.  Both arms identical.
extension VoiceTranscriptionFailureLog on ChatSessionRecorder {
  void logVoiceTranscriptionFailed(String category) {
    logEvent(
      VoiceTranscriptionFailedEvent.name,
      VoiceTranscriptionFailedEvent.payload(
        category: category,
        sessionId: sessionId,
        agentId: agentId,
      ),
    );
  }
}

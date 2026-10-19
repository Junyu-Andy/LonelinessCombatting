/// 1020 F (batch 2) — 小欣's one chat window, both arms, behind the remote
/// switch `app_config/feature_flags.checkInChatV2Enabled` (CheckInPage
/// picks it; off, CheckInArmA / CheckInArmB run exactly as before).
///
/// Today's check-in not done yet → it starts by itself inside the chat:
///   Q0 → Q1 → Q2 → Q3 → (Q3b when Q3 is 一啲小事 / 一件大事) → reply 1 →
///   Q4 → reply 2 → Q5 (好呀 opens the action plan; 唔使喇) → Q6,
/// as bubbles with button replies.  The questions, buttons and order come
/// from [CheckInChatCopy] in both arms — never from the LLM.  Only the two
/// replies differ:
///   - rule arm: reply 1 = X1–X5 by the Q1 band (5.4, no repeat of the last
///     few) or XG for 唔想答; reply 2 = R4a (answered) / R4b (唔講住).
///   - Hybrid: the LLM (prompt `siu_yan_v3`) — reply 1 from Q1–Q3 (+ Q3b),
///     reply 2 at most one or two places / ways for an answered Q4; for
///     唔講住 one sentence, no advice, no question (1020e 二.8), the fixed
///     R4b when the model fails.
/// Already done today → a plain chat: rule arm opens with SY0 and answers
/// from SY1–SY6 / SN1–SN4 ([SiuYanRuleChatPool]); Hybrid opens with an LLM
/// line and keeps the existing Siu Yan chat (thought-exercise offer,
/// cross-referral, cross-module callback, memory buffer).
///
/// 1020 E (batch 3, `moodRowV2Enabled`): opened from the mood row's M7 / M8
/// ([moodEntry]) → always the plain chat, never the check-in: the rule arm
/// opens with O1–O5 (by the mood) or C1 / C2 (the mood got better / worse)
/// and then answers from the same SY / SN pool (SN after O4, O5, C2); the
/// Hybrid arm's LLM opens, told the mood (and for M8 the change) and asked
/// to start by asking what happened (prompt `siu_yan.v4`, `[開場·心情]`).
///
/// Safety: Q3b, Q4 and every later message go through the same shared
/// check as any chat input (input point `chat_check_in` in both arms —
/// the Hybrid gateway uses it for `m2_check_in`).  Rule arm: a
/// moderate_review hit (grief, past hardship) gets an SN line (1020e 二.10);
/// moderate_interrupt and acute get no template and the safety flow runs.
/// Acute ends the check-in early (both arms); once the researcher marks the
/// alert a false alarm (誤觸), the same day's next visit resumes it at the
/// question where it stopped (1020e 二.9).
///
/// Records: `check_in_responses` ([CheckInChatRecord]); a completed
/// check-in marks its session valid ([ChatSessionRecorder.markCheckInCompleted]);
/// chatting on stays in that session, which ends by the usual rules.  The
/// Brief PR invitation then follows the usual rules (v2: the card on the
/// list page; never pushed straight after the check-in).
///
/// The rule arm never calls the LLM here: every model call sits behind
/// `!_ruleArm`, and the server refuses Arm B anyway.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/agent_context_service.dart';
import '../../../../core/agent_context/rolling_summary_compiler.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/companion_app_bar.dart';
import '../../../../core/agents/first_intro_overlay.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/connectivity/connectivity_service.dart';
import '../../../../core/connectivity/offline_pending_banner.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/cross_referral/referral_routing_service.dart';
import '../../../../core/cross_referral/referral_suggestion_card.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/memory/cross_module_memory.dart';
import '../../../../core/memory/memory_mode.dart';
import '../../../../core/privacy/shared_context_consent.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../../core/safety/safety_copy.dart';
import '../../../../core/scheduling/study_week.dart';
import '../../../../core/scheduling/w0_date.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../../shared/widgets/composer_send_button.dart';
import '../../../../shared/widgets/rich_chat_text.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_a_page.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_b_page.dart';
import '../../../adherence/data/adherence_check.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/data/brief_pr_v2.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../reflective_dialogue/data/negative_cognition_detector.dart';
import '../../../rule_replies/data/rule_reply_history_store.dart';
import '../../../rule_replies/data/rule_reply_picker.dart';
import '../../../rule_replies/data/rule_reply_pool.dart';
import '../../../thought_exercise/presentation/naming_thought_card.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../../../today/data/mood_recorder.dart';
import '../../../today/data/mood_row_copy.dart';
import '../../data/check_in_chat_copy.dart';
import '../../data/check_in_response_store.dart';
import '../../data/siu_yan_rule_chat_pool.dart';

class SiuYanChatPage extends StatefulWidget {
  const SiuYanChatPage({
    super.key,
    this.lowMoodEntry = false,
    this.moodEntry,
    this.checkedInToday,
    this.latestMoodToday,
    this.responseStore,
    this.replyHistory,
    this.clock,
    this.onOpenActionPlan,
    this.onPromptShown,
  });

  /// Opened from a low-mood opener (O4 / O5 / C2 — batch 3, 1020 E (5)):
  /// the rule arm answers from SN1–SN4.
  final bool lowMoodEntry;

  /// Opened from the mood row's M7 / M8 (1020 E (5)): the chat with a
  /// mood opener, not the check-in.
  final MoodChatEntry? moodEntry;

  /// Whether today's check-in is already done.  Default: the
  /// `check_in_submitted` event ([AdherenceCheck], as the status chip).
  final Future<bool> Function(String uid)? checkedInToday;

  /// Today's latest `daily_mood` (1..5), or null.  Default: [MoodRecorder].
  final Future<int?> Function(String uid)? latestMoodToday;

  /// Tests: defaults to Firestore.
  final CheckInResponseStore? responseStore;
  final RuleReplyHistoryStore? replyHistory;
  final DateTime Function()? clock;

  /// Tests: replaces pushing the action plan page after Q5 好呀.
  final Future<void> Function(BuildContext context)? onOpenActionPlan;

  /// Tests: every fixed question shown (id, text, button labels).
  final void Function(String id, String text, List<String> buttons)?
      onPromptShown;

  /// The prompt key the Hybrid calls send (functions/prompt_registry.js →
  /// `siu_yan.v3.txt`).
  static const String promptKey = 'siu_yan_v3';

  /// 1020 E: while `moodRowV2Enabled` is on, every Hybrid call of this
  /// window sends v4 (= v3 + the mood-opener section); off, v3 as before.
  static const String promptKeyMoodRow = 'siu_yan_v4';

  static String get activePromptKey =>
      RemoteFeatureFlags.current.moodRowV2Enabled ? promptKeyMoodRow : promptKey;

  /// Session moduleIds: the check-in session (type check-in), and a plain
  /// chat once today's check-in is done (type free chat, ≥3 replied
  /// messages to count).
  static const String checkInModule = 'm2_check_in';
  static const String chatModule = 'siu_yan_chat';

  @override
  State<SiuYanChatPage> createState() => _SiuYanChatPageState();
}

/// Where the window is.  `waiting` = between steps (no buttons, no box).
enum _Stage { resolving, q1, q2, q3, q3b, q4, q5, waiting, chat }

class _SiuYanChatPageState extends State<SiuYanChatPage> {
  /// Same client-side fallback as CheckInArmA (resolver unavailable).
  static const _fallbackPersonaPrompt = '''
你叫小欣，係一個 AI 機械人，唔係真人。每次回覆 1-2 句、reference 用戶啱啱講嘅
具體細節、不分析、不診斷、不重 frame、不建立依賴。
''';

  /// A short pause before a template line, as on Tung Tung's rule page,
  /// so the reply does not snap in under the elder's own bubble.
  static const _templatePause = Duration(milliseconds: 700);

  static const _siuYan = AgentRegistry.siuYanId;
  static const _negCogDetector = NegativeCognitionDetector();

  final _inputCtrl = TextEditingController();
  final _voice = VoiceInputController();
  final List<_Bubble> _bubbles = [];

  /// Elder messages whose exchange tripped a safety flag: kept on screen,
  /// left out of the memory summary.
  final Set<_Bubble> _safetyFlagged = Set.identity();
  final DateTime _openedAt = DateTime.now();

  final _connectivity = ConnectivityService();
  String? _pendingOffline;
  StreamSubscription<bool>? _connSub;

  _Stage _stage = _Stage.resolving;
  List<CheckInOption> _options = const [];
  bool _busy = false;
  bool _started = false;

  /// Fixed for the page's life, like Tung Tung's `_ruleBased`.
  bool _ruleArm = true;
  bool _available = false;
  String? _uid;
  bool _lowMood = false;

  CheckInChatRecord? _record;
  String? _recordId;
  bool _recordWritten = false;

  ChatSessionRecorder? _recorder;
  AnalyticsService? _analytics;
  bool _briefPrSurfaced = false;
  String? _closeReason;
  String get _exitReason => BriefPrV2.enabled
      ? (_closeReason ?? SessionEndReason.back)
      : SessionEndReason.userLeft;

  // T49e-3 memory hand-over (Hybrid), as CheckInArmA.
  bool _memoryHandedOver = false;
  bool _disposed = false;
  CoreServicesScope? _memCore;
  UserProfile? _memProfile;

  // Hybrid free chat, as CheckInArmA.
  bool _consentAsked = false;
  bool _crossModuleAsked = false;
  CrossModuleCallback? _crossModuleCallback;
  String? _pendingNamingThought;
  String? _pendingNamingInvitation;
  SurfacedReferral? _pendingReferral;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  CheckInResponseStore get _responses =>
      widget.responseStore ??
      FirestoreCheckInResponseStore(available: _available);

  RuleReplyHistoryStore get _replyHistory =>
      widget.replyHistory ??
      FirestoreRuleReplyHistoryStore(available: _available);

  bool get _inCheckIn =>
      _stage != _Stage.chat && _stage != _Stage.resolving;

  @override
  void initState() {
    super.initState();
    _connSub = _connectivity.onStatusChange.listen((online) {
      if (online && _pendingOffline != null && mounted) _resendPending();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
    _captureMemoryDeps();
    if (!_started) {
      _started = true;
      _ruleArm = !Arm.isA(context);
      _available = AuthServiceScope.of(context).available;
      _uid = AppSettingsScope.read(context).profile?.uid;
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _handOverMemory();
    _connSub?.cancel();
    _recorder?.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Start
  // ---------------------------------------------------------------------

  Future<void> _start() async {
    final uid = _uid;
    var done = false;
    int? mood;
    if (uid != null) {
      try {
        done = await (widget.checkedInToday ?? _defaultCheckedInToday)(uid);
      } catch (_) {}
      try {
        mood = await (widget.latestMoodToday ?? _defaultLatestMood)(uid);
      } catch (_) {}
    }
    if (!mounted) return;
    final entry = widget.moodEntry;
    _lowMood = SiuYanRuleChatPool.isLow(
        // From M7 / M8 the pick just made counts (its write may still be
        // on its way).
        latestMoodToday: entry?.mood ?? mood,
        lowMoodEntry: widget.lowMoodEntry || (entry?.lowOpener ?? false));
    if (entry != null) {
      // From M7 / M8: the chat, never the check-in (nor its resume).
      setState(() => _stage = _Stage.chat);
      await _seedMoodOpener(entry);
      return;
    }
    if (done) {
      setState(() => _stage = _Stage.chat);
      await _seedChatOpener();
      return;
    }
    // 1020e 二.9 — a crisis stop the researcher marked 誤觸 today: carry
    // on from the question where it stopped.
    final resume = uid == null ? null : await _findResumable(uid);
    if (!mounted) return;
    if (resume != null) {
      _resumeCheckIn(resume.$1, resume.$2, resume.$3);
    } else {
      _beginCheckIn();
    }
  }

  /// 1020e 二.9 — today's stopped chat check-in row that the researcher
  /// marked a false alarm (`falseAlarm: true`, server-written), not yet
  /// completed and not yet resumed: (id, row, stopped question).  Only
  /// today's rows are read, so nothing is resumed the next day.
  Future<(String, Map<String, dynamic>, String)?> _findResumable(
      String uid) async {
    Map<String, Map<String, dynamic>> rows;
    try {
      rows = await _responses.rowsForDay(
          uid: uid, dateIso: MoodRecorder.dateIsoFor(_now()));
    } catch (_) {
      return null;
    }
    final resumed = {
      for (final r in rows.values)
        if (r['resumed_from'] is String) r['resumed_from'] as String,
    };
    for (final e in rows.entries) {
      final r = e.value;
      if (r['flow'] != 'chat_v2' ||
          r['stopped_by_safety'] != true ||
          r['falseAlarm'] != true ||
          r['completed'] == true ||
          resumed.contains(e.key)) {
        continue;
      }
      final at = CheckInChatRecord.stoppedQuestionOf(r);
      if (at != null) return (e.key, r, at);
    }
    return null;
  }

  /// 1020e 二.9 — continue a stopped check-in: a new record carries the
  /// answers before [stoppedAt] (`resumed_from` = [id]); the stopped
  /// question is asked again, then the usual order.
  void _resumeCheckIn(String id, Map<String, dynamic> row, String stoppedAt) {
    final now = _now();
    _record = CheckInChatRecord.resumeOf(
      id: id,
      row: row,
      stoppedAt: stoppedAt,
      arm: _ruleArm ? 'B' : 'A',
      dateIso: MoodRecorder.dateIsoFor(now),
      copyVersion: CheckInChatCopy.version,
    );
    unawaited(_analytics?.logEvent('check_in_chat_resumed', {
          'stopped_at': stoppedAt,
        }) ??
        Future<void>.value());
    setState(() {
      if (stoppedAt == 'Q3b') {
        _ask(_Stage.q3b, 'Q3b', CheckInChatCopy.q3b, const []);
      } else {
        _ask(_Stage.q4, 'Q4', CheckInChatCopy.q4, const []);
      }
    });
  }

  Future<bool> _defaultCheckedInToday(String uid) =>
      AdherenceCheck(available: _available)
          .hasCheckedInToday(uid)
          .timeout(const Duration(seconds: 3), onTimeout: () => false);

  Future<int?> _defaultLatestMood(String uid) async {
    if (!_available) return null;
    final entry = await MoodRecorder()
        .latestForDate(uid: uid, dateIso: MoodRecorder.dateIsoFor(_now()))
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    return entry?.mood;
  }

  void _beginCheckIn() {
    final now = _now();
    final w0 = w0DateFor(AppSettingsScope.read(context).profile);
    final day = w0 == null ? null : studyDayOf(w0, now);
    _record = CheckInChatRecord(
      arm: _ruleArm ? 'B' : 'A',
      dateIso: MoodRecorder.dateIsoFor(now),
      copyVersion: CheckInChatCopy.version,
      studyDay: day,
      studyWeek: day == null ? null : studyWeekOf(day),
    );
    setState(() {
      _say('Q0', CheckInChatCopy.q0(now));
      _ask(_Stage.q1, 'Q1', CheckInChatCopy.q1, CheckInChatCopy.q1Options);
    });
  }

  /// Rule arm: SY0.  Hybrid: one LLM line; SY0 when the model fails.
  Future<void> _seedChatOpener() async {
    if (_ruleArm) {
      setState(() => _say('SY0', CheckInChatCopy.sy0));
      return;
    }
    setState(() => _busy = true);
    var text = CheckInChatCopy.sy0;
    var id = 'SY0';
    try {
      final r = await _callLlm(
        moduleId: 'greeting_$_siuYan',
        userInput: '（用戶打開咗同小欣嘅對話。）',
        history: const [],
        block: '[開場·check-in 已做]',
      );
      if (!r.isFallback && !r.hasEscalation && r.text.trim().isNotEmpty) {
        text = r.text.trim();
        id = 'llm_opener';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[siu_yan_chat] opener failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(text, copyId: id));
    });
  }

  /// 1020 E (5) — from M7 / M8.  Rule arm: O1–O5 / C1 / C2 (5.2), no LLM.
  /// Hybrid: one LLM line from the mood (and the change); the same 5.2
  /// line when the model fails.
  Future<void> _seedMoodOpener(MoodChatEntry entry) async {
    if (_ruleArm) {
      setState(() => _say(entry.openerId, entry.openerText));
      _logTemplate(entry.openerId, MoodRowCopy.version,
          theme: 'mood_opener', moduleId: SiuYanChatPage.chatModule);
      return;
    }
    setState(() => _busy = true);
    var text = entry.openerText;
    var id = entry.openerId;
    try {
      final r = await _callLlm(
        moduleId: 'greeting_$_siuYan',
        userInput: '（用戶喺首頁揀咗心情之後打開咗同小欣嘅對話。）',
        history: const [],
        block: entry.contextBlock,
      );
      if (!r.isFallback && !r.hasEscalation && r.text.trim().isNotEmpty) {
        text = r.text.trim();
        id = 'llm_opener';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[siu_yan_chat] mood opener failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(text, copyId: id));
    });
    widget.onPromptShown?.call(id, text, const []);
  }

  // ---------------------------------------------------------------------
  // Check-in script
  // ---------------------------------------------------------------------

  /// A fixed Siu Yan line (question or opener).  Call inside setState.
  void _say(String id, String text, [List<CheckInOption> options = const []]) {
    _bubbles.add(_Bubble.bot(text, copyId: id));
    if (id.startsWith('Q')) _record?.questionsShown.add(id);
    widget.onPromptShown?.call(id, text, [for (final o in options) o.label]);
  }

  /// Show a question and wait for its answer.  Call inside setState.
  void _ask(_Stage stage, String id, String text, List<CheckInOption> options) {
    _say(id, text, options);
    _stage = stage;
    _options = options;
  }

  static String _questionId(_Stage s) => switch (s) {
        _Stage.q1 => 'Q1',
        _Stage.q2 => 'Q2',
        _Stage.q3 => 'Q3',
        _Stage.q3b => 'Q3b',
        _Stage.q4 => 'Q4',
        _Stage.q5 => 'Q5',
        _ => '',
      };

  Future<void> _onOption(CheckInOption o) async {
    if (_busy) return;
    final stage = _stage;
    final qid = _questionId(stage);
    if (qid.isEmpty) return;
    setState(() {
      _stage = _Stage.waiting;
      _bubbles.add(_Bubble.user(o.label));
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    final answer = <String, dynamic>{
      'question_id': qid,
      'value': o.code,
      'label': o.label,
    };
    if (stage == _Stage.q1) answer['score'] = o.score;
    if (stage == _Stage.q2) {
      answer['index'] = CheckInChatCopy.q2Options.indexOf(o);
    }
    if (stage == _Stage.q3) {
      answer['index'] = CheckInChatCopy.q3Options.indexOf(o);
    }
    _record?.answers[qid] = answer;
    _persist();
    if (!mounted) return;
    if (stage == _Stage.q1) {
      setState(() => _ask(
          _Stage.q2, 'Q2', CheckInChatCopy.q2, CheckInChatCopy.q2Options));
    } else if (stage == _Stage.q2) {
      setState(() => _ask(
          _Stage.q3, 'Q3', CheckInChatCopy.q3, CheckInChatCopy.q3Options));
    } else if (stage == _Stage.q3) {
      if (CheckInChatCopy.q3OpensQ3b.contains(o.code)) {
        setState(() => _ask(_Stage.q3b, 'Q3b', CheckInChatCopy.q3b, const []));
      } else {
        await _reply1(null);
      }
    } else if (stage == _Stage.q5) {
      await _finishCheckIn(o);
    }
  }

  /// 唔講住 under Q3b / Q4.
  Future<void> _onSkip() async {
    if (_busy) return;
    final stage = _stage;
    if (stage != _Stage.q3b && stage != _Stage.q4) return;
    final qid = _questionId(stage);
    setState(() {
      _stage = _Stage.waiting;
      _bubbles.add(_Bubble.user(CheckInChatCopy.skipLabel));
      _inputCtrl.clear();
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    _record?.answers[qid] = {'question_id': qid, 'skipped': true, 'text': null};
    _persist();
    if (!mounted) return;
    if (stage == _Stage.q3b) {
      await _reply1(null);
    } else {
      await _reply2(null);
    }
  }

  /// Typed answer to Q3b / Q4.
  Future<void> _onFreeAnswer(String text) async {
    final stage = _stage;
    final qid = _questionId(stage);
    final sentAt = DateTime.now();
    final (usedVoice, voiceMs) = _voice.takeModality();
    final bubble = _Bubble.user(text, freeText: true);
    setState(() {
      _stage = _Stage.waiting;
      _bubbles.add(bubble);
      _inputCtrl.clear();
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    _record?.answers[qid] = {'question_id': qid, 'skipped': false, 'text': text};
    _persist();
    if (!mounted) return;
    final input = _FreeInput(
        text: text,
        bubble: bubble,
        sentAt: sentAt,
        voice: usedVoice,
        voiceMs: voiceMs);
    if (stage == _Stage.q3b) {
      await _reply1(input);
    } else {
      await _reply2(input);
    }
  }

  Future<void> _reply1(_FreeInput? input) async {
    final outcome = _ruleArm
        ? await _ruleCheckInReply(input, reply1: true)
        : await _hybridCheckInReply(input, block: _reply1Block());
    _record?.response1Id = outcome.id;
    if (outcome.stop) {
      _stopCheckInForSafety('Q3b');
      return;
    }
    _persist();
    if (!mounted) return;
    setState(() => _ask(_Stage.q4, 'Q4', CheckInChatCopy.q4, const []));
  }

  Future<void> _reply2(_FreeInput? input) async {
    final _ReplyOutcome outcome;
    if (input == null && _ruleArm) {
      // 唔講住, rule arm: the fixed R4b.
      outcome = await _fixedReply('R4b', CheckInChatCopy.r4b);
    } else if (input == null) {
      // 唔講住, Hybrid (1020e 二.8): one sentence from the model, no advice,
      // no question; R4b when the model fails.
      outcome = await _hybridSkipReply();
    } else if (_ruleArm) {
      outcome = await _ruleCheckInReply(input, reply1: false);
    } else {
      outcome = await _hybridCheckInReply(input, block: _reply2Block());
    }
    _record?.response2Id = outcome.id;
    if (outcome.stop) {
      _stopCheckInForSafety('Q4');
      return;
    }
    _persist();
    if (!mounted) return;
    setState(() => _ask(
        _Stage.q5, 'Q5', CheckInChatCopy.q5, CheckInChatCopy.q5Options));
  }

  /// Q5 answered: the check-in is complete (one valid session), then the
  /// action plan (好呀) and Q6; the window stays open for chatting.
  Future<void> _finishCheckIn(CheckInOption q5) async {
    final record = _record;
    if (record != null) {
      record.completed = true;
    }
    _recorder?.markCheckInCompleted();
    _persist();
    _logCheckInEvent();
    if (q5.code == 'yes') await _openActionPlan();
    if (!mounted) return;
    setState(() {
      _say('Q6', CheckInChatCopy.q6);
      _stage = _Stage.chat;
    });
    _persist();
  }

  /// Acute: the check-in ends at [at] (Q3b / Q4); a 誤觸 mark lets the
  /// same day's next visit resume there (1020e 二.9).
  void _stopCheckInForSafety(String at) {
    _record?.stoppedBySafety = true;
    _record?.stoppedAt = at;
    _persist();
    if (mounted) setState(() => _stage = _Stage.chat);
  }

  Future<void> _openActionPlan() async {
    final hook = widget.onOpenActionPlan;
    if (hook != null) {
      await hook(context);
      return;
    }
    // The same planner the 小行動 page opens (Arm A: LLM-assisted, Arm B:
    // template), as an M-7 tool session.
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ToolSessionScope(
        toolId: 'action_loop',
        child: _ruleArm
            ? const ActionLoopArmBPage()
            : const ActionLoopArmAPage(),
      ),
    ));
  }

  void _persist() {
    final record = _record;
    final uid = _uid;
    if (record == null || uid == null) return;
    record.sessionId = _recorder?.sessionId ?? record.sessionId;
    final store = _responses;
    final id = _recordId ??= store.newId();
    final first = !_recordWritten;
    _recordWritten = true;
    unawaited(store.write(uid: uid, id: id, data: record.toMap(), first: first));
  }

  void _logCheckInEvent() {
    final record = _record;
    if (record == null) return;
    final a = record.answers;
    final score = a['Q1']?['score'];
    String freeState(String q) => !a.containsKey(q)
        ? 'not_asked'
        : (a[q]!['skipped'] == true ? 'skipped' : 'answered');
    unawaited(_analytics?.logCheckInChat({
          'flow': 'chat_v2',
          if (score is int) 'mood': score,
          'q1': a['Q1']?['value'],
          'q2': a['Q2']?['value'],
          'q3': a['Q3']?['value'],
          'q3b': freeState('Q3b'),
          'q4': freeState('Q4'),
          'q5': a['Q5']?['value'],
          'response1_id': record.response1Id,
          'response2_id': record.response2Id,
          'study_week': record.studyWeek,
        }) ??
        Future<void>.value());
  }

  // ---------------------------------------------------------------------
  // Replies: rule arm (templates, no LLM)
  // ---------------------------------------------------------------------

  Future<_ReplyOutcome> _ruleCheckInReply(
    _FreeInput? input, {
    required bool reply1,
  }) async {
    var flag = const DistressMatch(DistressLevel.none);
    String? turnId;
    if (input != null) {
      setState(() => _busy = true);
      (flag, turnId) = await _ruleSafety(input.text);
      if (!mounted) return const _ReplyOutcome('none_safety', stop: true);
      if (flag.level == DistressLevel.acute) {
        await _ruleAcute(input, flag, turnId);
        return const _ReplyOutcome('none_safety', stop: true);
      }
      if (!_ruleAllowsReply(flag)) {
        await _ruleNoTemplate(input, flag, turnId);
        return const _ReplyOutcome('none_safety');
      }
    }
    setState(() => _busy = true);
    await Future<void>.delayed(_templatePause);
    if (!mounted) return const _ReplyOutcome('none', stop: true);
    // 1020e 二.10: a moderate_review hit (grief, past hardship) gets an SN
    // low-mood line instead of the X / R4a template.
    final (RuleReplyEntry, String) picked =
        flag.level == DistressLevel.moderateReview
            ? (await _pickChatLine(low: true), SiuYanRuleChatPool.version)
            : reply1
                ? await _pickReply1()
                : (
                    (
                      id: 'R4a',
                      agent: _siuYan,
                      band: 'none',
                      zh: CheckInChatCopy.r4a,
                    ),
                    CheckInChatCopy.version,
                  );
    final entry = picked.$1;
    final version = picked.$2;
    if (!mounted) return const _ReplyOutcome('none', stop: true);
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(entry.zh, copyId: entry.id));
    });
    final turnDocId = await _logTurn(
      input: input,
      flag: flag,
      response: _ruleResponse(entry.zh, flag, turnId),
    );
    _logTemplate(entry.id, version, theme: 'check_in_chat', band: entry.band);
    if (mounted && flag.level != DistressLevel.none) {
      await _route(flag, turnDocId);
    }
    return _ReplyOutcome(entry.id);
  }

  /// Reply 1: the 5.4 group of the Q1 band, first entry not used in the
  /// last few check-ins; XG for 唔想答.
  Future<(RuleReplyEntry, String)> _pickReply1() async {
    final band = _record?.answers['Q1']?['value'] as String?;
    final pool = band == null ? const <RuleReplyEntry>[] : RuleReplyPool.checkInChatSubPool(band);
    if (pool.isEmpty) {
      return (
        (id: 'XG', agent: _siuYan, band: 'none', zh: CheckInChatCopy.xg),
        CheckInChatCopy.version,
      );
    }
    final store = _replyHistory;
    final recent = await store.recent(uid: _uid, agentId: _siuYan);
    final entry = RuleReplyPicker.pick(pool, recent)!;
    unawaited(store.save(
      uid: _uid,
      agentId: _siuYan,
      recent: RuleReplyPicker.remember(recent, entry.id),
    ));
    return (entry, RuleReplyPool.checkInChatVersion);
  }

  /// A fixed line with no model call (R4b, both arms).
  Future<_ReplyOutcome> _fixedReply(String id, String text) async {
    setState(() => _busy = true);
    await Future<void>.delayed(_templatePause);
    if (!mounted) return _ReplyOutcome(id, stop: true);
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(text, copyId: id));
    });
    const none = DistressMatch(DistressLevel.none);
    await _logTurn(
      input: null,
      flag: none,
      response: _ruleArm
          ? _ruleResponse(text, none, null)
          : LlmResponse(
              text: text,
              inputFlag: none,
              outputFlag: none,
              shortCircuited: false,
              metadata: TurnMetadata(
                  agentId: _siuYan, sessionId: _recorder?.sessionId),
              status: LlmStatus.fixedReply,
            ),
    );
    if (_ruleArm) _logTemplate(id, CheckInChatCopy.version, theme: 'check_in_chat');
    return _ReplyOutcome(id);
  }

  /// Rule arm free chat: SY / SN line, or the safety flow.
  Future<void> _sendRuleChat(String text) async {
    final sentAt = DateTime.now();
    final (usedVoice, voiceMs) = _voice.takeModality();
    final bubble = _Bubble.user(text, freeText: true);
    setState(() {
      _busy = true;
      _bubbles.add(bubble);
      _inputCtrl.clear();
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    final input = _FreeInput(
        text: text,
        bubble: bubble,
        sentAt: sentAt,
        voice: usedVoice,
        voiceMs: voiceMs);
    final (flag, turnId) = await _ruleSafety(text);
    if (!mounted) return;
    if (flag.level == DistressLevel.acute) {
      await _ruleAcute(input, flag, turnId);
      return;
    }
    if (!_ruleAllowsReply(flag)) {
      await _ruleNoTemplate(input, flag, turnId);
      return;
    }
    await Future<void>.delayed(_templatePause);
    if (!mounted) return;
    // 1020e 二.10: moderate_review → an SN line, whatever today's mood.
    final entry = await _pickChatLine(
        low: _lowMood || flag.level == DistressLevel.moderateReview);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(entry.zh, copyId: entry.id));
    });
    final turnDocId = await _logTurn(
      input: input,
      flag: flag,
      response: _ruleResponse(entry.zh, flag, turnId),
    );
    _logTemplate(entry.id, SiuYanRuleChatPool.version,
        theme: 'free_chat', band: entry.band);
    if (mounted && flag.level != DistressLevel.none) {
      await _route(flag, turnDocId);
    }
  }

  /// 1020e 二.10 — which safety hits still get a rule-arm line: none, low
  /// and moderate_review (grief / past hardship; logged, no pop-up — the
  /// line is from SN).  moderate_interrupt and acute get no template; the
  /// safety flow runs.  (`allowsTemplateReply` in rule_replies is the old
  /// forms' rule and stays as it is.)
  static bool _ruleAllowsReply(DistressMatch flag) =>
      flag.level == DistressLevel.none ||
      flag.level == DistressLevel.low ||
      flag.level == DistressLevel.moderateReview;

  /// The next SY (or SN when [low]) line, rotated through
  /// `rule_reply_history/siu_yan_chat`.
  Future<RuleReplyEntry> _pickChatLine({required bool low}) async {
    final store = _replyHistory;
    final recent =
        await store.recent(uid: _uid, agentId: SiuYanRuleChatPool.historyKey);
    final entry = SiuYanRuleChatPool.pick(low: low, recent: recent);
    unawaited(store.save(
      uid: _uid,
      agentId: SiuYanRuleChatPool.historyKey,
      recent: SiuYanRuleChatPool.remember(recent, entry.id),
    ));
    return entry;
  }

  /// The shared safety check (T7) — same input point as the Hybrid
  /// gateway's `m2_check_in`; the classifier only when its switch is on.
  Future<(DistressMatch, String)> _ruleSafety(String text) async {
    final safety = CoreServicesScope.of(context).safety;
    const point = SafetyInputPoint.chatCheckIn;
    final turnId = SafetyService.newTurnId();
    if (safety.classifierActiveFor(point)) {
      final r = await safety.checkUserTextClassified(text,
          point: point,
          uid: _uid,
          agentId: _siuYan,
          sessionId: _recorder?.sessionId,
          turnId: turnId);
      return (r.match, turnId);
    }
    final r = safety.checkUserText(text,
        point: point,
        uid: _uid,
        agentId: _siuYan,
        sessionId: _recorder?.sessionId,
        turnId: turnId);
    return (r.match, turnId);
  }

  /// Acute: the safety template instead of any reply, session ends
  /// `crisis`, crisis page (as every chat page, both arms).
  Future<void> _ruleAcute(
      _FreeInput input, DistressMatch flag, String turnId) async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final core = CoreServicesScope.of(context);
    _safetyFlagged.add(input.bubble);
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.system(SafetyCopy.acuteAck(_siuYan, isEn: isEn)));
    });
    unawaited(_logTurn(
      input: input,
      flag: flag,
      response: _ruleResponse('', flag, turnId, acute: true),
      shortCircuited: true,
      ackShown: true,
    ));
    unawaited(_recorder?.end(SessionEndReason.crisis));
    if (!mounted) return;
    await core.distressRouter.route(flag, context: context);
  }

  /// Moderate: no template (rule-templates.md rule 4); the support line
  /// for moderate_interrupt, then the safety flow.
  Future<void> _ruleNoTemplate(
      _FreeInput input, DistressMatch flag, String turnId) async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final ack =
        flag.interrupts ? SafetyCopy.moderateAck(_siuYan, isEn: isEn) : null;
    _safetyFlagged.add(input.bubble);
    setState(() {
      _busy = false;
      if (ack != null) _bubbles.add(_Bubble.system(ack));
    });
    final turnDocId = await _logTurn(
      input: input,
      flag: flag,
      response: _ruleResponse('', flag, turnId),
      ackShown: ack != null,
    );
    if (mounted) await _route(flag, turnDocId);
  }

  LlmResponse _ruleResponse(String text, DistressMatch flag, String? turnId,
          {bool acute = false}) =>
      LlmResponse(
        text: text,
        inputFlag: flag,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: acute,
        metadata: TurnMetadata(agentId: _siuYan, sessionId: _recorder?.sessionId),
        status: acute ? LlmStatus.shortCircuited : LlmStatus.ruleBased,
        turnId: turnId,
      );

  void _logTemplate(String id, String version,
      {required String theme, String? band, String? moduleId}) {
    unawaited(_analytics?.logEvent('rule_template_reply', {
          'agent_id': _siuYan,
          'module_id': moduleId ??
              _recorder?.moduleId ??
              SiuYanChatPage.checkInModule,
          'template_id': id,
          'pool_version': version,
          'theme': theme,
          if (band != null) 'mood_band': band,
        }) ??
        Future<void>.value());
  }

  // ---------------------------------------------------------------------
  // Replies: Hybrid arm (LLM)
  // ---------------------------------------------------------------------

  String _answerLines() {
    final a = _record?.answers ?? const <String, Map<String, dynamic>>{};
    String label(String q) => (a[q]?['label'] as String?) ?? '（未答）';
    return [
      'Q1 尋日成日整體過得點：${label('Q1')}',
      'Q2 尋日有冇同人傾過偈：${label('Q2')}',
      'Q3 尋日有冇咩特別事：${label('Q3')}',
      if (a.containsKey('Q3b'))
        a['Q3b']!['skipped'] == true
            ? 'Q3b 係咩事：（用戶揀咗「唔講住」）'
            : 'Q3b 係咩事：（見用戶寫嘅字）',
    ].join('\n');
  }

  String _reply1Block() => '[簽到·回應一]\n${_answerLines()}';

  String _reply2Block() =>
      '[簽到·回應二]\n${_answerLines()}\nQ4 今日有咩打算：（見用戶最後一句）';

  /// 1020e 二.8 — Q4 唔講住 (Hybrid): one sentence, no advice, no question.
  String _skipBlock() =>
      '[簽到·唔講住]\n${_answerLines()}\nQ4 今日有咩打算：（用戶揀咗「唔講住」）';

  /// After the check-in, the free-chat calls carry today's answers.
  String? _todayBlock() {
    final record = _record;
    if (record == null || !record.completed) return null;
    final q4 = record.answers['Q4'];
    return '[今日 check-in]\n${_answerLines()}\n'
        'Q4 今日有咩打算：${q4?['skipped'] == true ? '（唔講住）' : '（佢講過，見對話）'}';
  }

  /// The transcript as alternating model turns (system safety lines left
  /// out, consecutive lines of one side joined) — bubbles before [end].
  List<LlmTurn> _history(int end) {
    final out = <LlmTurn>[];
    for (final b in _bubbles.take(end)) {
      if (b.isSystem) continue;
      if (out.isNotEmpty && out.last.fromUser == b.fromUser) {
        final last = out.removeLast();
        out.add(LlmTurn(fromUser: b.fromUser, text: '${last.text}\n${b.text}'));
      } else {
        out.add(LlmTurn(fromUser: b.fromUser, text: b.text));
      }
    }
    return out;
  }

  Future<LlmResponse> _callLlm({
    required String moduleId,
    required String userInput,
    required List<LlmTurn> history,
    String? block,
  }) async {
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final persona = await core.personaResolver.resolve(
      agentId: _siuYan,
      profile: profile,
      includeSharedMood: true,
    );
    final cross =
        _crossModuleCallback?.toSystemPromptInjection(isEn: isEn) ?? '';
    final suffix = [
      if (persona?.contextSuffix != null) persona!.contextSuffix!,
      if (cross.trim().isNotEmpty) cross.trim(),
      if (profile?.avoidTopics?.isNotEmpty == true)
        '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：${profile!.avoidTopics}',
      if (block != null) block,
    ].join('\n\n').trim();
    return core.llm.send(
      moduleId: moduleId,
      promptKey: SiuYanChatPage.activePromptKey,
      agentId: _siuYan,
      systemPrompt: persona == null ? _fallbackPersonaPrompt : null,
      contextSuffix: suffix.isEmpty ? null : suffix,
      agentContextSnapshot: persona?.agentContextSnapshot,
      history: history,
      userInput: userInput,
      uid: profile?.uid,
      sessionId: _recorder?.sessionId,
    );
  }

  Future<void> _maybeConsent() async {
    if (_consentAsked) return;
    _consentAsked = true;
    await TranscriptConsentPrompter.maybePrompt(
      context: context,
      moduleKey: SiuYanChatPage.checkInModule,
    );
  }

  /// Reply 1 / reply 2 from the model.  Typed words go through the
  /// gateway's safety check as any chat message.  A button-only turn sends
  /// the button's label (fixed words that match no lexicon term — tested),
  /// so the gateway still scans the model's reply as on every Hybrid turn.
  Future<_ReplyOutcome> _hybridCheckInReply(
    _FreeInput? input, {
    required String block,
  }) async {
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() => _busy = true);
    if (input != null) {
      await _maybeConsent();
      if (!mounted) return const _ReplyOutcome('none', stop: true);
    }
    final List<LlmTurn> history;
    final String userInput;
    if (input != null) {
      history = _history(_bubbles.indexOf(input.bubble));
      userInput = input.text;
    } else {
      final lastBot = _bubbles.lastIndexWhere((b) => !b.fromUser && !b.isSystem);
      history = _history(lastBot + 1);
      userInput = _bubbles
          .skip(lastBot + 1)
          .where((b) => b.fromUser)
          .map((b) => b.text)
          .join('\n');
    }
    final response = await _callLlm(
      moduleId: SiuYanChatPage.checkInModule,
      userInput: userInput,
      history: history,
      block: block,
    );
    if (input != null) {
      await _appendToBuffer(fromUser: true, text: input.text, response: response);
    }
    if (!mounted) return const _ReplyOutcome('none', stop: true);
    if (response.shortCircuited) {
      if (input != null) _safetyFlagged.add(input.bubble);
      setState(() {
        _busy = false;
        _bubbles.add(_Bubble.system(SafetyCopy.acuteAck(_siuYan, isEn: isEn)));
      });
      unawaited(_logTurn(
        input: input,
        flag: response.inputFlag,
        response: response,
        shortCircuited: true,
        ackShown: true,
      ));
      unawaited(_recorder?.end(SessionEndReason.crisis));
      await core.distressRouter.route(response.inputFlag, context: context);
      return const _ReplyOutcome('none_safety', stop: true);
    }
    final replyText = response.isFallback
        ? SafetyCopy.llmFallback(_siuYan, isEn: isEn)
        : response.text;
    final escalation = _higher(response.inputFlag, response.outputFlag);
    final ack = escalation.interrupts
        ? SafetyCopy.moderateAck(_siuYan, isEn: isEn)
        : null;
    if (response.hasEscalation && input != null) _safetyFlagged.add(input.bubble);
    final id = response.isFallback ? 'llm_fallback' : 'llm';
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(replyText,
          copyId: id, promptHash: response.metadata.systemPromptHash));
      if (ack != null) _bubbles.add(_Bubble.system(ack));
    });
    final turnDocId = await _logTurn(
      input: input,
      flag: escalation,
      response: response,
      ackShown: ack != null,
    );
    await _appendToBuffer(fromUser: false, text: response.text, response: response);
    if (mounted && escalation.level != DistressLevel.none) {
      await _route(escalation, turnDocId);
    }
    return _ReplyOutcome(id);
  }

  /// 1020e 二.8 — Hybrid reply 2 when Q4 was 唔講住: the model writes one
  /// sentence (`[簽到·唔講住]`, prompt v3 — v4 with the mood row on, same
  /// rule: no advice, no question).  A
  /// failed call, an empty answer or a reply that tripped the safety scan
  /// is replaced by the fixed R4b (`response2_id: llm_fallback`); the
  /// flagged text is never shown, so no support page opens for it (the
  /// gateway still wrote its safety event).  The turn sent is the button
  /// 唔講住, as for every button-only Hybrid turn.
  Future<_ReplyOutcome> _hybridSkipReply() async {
    setState(() => _busy = true);
    final lastBot =
        _bubbles.lastIndexWhere((b) => !b.fromUser && !b.isSystem);
    final history = _history(lastBot + 1);
    final userInput = _bubbles
        .skip(lastBot + 1)
        .where((b) => b.fromUser)
        .map((b) => b.text)
        .join('\n');
    LlmResponse? response;
    try {
      response = await _callLlm(
        moduleId: SiuYanChatPage.checkInModule,
        userInput: userInput,
        history: history,
        block: _skipBlock(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[siu_yan_chat] 唔講住 reply failed: $e');
    }
    if (!mounted) return const _ReplyOutcome('none', stop: true);
    final r = response;
    final ok = r != null &&
        !r.isFallback &&
        !r.shortCircuited &&
        !r.hasEscalation &&
        r.text.trim().isNotEmpty;
    final text = ok ? r.text.trim() : CheckInChatCopy.r4b;
    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(text,
          copyId: ok ? 'llm' : 'R4b',
          promptHash: r?.metadata.systemPromptHash));
    });
    const none = DistressMatch(DistressLevel.none);
    await _logTurn(
      input: null,
      flag: r == null ? none : _higher(r.inputFlag, r.outputFlag),
      response: r ??
          LlmResponse(
            text: '',
            inputFlag: none,
            outputFlag: none,
            shortCircuited: false,
            metadata: TurnMetadata(
                agentId: _siuYan, sessionId: _recorder?.sessionId),
            status: LlmStatus.fallback,
            error: 'client_error',
          ),
    );
    if (ok) await _appendToBuffer(fromUser: false, text: text, response: r);
    return _ReplyOutcome(ok ? 'llm' : 'llm_fallback');
  }

  /// The existing Siu Yan chat (CheckInArmA `_sendInner`), after the
  /// check-in or when it was already done.
  Future<void> _sendHybridChat(String text) async {
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    await _maybeConsent();
    if (!mounted) return;
    final sentAt = DateTime.now();
    final (usedVoice, voiceMs) = _voice.takeModality();
    final bubble = _Bubble.user(text, freeText: true);
    setState(() {
      _busy = true;
      _bubbles.add(bubble);
      _inputCtrl.clear();
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    final input = _FreeInput(
        text: text,
        bubble: bubble,
        sentAt: sentAt,
        voice: usedVoice,
        voiceMs: voiceMs);

    // Cross-module callback (Layer 3) on the first chat message, as
    // CheckInArmA; skipped when sharedContextUse consent is off.
    if (!_crossModuleAsked &&
        profile != null &&
        SharedContextConsent.allowsCrossAgent(profile)) {
      _crossModuleAsked = true;
      final inputFlag = core.distress.analyze(text);
      _crossModuleCallback = await core.crossModuleMemory.getEligibleCallback(
        uid: profile.uid,
        forModuleFamily: 'm2',
        candidateSourceModuleIds: const [
          'm3_reminiscence_w4',
          'm3_reminiscence_w3',
          'm3_reminiscence_w2',
          'm3_reminiscence_w1',
        ],
        currentTurnDistress: inputFlag.level,
      );
      if (_crossModuleCallback != null) {
        await core.crossModuleMemory.markUsed(
          uid: profile.uid,
          forModuleFamily: 'm2',
          callback: _crossModuleCallback!,
        );
      }
      if (!mounted) return;
    }

    final response = await _callLlm(
      moduleId: SiuYanChatPage.checkInModule,
      userInput: text,
      history: _history(_bubbles.indexOf(bubble)),
      block: _todayBlock(),
    );
    await _appendToBuffer(fromUser: true, text: text, response: response);
    if (!mounted) return;
    if (response.shortCircuited) {
      _safetyFlagged.add(bubble);
      setState(() {
        _busy = false;
        _bubbles.add(_Bubble.system(SafetyCopy.acuteAck(_siuYan, isEn: isEn)));
      });
      unawaited(_logTurn(
        input: input,
        flag: response.inputFlag,
        response: response,
        shortCircuited: true,
        ackShown: true,
      ));
      unawaited(_recorder?.end(SessionEndReason.crisis));
      await core.distressRouter.route(response.inputFlag, context: context);
      return;
    }

    final replyText = response.isFallback
        ? SafetyCopy.llmFallback(_siuYan, isEn: isEn)
        : response.text;
    final escalation = _higher(response.inputFlag, response.outputFlag);
    final ack = escalation.interrupts
        ? SafetyCopy.moderateAck(_siuYan, isEn: isEn)
        : null;
    if (response.hasEscalation) _safetyFlagged.add(bubble);

    // Phase A spec §2.6 — Siu Yan's Thought Exercise offer.
    String? teOfferText;
    NegativeCognitionMatch? namingMatch;
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation &&
        !response.isFallback) {
      namingMatch = _negCogDetector.scan(text);
      if (namingMatch != null) {
        teOfferText =
            NamingThoughtCard.invitationText(namingMatch.fullTurn, isEn: isEn);
      }
    }

    setState(() {
      _busy = false;
      _bubbles.add(_Bubble.bot(replyText,
          copyId: response.isFallback ? 'llm_fallback' : 'llm',
          promptHash: response.metadata.systemPromptHash));
      if (ack != null) _bubbles.add(_Bubble.system(ack));
    });
    final turnDocId = await _logTurn(
      input: input,
      flag: escalation,
      response: response,
      ackShown: ack != null,
      teOfferText: teOfferText,
    );
    await _appendToBuffer(fromUser: false, text: response.text, response: response);
    if (!mounted) return;
    if (escalation.level != DistressLevel.none) {
      await _route(escalation, turnDocId);
    }
    if (!mounted) return;

    if (namingMatch != null && teOfferText != null) {
      setState(() {
        _pendingNamingThought = namingMatch!.fullTurn;
        _pendingNamingInvitation = teOfferText;
      });
      _recorder?.logEvent(PhaseAEvents.teOffer, {
        'turnId': turnDocId,
        'offerText': teOfferText,
      });
    }

    // Cross-referral routing (Sprint 5), as CheckInArmA.
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      core.referralRouting.onUserTurn(_siuYan);
      final surfaced = await core.referralRouting.maybeSurface(
        sourceAgentId: _siuYan,
        profile: profile,
        userTurn: text,
        recentTurns: _history(_bubbles.length),
        localeCode: isEn ? 'en' : 'zh',
      );
      if (mounted && surfaced != null) {
        setState(() => _pendingReferral = surfaced);
        final target = surfaced.match.trigger.targetAgentId;
        unawaited(_recorder?.updateTurn(turnDocId, {
          'referral': {'offered': true, 'target': target},
        }));
        _recorder?.logEvent(PhaseAEvents.referralOffered, {
          'turnId': turnDocId,
          'target': target,
        });
      }
    }
  }

  /// Siu Yan's short-term buffer (memory), Hybrid only, as CheckInArmA:
  /// never a safety-flagged exchange, never a fallback line.
  Future<void> _appendToBuffer({
    required bool fromUser,
    required String text,
    required LlmResponse response,
  }) async {
    final core = _memCore;
    final profile = _memProfile;
    if (_ruleArm || core == null || profile == null) return;
    if (text.trim().isEmpty || response.hasEscalation) return;
    if (!fromUser && response.isFallback) return;
    if (!profile.consent.transcriptRetentionFor(_siuYan)) return;
    try {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: _siuYan,
        turn: AgentContextTurn(
          fromUser: fromUser,
          text: text,
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _acceptNaming() async {
    final thought = _pendingNamingThought;
    final invitation = _pendingNamingInvitation;
    if (thought == null) return;
    final profile = AppSettingsScope.read(context).profile;
    setState(() {
      _pendingNamingThought = null;
      _pendingNamingInvitation = null;
    });
    _recorder?.logEvent(PhaseAEvents.teAccept, {'offerText': invitation});
    await AnalyticsScope.of(context)
        .logM5ThoughtExerciseOpened(origin: 'siu_yan_offer');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThoughtExercisePage(
          initialThought: thought,
          agentId: _siuYan,
          agentInvitationText: invitation,
          originTurnRef: profile != null
              ? 'users/${profile.uid}/agent_contexts/$_siuYan'
              : null,
        ),
      ),
    );
  }

  void _declineNaming() {
    _recorder?.logEvent(PhaseAEvents.teDecline, {
      'offerText': _pendingNamingInvitation,
    });
    setState(() {
      _pendingNamingThought = null;
      _pendingNamingInvitation = null;
    });
  }

  DistressMatch _higher(DistressMatch a, DistressMatch b) =>
      a.level.index >= b.level.index ? a : b;

  // ---------------------------------------------------------------------
  // Shared: composer, safety routing, session, memory, Brief PR
  // ---------------------------------------------------------------------

  void _resendPending() {
    final t = _pendingOffline;
    if (t == null) return;
    setState(() => _pendingOffline = null);
    _inputCtrl.text = t;
    _send();
  }

  /// Wrapper so any throw cannot strand `_busy = true`.
  Future<void> _send() async {
    try {
      await _sendInner();
    } catch (e) {
      if (kDebugMode) debugPrint('[siu_yan_chat] send failed: $e');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _sendInner() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    if (_stage == _Stage.q3b || _stage == _Stage.q4) {
      await _onFreeAnswer(text);
      return;
    }
    if (_stage != _Stage.chat) return;
    // Offline: hold the message and send it on reconnect (both arms, as
    // Tung Tung).
    if (!await _connectivity.isOnline()) {
      if (!mounted) return;
      setState(() {
        _pendingOffline =
            _pendingOffline == null ? text : '$_pendingOffline\n$text';
        _inputCtrl.clear();
      });
      return;
    }
    if (_ruleArm) {
      await _sendRuleChat(text);
    } else {
      await _sendHybridChat(text);
    }
  }

  Future<void> _route(DistressMatch flag, String? turnDocId) async {
    if (!mounted) return;
    await CoreServicesScope.of(context).distressRouter.route(
          flag,
          context: context,
          onModerateSheetShown: () =>
              _recorder?.logEvent(PhaseAEvents.moderateSheetShown, {
            'turnId': turnDocId,
            'matchedTerm': flag.matchedTerm,
          }),
        );
  }

  Future<String?> _logTurn({
    required _FreeInput? input,
    required DistressMatch flag,
    required LlmResponse response,
    bool shortCircuited = false,
    bool ackShown = false,
    String? teOfferText,
  }) async {
    final rec = _recorder;
    if (rec == null) return null;
    return rec.logTurn(TurnRecord(
      agentId: _siuYan,
      moduleId: rec.moduleId,
      userSent: input?.sentAt ?? DateTime.now(),
      replyShown: DateTime.now(),
      modality: input?.voice == true ? InputModality.voice : InputModality.text,
      voiceDurationMs: input?.voiceMs,
      charCount: input?.text.length ?? 0,
      detector: flag,
      shortCircuited: shortCircuited,
      ackShown: ackShown,
      response: response,
      teOfferText: teOfferText,
    ));
  }

  /// Opens (or reopens, after a timeout / crisis) the agent session.  The
  /// check-in session is type check-in; once the check-in is over and that
  /// session has ended, a new one is a plain chat.
  Future<void> _ensureSession() async {
    final current = _recorder;
    if (current != null && current.isOpen) return;
    final module = _inCheckIn
        ? SiuYanChatPage.checkInModule
        : SiuYanChatPage.chatModule;
    if (current == null || current.moduleId != module) {
      current?.dispose();
      _recorder = ChatSessionRecorder(
        uid: _uid,
        agentId: _siuYan,
        moduleId: module,
        analytics: _analytics!,
        available: _available,
        onIdleTimeout: _onIdleTimeout,
        onSwitchedAway: _onSwitchedAway,
      );
      // T27 — a failed transcription goes into this session's log.
      _voice.onTranscriptionFailed =
          (c) => _recorder?.logVoiceTranscriptionFailed(c);
    }
    await _recorder!.ensureStarted();
    _memoryHandedOver = false;
    _briefPrSurfaced = false;
  }

  void _captureMemoryDeps() {
    if (!mounted || _disposed) return;
    _memCore = CoreServicesScope.of(context);
    _memProfile = AppSettingsScope.read(context).profile;
  }

  /// T49e-3 — hand the session to memory once per session end (Hybrid
  /// only; the rule arm has no memory).
  void _handOverMemory() {
    _captureMemoryDeps();
    if (_memoryHandedOver || _ruleArm) return;
    final core = _memCore;
    final profile = _memProfile;
    if (core == null || profile == null || _recorder?.sessionId == null) {
      return;
    }
    _memoryHandedOver = true;
    unawaited(RollingSummaryCompiler(
      agentContext: core.agentContext,
      llm: core.llm,
      memoryV1Service: core.memoryV1,
    ).compileAtSessionEnd(
      uid: profile.uid,
      agentId: _siuYan,
      retentionOn: profile.consent.transcriptRetentionFor(_siuYan),
      memoryV1: MemoryModes.of(profile).isV1,
    ));
  }

  /// Hybrid, as CheckInArmA `_saveSession`: the elder's typed words (not
  /// the safety-flagged ones) as the `m2_check_in` summary M6 reads.
  void _writeMemorySummary() {
    final core = _memCore;
    final profile = _memProfile;
    if (_ruleArm || core == null || profile == null) return;
    final summary = _bubbles
        .where((b) => b.fromUser && b.freeText && !_safetyFlagged.contains(b))
        .map((b) => b.text)
        .join('\n');
    if (summary.trim().isEmpty) return;
    final callback = _crossModuleCallback;
    unawaited(() async {
      try {
        await core.memory.writeSummary(
          uid: profile.uid,
          moduleId: SiuYanChatPage.checkInModule,
          summary: summary,
          armCode: 'A',
          hasTranscriptConsent: profile.consent.transcriptRetention,
          tags: [
            'check_in_chat_v2',
            if (callback != null) 'cross_callback:${callback.sourceFamily}',
          ],
        );
      } catch (_) {}
    }());
  }

  void _onIdleTimeout() {
    if (!mounted) return;
    _handOverMemory();
    final uid = _uid;
    if (uid == null) return;
    _briefPrSurfaced = false;
    unawaited(_surfaceBriefPr(Navigator.of(context), uid));
  }

  void _onSwitchedAway() {
    _handOverMemory();
    if (!mounted) return;
    final uid = _uid;
    if (uid == null) return;
    _briefPrSurfaced = false;
    unawaited(_surfaceBriefPr(Navigator.of(context), uid));
  }

  /// Leaving the window ends the session (S9 / back).  No check-in save
  /// step: the answers were written as they came.
  Future<void> _finalizeOnExit() async {
    _handOverMemory();
    _writeMemorySummary();
    final nav = Navigator.of(context);
    final uid = _uid;
    final rec = _recorder;
    if (rec == null || rec.sessionId == null) return;
    if (uid == null) {
      unawaited(rec.end(_exitReason));
      return;
    }
    await _surfaceBriefPr(nav, uid);
  }

  /// v2: the scheduler decides and the card shows on the list page — the
  /// elder is never pushed into Brief PR from here (1020 A (2)).  Legacy
  /// (switch off): the chat-page popup rule, as CheckInArmA.
  Future<void> _surfaceBriefPr(NavigatorState nav, String uid) async {
    if (_briefPrSurfaced) return;
    _briefPrSurfaced = true;
    final rec = _recorder;
    if (rec == null || rec.sessionId == null) return;
    if (BriefPrV2.enabled) {
      await BriefPrV2.endSession(rec,
          endReason: _exitReason, arm: _ruleArm ? 'B' : 'A');
      return;
    }
    if (rec.isOpen) await rec.end(_exitReason);
    final gate = BriefPrGate();
    final shouldShow = await gate.shouldSurfaceBriefPr(
      uid: uid,
      agentId: _siuYan,
      sessionStartedAt: rec.startedAt ?? _openedAt,
      exchangeCount: rec.userTurnCount,
      endReason: rec.endReason,
    );
    if (!shouldShow) return;
    final anchor = await gate.isAnchorPromptFor(uid: uid, agentId: _siuYan);
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: _siuYan,
          agentDisplayName: '小欣',
          isAnchorPrompt: anchor,
          sessionId: rec.sessionId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return FirstIntroOverlay(
      agentId: _siuYan,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) unawaited(_finalizeOnExit());
        },
        child: Scaffold(
          appBar: companionAppBar(context, agentId: _siuYan, onClose: () {
            _closeReason = SessionEndReason.closeButton;
            Navigator.of(context).maybePop();
          }),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    // Newest at the bottom edge; follows the keyboard up.
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    children: <Widget>[
                      for (int i = 0; i < _bubbles.length; i++)
                        _BubbleView(
                          key: ValueKey('siu_yan_chat_bubble_$i'),
                          bubble: _bubbles[i],
                        ),
                      if (_busy || _stage == _Stage.resolving)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      if (_pendingNamingThought != null)
                        NamingThoughtCard(
                          thought: _pendingNamingThought!,
                          onAccept: _acceptNaming,
                          onDecline: _declineNaming,
                        ),
                      if (_pendingReferral != null)
                        ReferralSuggestionCard(
                          surfaced: _pendingReferral!,
                          handoffExecutor:
                              CoreServicesScope.of(context).handoffExecutor,
                          sourceAgentId: _siuYan,
                          onDismiss: () =>
                              setState(() => _pendingReferral = null),
                        ),
                    ].reversed.toList(),
                  ),
                ),
                if (_pendingOffline != null)
                  OfflinePendingBanner(text: _pendingOffline!, isEn: isEn),
                _bottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottom() {
    switch (_stage) {
      case _Stage.q1:
      case _Stage.q2:
      case _Stage.q3:
      case _Stage.q5:
        return _AnswerBar(
          questionId: _questionId(_stage),
          options: _options,
          enabled: !_busy,
          onPick: _onOption,
        );
      case _Stage.q3b:
      case _Stage.q4:
        return _Composer(
          controller: _inputCtrl,
          voice: _voice,
          busy: _busy,
          onSend: _send,
          onSkip: _onSkip,
        );
      case _Stage.chat:
        return _Composer(
          controller: _inputCtrl,
          voice: _voice,
          busy: _busy,
          onSend: _send,
        );
      case _Stage.resolving:
      case _Stage.waiting:
        return const SizedBox.shrink();
    }
  }
}

class _FreeInput {
  const _FreeInput({
    required this.text,
    required this.bubble,
    required this.sentAt,
    required this.voice,
    required this.voiceMs,
  });
  final String text;
  final _Bubble bubble;
  final DateTime sentAt;
  final bool voice;
  final int? voiceMs;
}

class _ReplyOutcome {
  const _ReplyOutcome(this.id, {this.stop = false});

  /// Stored as `response1_id` / `response2_id`.
  final String id;

  /// An acute hit (or the page closed): the check-in ends here.
  final bool stop;
}

class _Bubble {
  _Bubble._(this.fromUser, this.isSystem, this.text,
      {this.copyId, this.freeText = false, this.promptHash});
  factory _Bubble.user(String t, {bool freeText = false}) =>
      _Bubble._(true, false, t, freeText: freeText);
  factory _Bubble.bot(String t, {String? copyId, String? promptHash}) =>
      _Bubble._(false, false, t, copyId: copyId, promptHash: promptHash);
  factory _Bubble.system(String t) => _Bubble._(false, true, t);

  final bool fromUser;
  final bool isSystem;
  final String text;

  /// Siu Yan's lines: the copy id (Q1, X2-1, SY4, …) or `llm`.
  final String? copyId;

  /// Elder's lines: typed (true) or a button (false).
  final bool freeText;
  final String? promptHash;
}

/// Same bubble as CheckInArmA's chat, for both arms.
class _BubbleView extends StatelessWidget {
  const _BubbleView({super.key, required this.bubble});
  final _Bubble bubble;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = bubble;
    final color = b.fromUser
        ? theme.colorScheme.primaryContainer
        : b.isSystem
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = b.fromUser
        ? theme.colorScheme.onPrimaryContainer
        : b.isSystem
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface;
    return Align(
      alignment: b.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: RichChatText(
          text: b.text,
          style: TextStyle(fontSize: 17, height: 1.4, color: fg),
        ),
      ),
    );
  }
}

/// The button replies of Q1, Q2, Q3 and Q5 (≥ 52 px tall, wrap on small
/// phones and large text).
class _AnswerBar extends StatelessWidget {
  const _AnswerBar({
    required this.questionId,
    required this.options,
    required this.enabled,
    required this.onPick,
  });

  final String questionId;
  final List<CheckInOption> options;
  final bool enabled;
  final ValueChanged<CheckInOption> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              OutlinedButton(
                key: ValueKey('check_in_answer_${questionId}_${o.code}'),
                onPressed: enabled ? () => onPick(o) : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: theme.colorScheme.primary, width: 1.4),
                ),
                child: Text(o.label, style: const TextStyle(fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }
}

/// CheckInArmA's composer; with [onSkip], the 唔講住 button above it
/// (Q3b, Q4).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.voice,
    required this.busy,
    required this.onSend,
    this.onSkip,
  });

  final TextEditingController controller;
  final VoiceInputController voice;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSkip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  key: const ValueKey('check_in_skip'),
                  onPressed: busy ? null : onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(
                        color: theme.colorScheme.primary, width: 1.4),
                  ),
                  child: const Text(CheckInChatCopy.skipLabel,
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            Row(
              children: [
                VoiceInputButton(
                  controller: voice,
                  prefix: () => controller.text,
                  onText: (t) => controller.text = t,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 17),
                    decoration: InputDecoration(
                      // 1020e 二.5: typing only (same words as #134).
                      hintText: isEn
                          ? CheckInChatCopy.inputHintEn
                          : CheckInChatCopy.inputHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ComposerSendButton(
                  onPressed: busy
                      ? null
                      : () async {
                          // B03 — stop dictation before snapshot + clear.
                          await voice.stopForSend();
                          onSend();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

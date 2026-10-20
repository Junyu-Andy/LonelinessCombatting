/// 1020d sections 2, 5, 6, 8 — 回憶 v2: one weekly page for both arms,
/// behind `app_config/feature_flags.reminiscenceV2Enabled` (the router in
/// `reminiscence_router.dart` picks it; off = the old arm A / arm B pages).
///
/// What the elder sees, both arms:
///   first visit of the week → the opener as three bubbles, then Q1;
///   Q1 … Q8 in order, each with an input box and 「唔想講」 (no answer
///   options, no topic cards);
///   after Q8 → the closing line and 「完成今個禮拜」 → the chapter, the
///   three ratings, 「改一改」 / 「儲存」; then 「再講多啲」 and, after
///   that, 「重新整理」.
///
/// The only difference is what follows an answer:
///   - rule arm: one fixed line (general lines rotated, not one of the last
///     two; the Q7 line after Q7; a Z5 line for grief / past hardship,
///     rule-templates.md rule 3).  **Zero LLM calls**: every model call sits
///     behind `!_ruleArm`, and the server refuses Arm B anyway.
///   - Hybrid: one LLM follow-up (`[回憶·追問]`), then after its answer one
///     short LLM reply (`[回憶·回應]`), prompt key `ah_jan_ah_bak_v3`,
///     moduleId `m3_reminiscence_w{N}`; up to
///     `app_config/phase_b.reminiscenceFollowupsMax` follow-ups (1).
///   - 唔想講: 「冇問題，我哋講下一樣。」 in both arms, no LLM.
///
/// The flow is driven by the last message ([_advance]): leaving at any
/// point and coming back continues exactly there (first unanswered
/// question, or a pending follow-up).
///
/// Safety: every typed message goes through the shared check at the
/// `chat_reminiscence` input point (Hybrid: inside the gateway, as the old
/// arm A page; rule arm: [SafetyService] directly, same point).  An acute
/// or `moderate_interrupt` hit stops the questions for this visit and runs
/// the existing safety flow; the message is marked and left out of the
/// chapter.  `moderate_review` (grief / past hardship, which these
/// questions invite) keeps going, as on the old pages.
///
/// Valid session (1020d 2 (5)): ≥ 3 of the week's questions answered in
/// this visit, both arms ([ChatSessionRecorder.markReminiscenceQuestionAnswered]).
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
import '../../../../core/config/phase_b_config.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/memory/memory_mode.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../../core/safety/safety_copy.dart';
import '../../../../core/scheduling/study_week.dart';
import '../../../../core/scheduling/w0_date.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../../shared/widgets/composer_send_button.dart';
import '../../../../shared/widgets/keyboard_compact.dart';
import '../../../../shared/widgets/rich_chat_text.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/data/brief_pr_v2.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../rule_replies/data/rule_reply_pool.dart';
import '../../data/reminiscence_themes.dart';
import '../../data/reminiscence_v2_copy.dart';
import '../../data/reminiscence_v2_models.dart';
import '../../data/reminiscence_v2_store.dart';
import '../widgets/reminiscence_chapter_card.dart';

class ReminiscenceV2Page extends StatefulWidget {
  const ReminiscenceV2Page({super.key, required this.theme, this.clock});

  final ReminiscenceTheme theme;

  /// Tests: message times and the study week.
  final DateTime Function()? clock;

  /// The prompt key the Hybrid calls send (the server agent registers it:
  /// functions/prompts/ah_jan_ah_bak.v3.txt).
  static const String promptKey = 'ah_jan_ah_bak_v3';

  /// First line of the context block (contract with the server prompt).
  static const markerFollowup = '[回憶·追問]';
  static const markerReply = '[回憶·回應]';
  static const markerMore = '[回憶·再講多啲]';

  static String moduleIdFor(int weekIndex) => 'm3_reminiscence_w$weekIndex';

  @override
  State<ReminiscenceV2Page> createState() => _ReminiscenceV2PageState();
}

enum _Stage { loading, answer, followupAnswer, waiting, finish, chapter, extra }

class _Ack {
  _Ack(this.afterCount, this.text);
  final int afterCount;
  final String text;
}

class _ReminiscenceV2PageState extends State<ReminiscenceV2Page> {
  /// Same pause as the other rule pages before a fixed line.
  static const _templatePause = Duration(milliseconds: 700);
  static const _agent = AgentRegistry.ahJanAhBakId;

  // The 80-character weekly summary (Hybrid), unchanged from the old arm A
  // page: next week's context and memory read it from the M3 week doc.
  static const _summarySystemPromptZh = '''
你係一個聆聽者，幫用戶整理今次傾過嘅內容。用第二人稱「你」嚟寫，
2-3 句，唔可以超過 80 字。寫出佢提過嘅人物 / 地方 / 感受具體細節。
唔好評論、唔好總結教訓。例：「呢個禮拜你同我提起阿嫲嘅煲仔飯…」
''';

  final _inputCtrl = TextEditingController();
  final _voice = VoiceInputController();
  final _chapterKey = GlobalKey();

  _Stage _stage = _Stage.loading;
  ReminiscenceWeekState? _state;
  ReminiscenceChapterDoc? _chapter;
  StreamSubscription<ReminiscenceChapterDoc?>? _chapterSub;
  final List<_Ack> _acks = [];
  bool _busy = false;
  bool _started = false;
  bool _safetyStopped = false;
  bool _consentAsked = false;
  bool _scrolledToChapter = false;

  /// The chapter became ready while this page was open (or is new on
  /// entry): 「第 N 章整理好喇」 above it.
  bool _readyBanner = false;

  // Fixed for the page's life.
  bool _ruleArm = true;
  bool _available = false;
  String? _uid;
  UserProfile? _profile;
  AnalyticsService? _analytics;

  /// Voice / time of the elder's message being answered (turn log).
  ({DateTime sentAt, bool voice, int? voiceMs, int chars})? _input;

  ChatSessionRecorder? _recorder;
  bool _briefPrSurfaced = false;
  String? _closeReason;

  // T49e-3 memory hand-over (Hybrid), as the old arm A page.
  bool _memoryHandedOver = false;
  bool _disposed = false;
  CoreServicesScope? _memCore;

  int get _week => widget.theme.weekIndex;
  ReminiscenceV2Week get _copy => ReminiscenceV2Copy.week(_week);
  String get _moduleId => ReminiscenceV2Page.moduleIdFor(_week);
  DateTime _now() => (widget.clock ?? DateTime.now)();

  ReminiscenceWeekStore get _weeks =>
      ReminiscenceV2Stores.week(available: _available);
  ReminiscenceChapterStore get _chapters =>
      ReminiscenceV2Stores.chapters(available: _available);

  bool get _retain =>
      _profile?.consent.transcriptRetentionFor(_agent) ?? false;

  List<ReminiscenceMessage> get _messages => _state?.messages ?? const [];

  // ---------------------------------------------------------------------
  // Start / resume
  // ---------------------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _captureMemoryDeps();
    if (_started) return;
    _started = true;
    _ruleArm = !Arm.isA(context);
    _available = AuthServiceScope.of(context).available;
    _profile = AppSettingsScope.read(context).profile;
    _uid = _profile?.uid;
    _analytics = AnalyticsScope.of(context);
    _recorder = ChatSessionRecorder(
      uid: _uid,
      agentId: _agent,
      moduleId: _moduleId,
      theme: widget.theme.titleZh,
      analytics: _analytics!,
      available: _available,
      onIdleTimeout: _onIdleTimeout,
      onSwitchedAway: _onSwitchedAway,
      reminiscenceV2: true,
    );
    _voice.onTranscriptionFailed =
        (c) => _recorder?.logVoiceTranscriptionFailed(c);
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
    _handOverMemory();
    _chapterSub?.cancel();
    _recorder?.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    final arm = _ruleArm ? 'B' : 'A';
    ReminiscenceWeekState? state;
    if (uid != null) state = await _weeks.load(uid, _week, arm: arm);
    if (!mounted) return;
    state ??= ReminiscenceWeekState(weekIndex: _week, arm: arm);
    _state = state;
    if (state.messages.isEmpty) {
      // First visit of the week: the opener (three bubbles), then Q1.
      final name = AgentRegistry.ahJanAhBakName(_profile?.ahJanAhBakVariant);
      final opener = ReminiscenceV2Copy.openerFor(_week, name: name);
      for (var i = 0; i < opener.length; i++) {
        _add(ReminiscenceMessageKind.opener, opener[i], copyId: 'opener_${i + 1}');
      }
      _askQuestion(1);
      await _save();
    }
    if (state.status != ReminiscenceWeekStatus.inProgress &&
        state.status != ReminiscenceWeekStatus.questionsDone) {
      _watchChapter();
    }
    if (!mounted) return;
    setState(() => _stage = _Stage.waiting);
    await _advance();
  }

  Future<void> _save() async {
    final uid = _uid;
    final s = _state;
    if (uid == null || s == null) return;
    await _weeks.save(uid, s, retainTranscript: _retain);
  }

  ReminiscenceMessage _add(ReminiscenceMessageKind kind, String text,
      {int? q, String? copyId}) {
    final s = _state!;
    final m = ReminiscenceMessage(
      id: 'm${(s.messages.length + 1).toString().padLeft(3, '0')}',
      kind: kind,
      text: text,
      at: _now(),
      questionIndex: q,
      copyId: copyId,
    );
    s.messages.add(m);
    return m;
  }

  void _askQuestion(int q) {
    final s = _state!;
    s.currentQuestion = q;
    _add(ReminiscenceMessageKind.question, _copy.question(q),
        q: q, copyId: 'W$_week-Q$q');
  }

  void _setStage(_Stage stage) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _busy = false;
    });
  }

  /// What to do next, from the last message (also how a visit resumes).
  Future<void> _advance() async {
    final s = _state;
    if (s == null || !mounted || _safetyStopped || _messages.isEmpty) return;
    final last = _messages.last;
    final q = last.questionIndex;
    switch (last.kind) {
      case ReminiscenceMessageKind.opener:
        _askQuestion(1);
        await _save();
        _setStage(_Stage.answer);
      case ReminiscenceMessageKind.question:
        _setStage(_Stage.answer);
      case ReminiscenceMessageKind.followup:
        _setStage(_Stage.followupAnswer);
      case ReminiscenceMessageKind.answer:
        if (last.flagged) {
          // Resuming after a safety stop: the next question.
          await _nextAfter(q!);
        } else if (_ruleArm) {
          await _ruleAfterAnswer(q!, last);
        } else {
          await _hybridAfterAnswer(q!, last);
        }
      case ReminiscenceMessageKind.followupAnswer:
        if (last.flagged || _ruleArm) {
          await _nextAfter(q!);
        } else {
          await _hybridAfterAnswer(q!, last);
        }
      case ReminiscenceMessageKind.skip:
        await _afterSkip(q!);
      case ReminiscenceMessageKind.reply:
      case ReminiscenceMessageKind.fixedLine:
        await _nextAfter(q!);
      case ReminiscenceMessageKind.closing:
        _setStage(_chapterPhase ? _Stage.chapter : _Stage.finish);
      case ReminiscenceMessageKind.extra:
        if (last.flagged) {
          _setStage(_Stage.chapter);
        } else {
          await _extraReply(last);
        }
      case ReminiscenceMessageKind.extraReply:
        // Coming back after 再講多啲: the chapter with its buttons (the
        // live flow keeps the input box open itself).
        _setStage(_Stage.chapter);
    }
  }

  bool get _chapterPhase {
    final status = _state?.status;
    return status == ReminiscenceWeekStatus.chapterRequested ||
        status == ReminiscenceWeekStatus.chapterReady;
  }

  /// The next question, or the closing line after Q8.
  Future<void> _nextAfter(int q) async {
    final s = _state!;
    if (q >= ReminiscenceV2Copy.questionsPerWeek) {
      s.currentQuestion = ReminiscenceV2Copy.questionsPerWeek + 1;
      s.status = ReminiscenceWeekStatus.questionsDone;
      _add(ReminiscenceMessageKind.closing, ReminiscenceV2Copy.closingLine,
          copyId: 'closing');
      await _save();
      _setStage(_Stage.finish);
      return;
    }
    _askQuestion(q + 1);
    await _save();
    _setStage(_Stage.answer);
  }

  // ---------------------------------------------------------------------
  // Elder input
  // ---------------------------------------------------------------------

  Future<void> _send() async {
    try {
      await _sendInner();
    } catch (e) {
      if (kDebugMode) debugPrint('[reminiscence_v2] send failed: $e');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _sendInner() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy || _state == null) return;
    final stage = _stage;
    if (stage != _Stage.answer &&
        stage != _Stage.followupAnswer &&
        stage != _Stage.extra) {
      return;
    }
    if (!_ruleArm && !_consentAsked) {
      // As the old arm A page: once per module per App run, Hybrid only.
      _consentAsked = true;
      await TranscriptConsentPrompter.maybePrompt(
          context: context, moduleKey: 'm3_w$_week');
      if (!mounted) return;
    }
    final (usedVoice, voiceMs) = _voice.takeModality();
    _input = (
      sentAt: DateTime.now(),
      voice: usedVoice,
      voiceMs: voiceMs,
      chars: text.length,
    );
    final q = _state!.currentQuestion;
    setState(() {
      _busy = true;
      _stage = _Stage.waiting;
      _inputCtrl.clear();
      switch (stage) {
        case _Stage.answer:
          _add(ReminiscenceMessageKind.answer, text, q: q);
        case _Stage.followupAnswer:
          _add(ReminiscenceMessageKind.followupAnswer, text, q: q);
        default:
          _add(ReminiscenceMessageKind.extra, text);
      }
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    // 1020d 2 (5): a question answered in this visit (follow-up answers,
    // 唔想講 and 再講多啲 not counted).
    if (stage == _Stage.answer) _recorder?.markReminiscenceQuestionAnswered();
    await _save();
    await _advance();
  }

  /// 唔想講 under a question or a follow-up.
  Future<void> _skip() async {
    if (_busy || _state == null) return;
    if (_stage != _Stage.answer && _stage != _Stage.followupAnswer) return;
    final q = _state!.currentQuestion;
    _input = null;
    setState(() {
      _busy = true;
      _stage = _Stage.waiting;
      _inputCtrl.clear();
      _add(ReminiscenceMessageKind.skip, ReminiscenceV2Copy.skipLabel, q: q);
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    await _save();
    await _advance();
  }

  /// Both arms: the fixed 唔想講 line (no LLM), then the next question.
  /// After Q8 the closing line follows straight away.
  Future<void> _afterSkip(int q) async {
    if (q < ReminiscenceV2Copy.questionsPerWeek) {
      await _fixedLine(ReminiscenceV2Copy.skipLine, 'SKIP', q);
    } else {
      await _logFixedTurn('', 'SKIP');
    }
    await _nextAfter(q);
  }

  /// Show a fixed line (after the usual short pause) and log it.
  Future<void> _fixedLine(String text, String id, int? q,
      {ReminiscenceMessageKind kind = ReminiscenceMessageKind.fixedLine,
      DistressMatch flag = const DistressMatch(DistressLevel.none),
      String? turnId}) async {
    if (mounted) setState(() => _busy = true);
    await Future<void>.delayed(_templatePause);
    if (mounted) {
      setState(() => _add(kind, text, q: q, copyId: id));
    } else {
      _add(kind, text, q: q, copyId: id);
    }
    await _logFixedTurn(text, id, flag: flag, turnId: turnId);
  }

  Future<void> _logFixedTurn(String text, String id,
      {DistressMatch flag = const DistressMatch(DistressLevel.none),
      String? turnId}) async {
    final rec = _recorder;
    if (rec == null) return;
    final input = _input;
    _input = null;
    await rec.logTurn(TurnRecord(
      agentId: _agent,
      moduleId: _moduleId,
      theme: widget.theme.titleZh,
      userSent: input?.sentAt ?? DateTime.now(),
      replyShown: DateTime.now(),
      modality: input?.voice == true ? InputModality.voice : InputModality.text,
      voiceDurationMs: input?.voiceMs,
      charCount: input?.chars ?? 0,
      detector: flag,
      shortCircuited: false,
      ackShown: false,
      response: LlmResponse(
        text: text,
        inputFlag: flag,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: false,
        metadata: TurnMetadata(agentId: _agent, sessionId: rec.sessionId),
        status: _ruleArm ? LlmStatus.ruleBased : LlmStatus.fixedReply,
        turnId: turnId,
      ),
    ));
    if (_ruleArm && text.isNotEmpty) {
      unawaited(_analytics?.logEvent('rule_template_reply', {
            'agent_id': _agent,
            'module_id': _moduleId,
            'template_id': id,
            'pool_version': ReminiscenceV2Copy.version,
            'theme': 'reminiscence_v2',
          }) ??
          Future<void>.value());
    }
  }

  // ---------------------------------------------------------------------
  // Rule arm: fixed lines, no LLM
  // ---------------------------------------------------------------------

  Future<void> _ruleAfterAnswer(int q, ReminiscenceMessage answer) async {
    final (flag, turnId) = await _ruleSafety(answer.text);
    if (flag.level == DistressLevel.acute || flag.interrupts) {
      await _safetyStop(answer, flag, turnId: turnId);
      return;
    }
    if (q >= ReminiscenceV2Copy.questionsPerWeek) {
      // After Q8 the closing line itself thanks the elder.
      await _logFixedTurn('', 'none', flag: flag, turnId: turnId);
      await _nextAfter(q);
      return;
    }
    final (String, String) line;
    if (q == ReminiscenceV2Copy.hardshipQuestion) {
      line = ('Q7', ReminiscenceV2Copy.q7Line);
    } else if (flag.level == DistressLevel.moderateReview) {
      line = ReminiscenceV2Logic.nextGriefLine(_messages, [
        for (final e in RuleReplyPool.entries)
          if (e.id.startsWith('Z5')) (e.id, e.zh),
      ]);
    } else {
      line = ReminiscenceV2Logic.nextGeneralLine(_messages);
    }
    await _fixedLine(line.$2, line.$1, q, flag: flag, turnId: turnId);
    await _nextAfter(q);
  }

  /// Rule arm 再講多啲: one fixed line.
  Future<void> _ruleExtra(ReminiscenceMessage extra) async {
    final (flag, turnId) = await _ruleSafety(extra.text);
    if (flag.level == DistressLevel.acute || flag.interrupts) {
      await _safetyStop(extra, flag, turnId: turnId);
      return;
    }
    await _fixedLine(ReminiscenceV2Copy.extraLine, 'EXTRA', null,
        kind: ReminiscenceMessageKind.extraReply, flag: flag, turnId: turnId);
    await _save();
    _setStage(_Stage.extra);
  }

  /// The shared check (T7) at the same point the Hybrid gateway uses for
  /// `m3_reminiscence_w{N}`; the classifier only when its switch is on.
  Future<(DistressMatch, String)> _ruleSafety(String text) async {
    final safety = (_memCore ?? CoreServicesScope.of(context)).safety;
    const point = SafetyInputPoint.chatReminiscence;
    final turnId = SafetyService.newTurnId();
    if (safety.classifierActiveFor(point)) {
      final r = await safety.checkUserTextClassified(text,
          point: point,
          uid: _uid,
          agentId: _agent,
          sessionId: _recorder?.sessionId,
          turnId: turnId);
      return (r.match, turnId);
    }
    final r = safety.checkUserText(text,
        point: point,
        uid: _uid,
        agentId: _agent,
        sessionId: _recorder?.sessionId,
        turnId: turnId);
    return (r.match, turnId);
  }

  // ---------------------------------------------------------------------
  // Hybrid: LLM follow-up and short reply
  // ---------------------------------------------------------------------

  /// After an answer or a follow-up answer: another follow-up while under
  /// the cap, else the short reply; then the next question.
  Future<void> _hybridAfterAnswer(int q, ReminiscenceMessage last) async {
    final s = _state!;
    final max = PhaseBConfig.current.reminiscenceFollowupsMax.clamp(1, 2);
    final asked = s.followupsAsked[q] ?? 0;
    final followup = asked < max;
    final response = await _callLlm(
      block: _questionBlock(q, followup: followup),
      userInput: last.text,
      upTo: _messages.length - 1,
    );
    final outcome = await _handleLlm(response, last);
    if (outcome == null) return; // safety stop
    if (outcome == _LlmOutcome.fallback) {
      // A neutral fixed line, then on (logged as llm_fallback).
      final (_, text) = ReminiscenceV2Logic.nextGeneralLine(_messages);
      _addAndShow(ReminiscenceMessageKind.fixedLine, text, q, 'llm_fallback');
      await _nextAfter(q);
      return;
    }
    if (followup) {
      s.followupsAsked[q] = asked + 1;
      _addAndShow(ReminiscenceMessageKind.followup, response.text, q, 'llm');
      await _save();
      _setStage(_Stage.followupAnswer);
    } else {
      _addAndShow(ReminiscenceMessageKind.reply, response.text, q, 'llm');
      await _nextAfter(q);
    }
  }

  Future<void> _hybridExtra(ReminiscenceMessage extra) async {
    final response = await _callLlm(
      block: '${ReminiscenceV2Page.markerMore}\n本週主題：${_copy.themeZh}',
      userInput: extra.text,
      upTo: _messages.length - 1,
    );
    final outcome = await _handleLlm(response, extra);
    if (outcome == null) return;
    if (outcome == _LlmOutcome.fallback) {
      _addAndShow(ReminiscenceMessageKind.extraReply,
          ReminiscenceV2Copy.extraLine, null, 'llm_fallback');
    } else {
      _addAndShow(ReminiscenceMessageKind.extraReply, response.text, null, 'llm');
    }
    await _save();
    _setStage(_Stage.extra);
  }

  Future<void> _extraReply(ReminiscenceMessage extra) =>
      _ruleArm ? _ruleExtra(extra) : _hybridExtra(extra);

  void _addAndShow(
      ReminiscenceMessageKind kind, String text, int? q, String copyId) {
    if (mounted) {
      setState(() => _add(kind, text, q: q, copyId: copyId));
    } else {
      _add(kind, text, q: q, copyId: copyId);
    }
  }

  /// The context block: first line one of the three markers, then
  /// 本週主題 / 題目 / 老人答 and, after a follow-up, 追問 / 老人再答.
  String _questionBlock(int q, {required bool followup}) {
    final lines = <String>[
      followup ? ReminiscenceV2Page.markerFollowup : ReminiscenceV2Page.markerReply,
      '本週主題：${_copy.themeZh}',
      '題目：${_copy.question(q)}',
    ];
    final answer = ReminiscenceV2Logic.answerTo(_messages, q);
    lines.add('老人答：${answer?.text ?? ''}');
    String? pending;
    for (final m in _messages) {
      if (m.questionIndex != q) continue;
      if (m.kind == ReminiscenceMessageKind.followup) {
        pending = m.text;
      } else if (m.kind == ReminiscenceMessageKind.followupAnswer &&
          pending != null) {
        lines.add('追問：$pending');
        lines.add('老人再答：${m.text}');
        pending = null;
      }
    }
    return lines.join('\n');
  }

  /// The week so far as alternating model turns (flagged messages and the
  /// message being answered left out; the last 16 turns).
  List<LlmTurn> _history(int upTo) {
    final out = <LlmTurn>[];
    for (final m in _messages.take(upTo)) {
      if (m.flagged || m.text.trim().isEmpty) continue;
      final fromUser = m.fromUser;
      if (out.isNotEmpty && out.last.fromUser == fromUser) {
        final prev = out.removeLast();
        out.add(LlmTurn(fromUser: fromUser, text: '${prev.text}\n${m.text}'));
      } else {
        out.add(LlmTurn(fromUser: fromUser, text: m.text));
      }
    }
    return out.length <= 16 ? out : out.sublist(out.length - 16);
  }

  Future<LlmResponse> _callLlm({
    required String block,
    required String userInput,
    required int upTo,
  }) async {
    assert(!_ruleArm, 'the rule arm never calls the LLM');
    final core = _memCore ?? CoreServicesScope.of(context);
    final profile = _profile;
    if (mounted) setState(() => _busy = true);
    final persona = await core.personaResolver
        .resolve(agentId: _agent, profile: profile);
    final suffix = [
      block,
      if (persona?.contextSuffix != null) persona!.contextSuffix!,
      if (profile?.avoidTopics?.isNotEmpty == true)
        '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：${profile!.avoidTopics}',
    ].join('\n\n').trim();
    try {
      return await core.llm.send(
        moduleId: _moduleId,
        promptKey: ReminiscenceV2Page.promptKey,
        agentId: _agent,
        variantName: persona?.variantName,
        contextSuffix: suffix,
        agentContextSnapshot: persona?.agentContextSnapshot,
        history: _history(upTo),
        userInput: userInput,
        uid: _uid,
        sessionId: _recorder?.sessionId,
        theme: widget.theme.titleZh,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[reminiscence_v2] LLM call failed: $e');
      return LlmResponse(
        text: '',
        inputFlag: const DistressMatch(DistressLevel.none),
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: false,
        metadata: TurnMetadata(agentId: _agent, sessionId: _recorder?.sessionId),
        status: LlmStatus.fallback,
        error: 'client_exception',
      );
    }
  }

  /// Safety, turn log, memory buffer.  Null = the questions stopped.
  Future<_LlmOutcome?> _handleLlm(
      LlmResponse response, ReminiscenceMessage input) async {
    final escalation = response.inputFlag.level.index >=
            response.outputFlag.level.index
        ? response.inputFlag
        : response.outputFlag;
    if (response.shortCircuited ||
        escalation.level == DistressLevel.acute ||
        escalation.interrupts) {
      await _safetyStop(input, escalation,
          response: response, turnId: response.turnId);
      return null;
    }
    final input0 = _input;
    _input = null;
    await _recorder?.logTurn(TurnRecord(
      agentId: _agent,
      moduleId: _moduleId,
      theme: widget.theme.titleZh,
      userSent: input0?.sentAt ?? DateTime.now(),
      replyShown: DateTime.now(),
      modality: input0?.voice == true ? InputModality.voice : InputModality.text,
      voiceDurationMs: input0?.voiceMs,
      charCount: input0?.chars ?? input.text.length,
      detector: escalation,
      shortCircuited: false,
      ackShown: false,
      response: response,
    ));
    if (response.isFallback) {
      if (kDebugMode) {
        debugPrint('[reminiscence_v2] LLM fallback: ${response.error}');
      }
      unawaited(_analytics?.logEvent('reminiscence_v2_llm_fallback', {
            'agent_id': _agent,
            'module_id': _moduleId,
            'error': response.error,
            'message_kind': input.kind.code,
          }) ??
          Future<void>.value());
      return _LlmOutcome.fallback;
    }
    await _appendToBuffer(fromUser: true, text: input.text, response: response);
    await _appendToBuffer(
        fromUser: false, text: response.text, response: response);
    return _LlmOutcome.ok;
  }

  /// Acute or moderate_interrupt: the message is marked (left out of the
  /// chapter, never sent again), the safety template, the existing safety
  /// flow, and no more questions in this visit.  Next visit: the next
  /// question.
  Future<void> _safetyStop(ReminiscenceMessage msg, DistressMatch flag,
      {LlmResponse? response, String? turnId}) async {
    final s = _state!;
    final i = s.messages.indexOf(msg);
    if (i >= 0) s.messages[i] = msg.copyWith(safety: flag.level.tierCode);
    final acute = flag.level == DistressLevel.acute;
    final ack = acute
        ? SafetyCopy.acuteAck(_agent, isEn: false)
        : SafetyCopy.moderateAck(_agent, isEn: false);
    _safetyStopped = true;
    if (mounted) {
      setState(() {
        if (ack != null) _acks.add(_Ack(s.messages.length, ack));
        _busy = false;
        _stage = _stage == _Stage.extra || msg.kind == ReminiscenceMessageKind.extra
            ? _Stage.chapter
            : _Stage.waiting;
      });
    }
    await _save();
    final input0 = _input;
    _input = null;
    final rec = _recorder;
    String? turnDocId;
    if (rec != null) {
      turnDocId = await rec.logTurn(TurnRecord(
        agentId: _agent,
        moduleId: _moduleId,
        theme: widget.theme.titleZh,
        userSent: input0?.sentAt ?? DateTime.now(),
        replyShown: DateTime.now(),
        modality:
            input0?.voice == true ? InputModality.voice : InputModality.text,
        voiceDurationMs: input0?.voiceMs,
        charCount: input0?.chars ?? msg.text.length,
        detector: flag,
        shortCircuited: acute,
        ackShown: ack != null,
        response: response ??
            LlmResponse(
              text: '',
              inputFlag: flag,
              outputFlag: const DistressMatch(DistressLevel.none),
              shortCircuited: acute,
              metadata: TurnMetadata(agentId: _agent, sessionId: rec.sessionId),
              status: acute
                  ? LlmStatus.shortCircuited
                  : (_ruleArm ? LlmStatus.ruleBased : LlmStatus.fixedReply),
              turnId: turnId,
            ),
      ));
    }
    if (acute) unawaited(rec?.end(SessionEndReason.crisis));
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

  /// Ah Jan / Ah Bak's short-term buffer (memory), Hybrid only, as the old
  /// arm A page: never a safety-flagged exchange, never a fallback.
  Future<void> _appendToBuffer({
    required bool fromUser,
    required String text,
    required LlmResponse response,
  }) async {
    final core = _memCore;
    final profile = _profile;
    if (_ruleArm || core == null || profile == null) return;
    if (text.trim().isEmpty || response.hasEscalation) return;
    if (!fromUser && response.isFallback) return;
    if (!profile.consent.transcriptRetentionFor(_agent)) return;
    try {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: _agent,
        turn: AgentContextTurn(
            fromUser: fromUser, text: text, timestamp: DateTime.now()),
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Chapter
  // ---------------------------------------------------------------------

  /// 「完成今個禮拜」 / 「重新整理」.
  Future<void> _requestChapter() async {
    final s = _state;
    final uid = _uid;
    if (s == null || _busy) return;
    final first = s.status == ReminiscenceWeekStatus.questionsDone;
    setState(() {
      _busy = true;
      _stage = _Stage.chapter;
    });
    await _ensureSession();
    _recorder?.bumpActivity();
    final input = ReminiscenceV2Logic.chapterInput(_week, s.messages);
    final requestId = ReminiscenceChapterStore.newRequestId();
    _scrolledToChapter = false;
    if (uid != null) {
      if (_ruleArm) {
        final prev = await _chapters.get(uid, _week);
        await _chapters.writeRule(uid, _week,
            requestId: requestId,
            input: input,
            ruleText: ReminiscenceV2Logic.ruleChapterText(_week, s.messages),
            version: (prev?.version ?? 0) + 1);
        s.status = ReminiscenceWeekStatus.chapterReady;
      } else {
        await _chapters.requestHybrid(uid, _week,
            requestId: requestId, input: input);
        s.status = ReminiscenceWeekStatus.chapterRequested;
      }
    }
    s.chapterRequestedAtMessage = s.messages.length;
    await _save();
    _watchChapter();
    if (first) unawaited(_saveWeeklySummary());
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _watchChapter() {
    final uid = _uid;
    if (uid == null || _chapterSub != null) return;
    _chapterSub = _chapters.watch(uid, _week).listen(_onChapter);
  }

  void _onChapter(ReminiscenceChapterDoc? doc) {
    if (!mounted) return;
    final s = _state;
    final becameReady = doc != null &&
        doc.isReady &&
        (_chapter == null ||
            !_chapter!.isReady ||
            _chapter!.requestId != doc.requestId);
    setState(() {
      _chapter = doc;
      if (doc != null && doc.isReady && s?.ratedRequestId != doc.requestId) {
        _readyBanner = true;
      }
    });
    if (s != null &&
        doc != null &&
        doc.isReady &&
        s.status != ReminiscenceWeekStatus.chapterReady) {
      s.status = ReminiscenceWeekStatus.chapterReady;
      unawaited(_save());
    }
    if (becameReady && !_scrolledToChapter) {
      _scrolledToChapter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chapterKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(ctx,
            alignment: 1.0, duration: const Duration(milliseconds: 250));
      });
    }
  }

  Future<void> _onRated(ChapterRatingResult r) async {
    final doc = _chapter;
    final s = _state;
    final uid = _uid;
    if (doc == null || s == null) return;
    final w0 = w0DateFor(_profile);
    final data = <String, dynamic>{
      'weekIndex': _week,
      'studyWeek': w0 == null ? null : studyWeekAt(w0, _now()),
      'chapterVersion': doc.version ?? 1,
      'source': doc.isRule ? 'rule' : 'hybrid',
      for (final e in r.scores.entries) e.key: e.value,
      'skipped': r.skipped,
    };
    if (uid != null) {
      await ReminiscenceV2Stores.ratings(available: _available).add(uid, data);
    }
    s.ratedRequestId = doc.requestId;
    await _save();
    if (mounted) setState(() => _readyBanner = false);
  }

  Future<void> _onSaveChapter(String text) async {
    final doc = _chapter;
    final uid = _uid;
    if (doc == null || uid == null) return;
    await saveChapterEdit(
      context,
      store: _chapters,
      uid: uid,
      doc: doc,
      edited: text,
    );
    if (mounted) setState(() => _readyBanner = false);
  }

  /// The 80-character summary, as the old pages kept it (M3 week doc):
  /// Hybrid = the LLM summary (fallback: the elder's words), rule arm =
  /// the elder's words, no LLM.
  Future<void> _saveWeeklySummary() async {
    final uid = _uid;
    final s = _state;
    if (uid == null || s == null) return;
    final words = ReminiscenceV2Logic.answersJoined(s.messages);
    var summary = words;
    if (!_ruleArm && words.trim().isNotEmpty) {
      try {
        final core = _memCore!;
        final r = await core.llm.send(
          moduleId: '${_moduleId}_summary',
          systemPrompt: _summarySystemPromptZh,
          history: _history(s.messages.length),
          userInput: '請總結今次嘅內容。',
          uid: uid,
        );
        if (!r.isFallback && r.text.trim().isNotEmpty) summary = r.text.trim();
      } catch (e) {
        if (kDebugMode) debugPrint('[reminiscence_v2] summary failed: $e');
      }
    }
    if (summary.trim().isEmpty) return;
    await ReminiscenceV2Stores.summary(available: _available).save(
      uid: uid,
      weekIndex: _week,
      armCode: _ruleArm ? 'B' : 'A',
      summary: summary,
    );
  }

  bool get _canRegenerate {
    final s = _state;
    if (s == null || !_chapterPhase || _busy) return false;
    final doc = _chapter;
    if (doc != null && doc.isFailed) return true;
    final generating = s.status == ReminiscenceWeekStatus.chapterRequested &&
        (doc == null || !doc.isReady);
    if (generating) return false;
    final since = s.chapterRequestedAtMessage ?? s.messages.length;
    return s.messages
        .skip(since)
        .any((m) => m.kind == ReminiscenceMessageKind.extra && !m.flagged);
  }

  // ---------------------------------------------------------------------
  // Session, memory, Brief PR (as the old arm A page)
  // ---------------------------------------------------------------------

  Future<void> _ensureSession() async {
    final rec = _recorder;
    if (rec == null || rec.isOpen) return;
    await rec.ensureStarted();
    _memoryHandedOver = false;
    _briefPrSurfaced = false;
  }

  void _captureMemoryDeps() {
    if (!mounted || _disposed) return;
    _memCore = CoreServicesScope.of(context);
  }

  void _handOverMemory() {
    _captureMemoryDeps();
    if (_memoryHandedOver || _ruleArm) return;
    final core = _memCore;
    final profile = _profile;
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
      agentId: _agent,
      retentionOn: profile.consent.transcriptRetentionFor(_agent),
      memoryV1: MemoryModes.of(profile).isV1,
    ));
  }

  void _onIdleTimeout() {
    if (!mounted) return;
    _briefPrSurfaced = false;
    unawaited(_endSession(Navigator.of(context), closeSession: false));
  }

  void _onSwitchedAway() {
    _handOverMemory();
    if (!mounted) return;
    _briefPrSurfaced = false;
    unawaited(_endSession(Navigator.of(context), closeSession: false));
  }

  /// Leaving (「離開（會暫存）」, S9 or back) ends the session under the
  /// current rules; the week stays where it is.  Brief PR as usual.
  Future<void> _endSession(NavigatorState nav, {bool closeSession = true}) async {
    _handOverMemory();
    if (_briefPrSurfaced) return;
    _briefPrSurfaced = true;
    final rec = _recorder;
    final profile = _profile;
    final v2 = BriefPrV2.enabled;
    final endReason = _closeReason ?? SessionEndReason.back;
    if (rec == null || rec.sessionId == null) return;
    if (closeSession && rec.isOpen) {
      await rec.end(v2 ? endReason : SessionEndReason.userLeft);
    }
    if (v2) {
      await BriefPrV2.endSession(rec,
          endReason: endReason, arm: _ruleArm ? 'B' : 'A');
      return;
    }
    if (profile == null) return;
    final gate = BriefPrGate();
    final shouldShow = await gate.shouldSurfaceBriefPr(
      uid: profile.uid,
      agentId: _agent,
      sessionStartedAt: rec.startedAt ?? DateTime.now(),
      exchangeCount: rec.userTurnCount,
      endReason: rec.endReason,
    );
    if (!shouldShow) return;
    final anchor = await gate.isAnchorPromptFor(uid: profile.uid, agentId: _agent);
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => BriefPrPage(
        agentId: _agent,
        agentDisplayName:
            AgentRegistry.ahJanAhBakName(profile.ahJanAhBakVariant),
        isAnchorPrompt: anchor,
        sessionId: rec.sessionId,
      ),
    ));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FirstIntroOverlay(
      agentId: _agent,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) unawaited(_endSession(Navigator.of(context)));
        },
        child: Scaffold(
          appBar: companionAppBar(context,
              agentId: _agent,
              leaveLabel: ReminiscenceV2Copy.leaveLabel, onClose: () {
            _closeReason = SessionEndReason.closeButton;
            Navigator.of(context).maybePop();
          }),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: KeyboardScrollToLatest(
                    keyboardOpen: KeyboardCompact.active(context),
                    child: ListView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      children: _listChildren(theme).reversed.toList(),
                    ),
                  ),
                ),
                _bottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _listChildren(ThemeData theme) {
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(widget.theme.titleZh,
            key: const Key('reminiscence_theme_title'),
            style: theme.textTheme.titleMedium),
      ),
    ];
    if (_stage == _Stage.loading) {
      out.add(const _Spinner());
      return out;
    }
    void acksAt(int count) {
      for (final a in _acks) {
        if (a.afterCount == count) out.add(_SystemBubble(text: a.text));
      }
    }

    acksAt(0);
    final msgs = _messages;
    var closingSeen = false;
    for (var i = 0; i < msgs.length; i++) {
      out.add(_MessageBubble(
          key: ValueKey('reminiscence_v2_msg_${msgs[i].id}'), message: msgs[i]));
      acksAt(i + 1);
      if (msgs[i].kind == ReminiscenceMessageKind.closing) {
        closingSeen = true;
        out.add(_chapterSection());
      }
    }
    if (_busy) out.add(const _Spinner());
    if (closingSeen && _chapterPhase && !_busy) {
      final buttons = <Widget>[
        if (_stage != _Stage.extra && !_safetyStopped && _chapter?.isReady == true)
          OutlinedButton(
            key: const Key('reminiscence_more'),
            onPressed: () => setState(() => _stage = _Stage.extra),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            child: const Text(ReminiscenceV2Copy.moreLabel,
                style: TextStyle(fontSize: 18)),
          ),
        if (_canRegenerate)
          FilledButton.tonal(
            key: const Key('reminiscence_regenerate'),
            onPressed: _requestChapter,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            child: const Text(ReminiscenceV2Copy.regenerateLabel,
                style: TextStyle(fontSize: 18)),
          ),
      ];
      if (buttons.isNotEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(spacing: 12, runSpacing: 8, children: buttons),
        ));
      }
    }
    return out;
  }

  Widget _chapterSection() {
    final s = _state!;
    if (s.status == ReminiscenceWeekStatus.questionsDone ||
        s.status == ReminiscenceWeekStatus.inProgress) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FilledButton(
          key: const Key('reminiscence_finish_week'),
          onPressed: _busy || _safetyStopped ? null : _requestChapter,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          child: const Text(ReminiscenceV2Copy.finishWeekLabel,
              style: TextStyle(fontSize: 20)),
        ),
      );
    }
    final doc = _chapter;
    return KeyedSubtree(
      key: _chapterKey,
      child: doc != null && doc.isReady
          ? ReminiscenceChapterCard(
              doc: doc,
              askRating: s.ratedRequestId != doc.requestId,
              showReadyBanner: _readyBanner,
              onRated: _onRated,
              onSave: _onSaveChapter,
            )
          : ReminiscenceChapterPending(
              weekIndex: _week, failed: doc != null && doc.isFailed),
    );
  }

  Widget _bottom() {
    switch (_stage) {
      case _Stage.answer:
      case _Stage.followupAnswer:
        return _Composer(
          controller: _inputCtrl,
          voice: _voice,
          busy: _busy,
          onSend: _send,
          onSkip: _skip,
        );
      case _Stage.extra:
        if (_safetyStopped) return const SizedBox.shrink();
        return _Composer(
          controller: _inputCtrl,
          voice: _voice,
          busy: _busy,
          onSend: _send,
        );
      case _Stage.loading:
      case _Stage.waiting:
      case _Stage.finish:
      case _Stage.chapter:
        return const SizedBox.shrink();
    }
  }
}

enum _LlmOutcome { ok, fallback }

/// Shared by the week page and 我嘅人生小篇章: store the elder's text and
/// the edit ratio against the original (both arms), then the shared safety
/// check on what they typed (the old summary-edit input point).
Future<void> saveChapterEdit(
  BuildContext context, {
  required ReminiscenceChapterStore store,
  required String uid,
  required ReminiscenceChapterDoc doc,
  required String edited,
}) async {
  final safety = CoreServicesScope.of(context).safety;
  final original = doc.originalText;
  final ratio = ReminiscenceV2Logic.editRatio(original, edited);
  await store.saveEdit(uid, doc.weekIndex, editedText: edited, editRatio: ratio);
  if (edited.trim() == original.trim() || !context.mounted) return;
  await safety.checkAndRoute(
    context,
    edited,
    point: SafetyInputPoint.reminiscenceSummaryEdit,
    uid: uid,
    agentId: AgentRegistry.ahJanAhBakId,
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

/// The old arm A page's bubble, now for both arms.  Questions in bold so
/// the elder can find them when scrolling back.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({super.key, required this.message});
  final ReminiscenceMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final color = m.fromUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.secondaryContainer;
    final fg = m.fromUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;
    final question = m.kind == ReminiscenceMessageKind.question;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: RichChatText(
          text: m.text,
          style: TextStyle(
            fontSize: 17,
            height: 1.4,
            color: fg,
            fontWeight: question ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: RichChatText(
          text: text,
          style: TextStyle(
              fontSize: 17, height: 1.4, color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}

/// Input box with 「唔想講」 above it (questions and follow-ups); without
/// it for 再講多啲.
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
                  key: const ValueKey('reminiscence_skip'),
                  onPressed: busy ? null : onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(
                        color: theme.colorScheme.primary, width: 1.4),
                  ),
                  child: const Text(ReminiscenceV2Copy.skipLabel,
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
                    key: const Key('reminiscence_input'),
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                        hintText: ReminiscenceV2Copy.inputHint),
                  ),
                ),
                const SizedBox(width: 8),
                ComposerSendButton(
                  onPressed: busy
                      ? null
                      : () async {
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

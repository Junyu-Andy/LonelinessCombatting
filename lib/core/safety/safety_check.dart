/// T7 — the one safety-check entry point for every free-text input, both
/// arms (SPEC C12, decision 0018).
///
/// ## Who does what
///
/// | Call | Detects | Writes `safety_events` | Crisis page / sheet | PI notified |
/// |---|---|---|---|---|
/// | [SafetyService.detect] | yes | no | no | no |
/// | [SafetyService.checkUserText] | yes | yes, if moderate+ | no (caller) | server, acute |
/// | [SafetyService.checkAiOutput] | yes | yes, only if above the input | no (caller) | server, acute |
/// | [SafetyService.checkAndRoute] | yes | yes, if moderate+ | yes | server, acute |
/// | [SafetyService.route] | no | no | yes | no |
///
/// - **Detect** is the v5 lexicon ([DistressDetector]); same text, same
///   level, in both arms.  It is synchronous and never throws.
/// - **Write**: one `safety_events` doc with `source`
///   (`user_input` / `ai_output_scan` / `form`), `inputPoint`
///   ([SafetyInputPoint] code) and `turnId`.  Fire-and-forget: an offline
///   write must never stand between a participant and the crisis page.
/// - **Route** is [DistressRouter.route]: acute → full-screen
///   [EmergencySupportPage]; moderate_interrupt → support sheet;
///   moderate_review → nothing visible.  Chat pages route themselves
///   because they also show the per-agent template; form pages use
///   [checkAndRoute].
/// - **PI**: the `onSafetyEventCreated` Cloud Function writes `pi_alerts`
///   and emails PI for acute events (testers excepted), and counts one
///   turn once (`turnId`).
///
/// T8 (decision 0025, proposed): an optional classifier slot behind the
/// lexicon — [classifierActiveFor] / [checkUserTextClassified].  Off by
/// default (`PhaseAConfig.safetyClassifierEnabled`); while off, nothing
/// here changes and every check stays synchronous.  See
/// `safety_classifier.dart`.
///
/// Planned callers: T10 (memory:
/// [detect] on the participant's words before summarising), T15 (rule-arm
/// template replies: [checkUserText] before choosing a template).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../config/phase_a_config.dart';
import '../core_services_scope.dart';
import 'distress_detector.dart';
import 'safety_classifier.dart';
import 'safety_event_writer.dart';

/// Where a piece of free text came from — `safety_events.inputPoint`.
/// Codes are stable; add new ones, never rename.
enum SafetyInputPoint {
  // Conversations (scanned before T7 too; never switched off).
  chatCheckIn('chat_check_in', SafetySource.userInput, newInT7: false),
  chatReminiscence('chat_reminiscence', SafetySource.userInput,
      newInT7: false),
  chatReflective('chat_reflective', SafetySource.userInput, newInT7: false),
  chatTungTung('chat_tung_tung', SafetySource.userInput, newInT7: false),
  articleQa('article_qa', SafetySource.userInput, newInT7: false),
  checkInNote('check_in_note', SafetySource.userInput, newInT7: false),
  reminiscenceNote('reminiscence_note', SafetySource.userInput,
      newInT7: false),

  /// App-built model input (greeting, summary, suggestions, progress).
  systemGenerated('system_generated', SafetySource.userInput,
      newInT7: false),

  // Forms and other free text — added in T7, behind
  // `PhaseAConfig.safetyScanAllInputs`.
  thoughtExercise('thought_exercise', SafetySource.form),
  intakeOnMind('intake_on_mind', SafetySource.form),
  intakeAvoidTopics('intake_avoid_topics', SafetySource.form),
  intakeOtherText('intake_other_text', SafetySource.form),
  agentDiff('agent_diff', SafetySource.form),
  feedbackOther('feedback_other', SafetySource.form),
  actionPlan('action_plan', SafetySource.form),
  actionFollowup('action_followup', SafetySource.form),
  pprFreeText('ppr_free_text', SafetySource.form),
  reminiscenceSummaryEdit('reminiscence_summary_edit', SafetySource.form),
  m3SessionEdit('m3_session_edit', SafetySource.form),
  searchQuery('search_query', SafetySource.userInput),

  // T17 (decision 0026) — Phase A ADA Part D and day-7 open questions.
  adaFreeText('ada_free_text', SafetySource.form),
  day7OpenEnded('day7_open_ended', SafetySource.form);

  const SafetyInputPoint(this.code, this.source, {this.newInT7 = true});
  final String code;
  final SafetySource source;

  /// True for inputs first covered in T7 — these follow the
  /// `safetyScanAllInputs` switch.
  final bool newInT7;

  /// T8 — whether the classifier (when switched on) also looks at this
  /// input.  Only the participant's own words: not App-built model input,
  /// and not search words (only [SafetyService.detect] runs on those).
  bool get classifiable =>
      this != SafetyInputPoint.systemGenerated &&
      this != SafetyInputPoint.searchQuery;

  /// The point an [LlmGateway] call's user input belongs to, by moduleId.
  static SafetyInputPoint forModule(String moduleId) {
    if (moduleId == 'm2_check_in') return chatCheckIn;
    if (moduleId == 'reflective_dialogue') return chatReflective;
    if (moduleId == 'tung_tung_chat') return chatTungTung;
    if (moduleId.startsWith('m8_education')) return articleQa;
    if (moduleId == 'm7_action_loop_summary') return actionPlan;
    if (moduleId == 'm7_action_loop_followup') return actionFollowup;
    if (moduleId.startsWith('m3_reminiscence_w') &&
        !moduleId.endsWith('_opener') &&
        !moduleId.endsWith('_summary')) {
      return chatReminiscence;
    }
    return systemGenerated;
  }
}

/// Outcome of one check.
class SafetyCheckResult {
  /// Lexicon result; `none` when [scanned] is false.
  final DistressMatch match;
  final SafetyInputPoint point;

  /// False when the input point is switched off (pre-T7 coverage).
  final bool scanned;

  /// True when a `safety_events` write was queued.
  final bool eventQueued;

  /// Shared by every scan of one turn (input + AI reply).
  final String turnId;

  const SafetyCheckResult({
    required this.match,
    required this.point,
    required this.scanned,
    required this.eventQueued,
    required this.turnId,
    this.classifier,
  });

  /// T8 — the classifier's answer; null when it was not asked (switch
  /// off, input not classifiable, or the lexicon already said acute).
  final ClassifierVerdict? classifier;

  DistressLevel get level => match.level;
  bool get isEscalation => match.isEscalation;
  bool get isAcute => match.level == DistressLevel.acute;
}

/// See the library comment for the contract.  Holds no state; one instance
/// lives in [CoreServicesScope.safety].
class SafetyService {
  const SafetyService({
    this.detector = const DistressDetector(),
    this.writer,
    this.classifier,
    this.classifierLog,
  });

  final DistressDetector detector;

  /// Null in guest mode and tests: nothing is written, detection still runs.
  final SafetyEventWriter? writer;

  /// T8 — the classifier slot.  Null = lexicon only, whatever the switch.
  final SafetyClassifier? classifier;

  /// T8 — where the App logs calls that never came back.
  final ClassifierFallbackLog? classifierLog;

  static final Random _rng = Random();

  /// A fresh id for one conversational turn / one form submission.
  static String newTurnId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_rng.nextInt(1 << 32).toRadixString(36)}';

  /// Detection only: no write, no UI, no PI.
  DistressMatch detect(String text) => detector.analyze(text);

  /// Whether [point] is scanned under the current switches.
  static bool isScanned(SafetyInputPoint point) =>
      !point.newInT7 || PhaseAConfig.current.safetyScanAllInputs;

  /// T8 — whether [checkUserTextClassified] would ask the classifier for
  /// [point].  False whenever the switch is off: callers then keep calling
  /// the synchronous [checkUserText], so nothing changes, timing included:
  ///
  /// ```dart
  /// final r = safety.classifierActiveFor(point)
  ///     ? await safety.checkUserTextClassified(text, point: point, ...)
  ///     : safety.checkUserText(text, point: point, ...);
  /// ```
  bool classifierActiveFor(SafetyInputPoint point) =>
      classifier != null &&
      PhaseAConfig.current.safetyClassifierEnabled &&
      point.classifiable &&
      isScanned(point);

  /// [checkUserText] with the classifier: lexicon first; unless it already
  /// says acute (nothing higher to find, and the crisis page must not
  /// wait), ask the classifier for at most
  /// `PhaseAConfig.safetyClassifierTimeoutMs`; keep the higher level; then
  /// write one `safety_events` doc for the turn (with `detector` and the
  /// classifier fields).  On timeout or failure: the lexicon result and
  /// one fallback log row.  Falls through to [checkUserText] when
  /// [classifierActiveFor] is false.
  Future<SafetyCheckResult> checkUserTextClassified(
    String text, {
    required SafetyInputPoint point,
    String? uid,
    String? agentId,
    String? sessionId,
    String? turnId,
  }) async {
    final c = classifier;
    if (c == null || !classifierActiveFor(point)) {
      return checkUserText(text,
          point: point,
          uid: uid,
          agentId: agentId,
          sessionId: sessionId,
          turnId: turnId);
    }
    final id = turnId ?? newTurnId();
    final lexicon = detect(text);
    ClassifierVerdict? verdict;
    if (lexicon.level != DistressLevel.acute && text.trim().isNotEmpty) {
      verdict = await _classify(c, text, point: point, turnId: id, uid: uid);
    }
    final match =
        verdict == null ? lexicon : mergeClassifierVerdict(lexicon, verdict);
    final queued = _write(
      match: match,
      text: text,
      source: point.source,
      point: point,
      uid: uid,
      agentId: agentId,
      sessionId: sessionId,
      turnId: id,
      // Null when the classifier was not asked (lexicon acute / empty).
      classifier: verdict,
      detector: verdict == null ? 'lexicon' : detectorLabel(lexicon, verdict),
    );
    return SafetyCheckResult(
      match: match,
      point: point,
      scanned: true,
      eventQueued: queued,
      turnId: id,
      classifier: verdict,
    );
  }

  Future<ClassifierVerdict> _classify(
    SafetyClassifier c,
    String text, {
    required SafetyInputPoint point,
    required String turnId,
    String? uid,
  }) async {
    final timeout =
        Duration(milliseconds: PhaseAConfig.current.safetyClassifierTimeoutMs);
    final sw = Stopwatch()..start();
    ClassifierVerdict verdict;
    try {
      verdict = await c
          .classify(text,
              inputPoint: point.code,
              source: point.source.code,
              turnId: turnId)
          .timeout(timeout);
    } on TimeoutException {
      verdict = ClassifierVerdict(
          status: ClassifierStatus.clientTimeout,
          latencyMs: sw.elapsedMilliseconds);
    } catch (_) {
      verdict = ClassifierVerdict(
          status: ClassifierStatus.clientError,
          latencyMs: sw.elapsedMilliseconds);
    }
    if (verdict.status == ClassifierStatus.clientTimeout ||
        verdict.status == ClassifierStatus.clientError) {
      classifierLog?.record(
        status: verdict.status,
        inputPoint: point.code,
        source: point.source.code,
        turnId: turnId,
        latencyMs: sw.elapsedMilliseconds,
        uid: uid,
      );
    }
    return verdict;
  }

  /// Detect, and write one `safety_events` doc when moderate or above.
  /// Returns synchronously; the write is fire-and-forget.  Does not route.
  SafetyCheckResult checkUserText(
    String text, {
    required SafetyInputPoint point,
    String? uid,
    String? agentId,
    String? sessionId,
    String? turnId,
  }) {
    final id = turnId ?? newTurnId();
    if (!isScanned(point)) {
      return SafetyCheckResult(
        match: const DistressMatch(DistressLevel.none),
        point: point,
        scanned: false,
        eventQueued: false,
        turnId: id,
      );
    }
    final match = detect(text);
    final queued = _write(
      match: match,
      text: text,
      source: point.source,
      point: point,
      uid: uid,
      agentId: agentId,
      sessionId: sessionId,
      turnId: id,
    );
    return SafetyCheckResult(
      match: match,
      point: point,
      scanned: true,
      eventQueued: queued,
      turnId: id,
    );
  }

  /// Scan an AI reply of the turn [turnId].  Writes an `ai_output_scan`
  /// event only when the reply is at a higher tier than the participant's
  /// input ([inputMatch]): the input event already stands for the turn
  /// otherwise (one turn = one event; the server merges the rest).
  SafetyCheckResult checkAiOutput(
    String text, {
    required String turnId,
    required DistressMatch inputMatch,
    required SafetyInputPoint point,
    String? uid,
    String? agentId,
    String? sessionId,
  }) {
    final match = detect(text);
    final above = match.level.index > inputMatch.level.index;
    final queued = above &&
        _write(
          match: match,
          text: text,
          source: SafetySource.aiOutputScan,
          point: point,
          uid: uid,
          agentId: agentId,
          sessionId: sessionId,
          turnId: turnId,
        );
    return SafetyCheckResult(
      match: match,
      point: point,
      scanned: true,
      eventQueued: queued,
      turnId: turnId,
    );
  }

  /// [checkUserText], then the same safety surface every page uses
  /// (crisis page for acute, support sheet for moderate_interrupt).  For
  /// form pages: call after the form is saved, so nothing is lost.
  /// Works without [CoreServicesScope] (widget tests): routing is skipped.
  Future<SafetyCheckResult> checkAndRoute(
    BuildContext context,
    String text, {
    required SafetyInputPoint point,
    String? uid,
    String? agentId,
    String? sessionId,
  }) async {
    // T8: with the classifier switch off this stays the synchronous call
    // it always was.
    if (classifierActiveFor(point)) {
      final classified = await checkUserTextClassified(text,
          point: point, uid: uid, agentId: agentId, sessionId: sessionId);
      if (!context.mounted) return classified;
      await route(context, [classified]);
      return classified;
    }
    final result = checkUserText(text,
        point: point, uid: uid, agentId: agentId, sessionId: sessionId);
    await route(context, [result]);
    return result;
  }

  /// Show the safety surface for the most severe of [results] (several
  /// fields checked separately, one surface).  No-op without
  /// [CoreServicesScope] or below moderate.
  Future<void> route(
      BuildContext context, List<SafetyCheckResult> results) async {
    if (results.isEmpty) return;
    final top = results.reduce(
        (a, b) => b.level.index > a.level.index ? b : a);
    if (top.level == DistressLevel.none) return;
    final scope =
        context.getInheritedWidgetOfExactType<CoreServicesScope>();
    if (scope == null || !context.mounted) return;
    await scope.distressRouter.route(top.match, context: context);
  }

  bool _write({
    required DistressMatch match,
    required String text,
    required SafetySource source,
    required SafetyInputPoint point,
    required String turnId,
    String? uid,
    String? agentId,
    String? sessionId,
    ClassifierVerdict? classifier,
    String? detector,
  }) {
    final w = writer;
    if (w == null || !match.isEscalation) return false;
    // ignore: discarded_futures
    w.maybeWrite(
      uid: uid,
      source: source,
      match: match,
      inputText: text,
      inputPoint: point.code,
      turnId: turnId,
      agentId: agentId,
      sessionId: sessionId,
      classifier: classifier,
      detector: detector,
    );
    return true;
  }

  /// [SafetyService] of the enclosing [CoreServicesScope], or a detect-only
  /// instance when there is none (widget tests).
  static SafetyService of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CoreServicesScope>()?.safety ??
      const SafetyService();
}

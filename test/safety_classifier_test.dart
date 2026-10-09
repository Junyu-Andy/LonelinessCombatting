// T8 — the safety-classifier slot behind SafetyService
// (lib/core/safety/safety_classifier.dart, decision 0025).
//
//   - switch off (default): nothing changes — the check stays synchronous
//     (the event is queued before the first await, as before T8), the
//     classifier is never asked, the event has no classifier fields;
//   - switch on, with a fake model: normal (raise), no lowering, acute
//     skips the model, timeout and failure fall back to the lexicon and
//     log one row, server-side fallbacks log nothing on the App;
//   - both arms: the Hybrid path (LlmGateway) and the rule path
//     (checkUserTextClassified) give the same level and the same event.
//
// The fake model stands in for the `classifySafety` Cloud Function; the
// HTTP side (a real local fake model: ok / slow / failing) is tested in
// functions/test/safety_classifier_emulator_test.js.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/safety_check.dart';
import 'package:app_demo/core/safety/safety_classifier.dart';
import 'package:app_demo/core/safety/safety_event_writer.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Writer extends SafetyEventWriter {
  _Writer() : super(available: false);
  final List<Map<String, Object?>> rows = [];

  @override
  Future<void> maybeWrite({
    String? uid,
    required SafetySource source,
    required DistressMatch match,
    required String inputText,
    String? inputPoint,
    String? turnId,
    String? agentId,
    String? sessionId,
    String? detector,
    ClassifierVerdict? classifier,
  }) async {
    if (!match.isEscalation) return;
    rows.add({
      'source': source.code,
      'inputPoint': inputPoint,
      'turnId': turnId,
      'tier': match.level.tierCode,
      'detector': detector,
      'classifierStatus': classifier?.status.code,
      'classifierScore': classifier?.score,
    });
  }
}

/// The fake model: answers [level] after [delay], or throws.
class _FakeModel implements SafetyClassifier {
  _FakeModel({
    this.level = DistressLevel.none,
    this.delay = Duration.zero,
    this.status = ClassifierStatus.ok,
    this.fail = false,
  });
  final DistressLevel level;
  final Duration delay;
  final ClassifierStatus status;
  final bool fail;
  final List<String> asked = [];
  final List<String> askedTurnIds = [];

  @override
  Future<ClassifierVerdict> classify(
    String text, {
    required String inputPoint,
    required String source,
    required String turnId,
  }) async {
    asked.add(inputPoint);
    askedTurnIds.add(turnId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw StateError('model down');
    if (status != ClassifierStatus.ok) {
      return ClassifierVerdict(status: status);
    }
    return ClassifierVerdict(
        status: ClassifierStatus.ok,
        level: level,
        score: 0.87,
        modelVersion: 'fake-1');
  }
}

class _Log implements ClassifierFallbackLog {
  final List<Map<String, Object?>> rows = [];
  @override
  void record({
    required ClassifierStatus status,
    required String inputPoint,
    required String source,
    required String turnId,
    required int latencyMs,
    String? uid,
  }) =>
      rows.add({
        'status': status.code,
        'inputPoint': inputPoint,
        'turnId': turnId,
        'latencyMs': latencyMs,
      });
}

class _Client implements LlmClient {
  int calls = 0;
  @override
  Future<LlmRawResponse> complete({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
    bool regenerate = false,
    Map<String, dynamic>? agentContextSnapshot,
  }) async {
    calls++;
    return const LlmRawResponse(text: '多謝你話我知。');
  }
}

const _safe = '今日去咗飲茶。'; // lexicon: none
const _moderate = '我覺得自己好冇用。'; // lexicon: moderate
const _acute = '我真係想死，冇人理我。'; // lexicon: acute

void _on({int timeoutMs = 300}) => PhaseAConfig.current = PhaseAConfig(
    safetyClassifierEnabled: true, safetyClassifierTimeoutMs: timeoutMs);

void main() {
  tearDown(() => PhaseAConfig.current = const PhaseAConfig());

  group('switch', () {
    test('default off; read from app_config/phase_a', () {
      expect(const PhaseAConfig().safetyClassifierEnabled, isFalse);
      expect(const PhaseAConfig().safetyClassifierTimeoutMs, 1500);
      final c = PhaseAConfig.fromMap(
          {'safetyClassifierEnabled': true, 'safetyClassifierTimeoutMs': 9});
      expect(c.safetyClassifierEnabled, isTrue);
      expect(c.safetyClassifierTimeoutMs, 200, reason: 'clamped');
      expect(PhaseAConfig.fromMap({}).safetyClassifierEnabled, isFalse);
    });

    test('active only with switch on, a classifier, a participant input',
        () {
      final model = _FakeModel();
      final s = SafetyService(classifier: model);
      expect(s.classifierActiveFor(SafetyInputPoint.checkInNote), isFalse);
      _on();
      expect(s.classifierActiveFor(SafetyInputPoint.checkInNote), isTrue);
      expect(s.classifierActiveFor(SafetyInputPoint.thoughtExercise), isTrue);
      expect(s.classifierActiveFor(SafetyInputPoint.systemGenerated), isFalse);
      expect(s.classifierActiveFor(SafetyInputPoint.searchQuery), isFalse);
      expect(const SafetyService().classifierActiveFor(
              SafetyInputPoint.checkInNote),
          isFalse,
          reason: 'no classifier wired');
    });
  });

  group('switch off: behaviour and timing unchanged', () {
    test('gateway: event queued synchronously, model never asked', () async {
      final w = _Writer();
      final model = _FakeModel(level: DistressLevel.acute);
      final client = _Client();
      final f = LlmGateway(
        safety: SafetyService(writer: w, classifier: model),
        client: client,
      ).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: _moderate,
        uid: 'u',
      );
      // Before the first await: the lexicon event is already queued.
      expect(w.rows, hasLength(1));
      final r = await f;
      expect(model.asked, isEmpty);
      expect(client.calls, 1);
      expect(r.inputFlag.level, isNot(DistressLevel.acute));
      expect(w.rows.single['detector'], isNull,
          reason: 'no classifier fields on the event');
      expect(w.rows.single['classifierStatus'], isNull);
    });

    testWidgets('checkAndRoute: event queued synchronously', (tester) async {
      final w = _Writer();
      final model = _FakeModel(level: DistressLevel.acute);
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      final f = SafetyService(writer: w, classifier: model).checkAndRoute(
          ctx, _moderate,
          point: SafetyInputPoint.thoughtExercise, uid: 'u');
      expect(w.rows, hasLength(1));
      await f;
      expect(model.asked, isEmpty);
    });

    test('checkUserTextClassified falls through to checkUserText', () async {
      final w = _Writer();
      final model = _FakeModel(level: DistressLevel.acute);
      final r = await SafetyService(writer: w, classifier: model)
          .checkUserTextClassified(_safe,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(model.asked, isEmpty);
      expect(r.level, DistressLevel.none);
      expect(r.classifier, isNull);
      expect(w.rows, isEmpty);
    });
  });

  group('switch on, fake model', () {
    test('normal: raises a lexicon miss; one event, detector=classifier',
        () async {
      _on();
      final w = _Writer();
      final log = _Log();
      final r = await SafetyService(
              writer: w,
              classifier: _FakeModel(level: DistressLevel.moderateInterrupt),
              classifierLog: log)
          .checkUserTextClassified(_safe,
              point: SafetyInputPoint.checkInNote, uid: 'u', turnId: 't1');
      expect(r.level, DistressLevel.moderateInterrupt);
      expect(r.match.matchedTerm, isNull);
      expect(r.classifier!.ok, isTrue);
      expect(w.rows, hasLength(1));
      expect(w.rows.single['detector'], 'classifier');
      expect(w.rows.single['classifierStatus'], 'ok');
      expect(w.rows.single['classifierScore'], 0.87);
      expect(w.rows.single['turnId'], 't1');
      expect(log.rows, isEmpty, reason: 'the server logs normal calls');
    });

    test('never lowers: lexicon moderate, model none → moderate', () async {
      _on();
      final w = _Writer();
      final r = await SafetyService(
              writer: w, classifier: _FakeModel(level: DistressLevel.none))
          .checkUserTextClassified(_moderate,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(r.isEscalation, isTrue);
      expect(r.match.matchedTerm, isNotNull, reason: 'lexicon result kept');
      expect(w.rows.single['detector'], 'lexicon');
    });

    test('same level from both → detector=both', () async {
      _on();
      final w = _Writer();
      final lex = const DistressDetector().analyze(_moderate).level;
      await SafetyService(writer: w, classifier: _FakeModel(level: lex))
          .checkUserTextClassified(_moderate,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(w.rows.single['detector'], 'both');
    });

    test('lexicon acute: model not asked, no wait', () async {
      _on();
      final model = _FakeModel(
          level: DistressLevel.none, delay: const Duration(seconds: 5));
      final sw = Stopwatch()..start();
      final r = await SafetyService(writer: _Writer(), classifier: model)
          .checkUserTextClassified(_acute,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(r.isAcute, isTrue);
      expect(model.asked, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('timeout → lexicon only + one App log row', () async {
      _on(timeoutMs: 300);
      final w = _Writer();
      final log = _Log();
      final sw = Stopwatch()..start();
      final r = await SafetyService(
              writer: w,
              classifier: _FakeModel(
                  level: DistressLevel.acute,
                  delay: const Duration(seconds: 3)),
              classifierLog: log)
          .checkUserTextClassified(_moderate,
              point: SafetyInputPoint.reminiscenceNote,
              uid: 'u',
              turnId: 't2');
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(r.level, const DistressDetector().analyze(_moderate).level);
      expect(r.classifier!.status, ClassifierStatus.clientTimeout);
      expect(log.rows, hasLength(1));
      expect(log.rows.single['status'], 'client_timeout');
      expect(log.rows.single['inputPoint'], 'reminiscence_note');
      expect(log.rows.single['turnId'], 't2');
      expect(w.rows.single['detector'], 'lexicon');
      expect(w.rows.single['classifierStatus'], 'client_timeout');
    });

    test('default timeout is 1.5 s', () async {
      PhaseAConfig.current =
          const PhaseAConfig(safetyClassifierEnabled: true);
      final log = _Log();
      final never = _NeverModel();
      final sw = Stopwatch()..start();
      await SafetyService(classifier: never, classifierLog: log)
          .checkUserTextClassified(_safe,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(sw.elapsedMilliseconds, inInclusiveRange(1450, 2500));
      expect(log.rows.single['status'], 'client_timeout');
    });

    test('failure (throws) → lexicon only + one App log row', () async {
      _on();
      final log = _Log();
      final r = await SafetyService(
              writer: _Writer(),
              classifier: _FakeModel(fail: true),
              classifierLog: log)
          .checkUserTextClassified(_safe,
              point: SafetyInputPoint.checkInNote, uid: 'u');
      expect(r.level, DistressLevel.none);
      expect(r.classifier!.status, ClassifierStatus.clientError);
      expect(log.rows.single['status'], 'client_error');
    });

    for (final s in [
      ClassifierStatus.timeout,
      ClassifierStatus.error,
      ClassifierStatus.disabled,
    ]) {
      test('server says ${s.code} → lexicon only, no App row', () async {
        _on();
        final log = _Log();
        final r = await SafetyService(
                writer: _Writer(),
                classifier: _FakeModel(status: s),
                classifierLog: log)
            .checkUserTextClassified(_safe,
                point: SafetyInputPoint.checkInNote, uid: 'u');
        expect(r.level, DistressLevel.none);
        expect(log.rows, isEmpty, reason: 'the server logged it');
      });
    }

    test('gateway: model raise to acute short-circuits the LLM', () async {
      _on();
      final client = _Client();
      final r = await LlmGateway(
        safety: SafetyService(
            writer: _Writer(),
            classifier: _FakeModel(level: DistressLevel.acute)),
        client: client,
      ).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: _safe,
        uid: 'u',
      );
      expect(r.shortCircuited, isTrue);
      expect(client.calls, 0);
    });

    test('gateway: system-generated input is not sent to the model',
        () async {
      _on();
      final model = _FakeModel(level: DistressLevel.acute);
      await LlmGateway(
        safety: SafetyService(writer: _Writer(), classifier: model),
        client: _Client(),
      ).send(
        moduleId: 'greeting_siu_yan',
        systemPrompt: 'sys',
        history: const [],
        userInput: _safe,
        uid: 'u',
      );
      expect(model.asked, isEmpty);
    });
  });

  group('both arms through the same slot (T6 sentences)', () {
    final raw = File(
      'docs/dev-reports/T6-safety-parity-20261006-scripts/sentences.json',
    ).readAsStringSync();
    final sentences =
        (jsonDecode(raw)['sentences'] as List).cast<Map<String, dynamic>>();
    for (final s in sentences) {
      test('${s['id']}: Hybrid gateway == rule path', () async {
        _on();
        final text = s['text'] as String;
        // A fake model that flags everything moderate_interrupt.
        final wB = _Writer();
        final modelB = _FakeModel(level: DistressLevel.moderateInterrupt);
        final rB = await SafetyService(writer: wB, classifier: modelB)
            .checkUserTextClassified(text,
                point: SafetyInputPoint.checkInNote, uid: 'u');
        final wA = _Writer();
        final modelA = _FakeModel(level: DistressLevel.moderateInterrupt);
        final rA = await LlmGateway(
          safety: SafetyService(writer: wA, classifier: modelA),
          client: _Client(),
        ).send(
          moduleId: 'm2_check_in',
          systemPrompt: 'sys',
          history: const [],
          userInput: text,
          uid: 'u',
        );
        expect(rA.inputFlag.level, rB.level);
        expect(modelA.asked.length, modelB.asked.length);
        expect(wA.rows.length, wB.rows.length);
        for (var i = 0; i < wA.rows.length; i++) {
          expect(wA.rows[i]['tier'], wB.rows[i]['tier']);
          expect(wA.rows[i]['detector'], wB.rows[i]['detector']);
        }
      });
    }
  });

  // T26 (decision 0033) — the message id: the classifier call, the
  // safety event and the logged turn (`turns.safetyTurnId`) share one id,
  // in both arms.
  group('message id (both arms)', () {
    TurnRecord turn(LlmResponse r) => TurnRecord(
          agentId: 'siu_yan',
          moduleId: 'm2_check_in',
          userSent: DateTime(2026, 10, 9),
          replyShown: DateTime(2026, 10, 9),
          modality: InputModality.text,
          charCount: 3,
          detector: r.inputFlag,
          shortCircuited: false,
          ackShown: false,
          response: r,
        );

    test('Hybrid: gateway turn id = event = classifier call = turn doc',
        () async {
      _on();
      final w = _Writer();
      final model = _FakeModel(level: DistressLevel.moderateInterrupt);
      final r = await LlmGateway(
        safety: SafetyService(writer: w, classifier: model),
        client: _Client(),
      ).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: _safe,
        uid: 'u',
      );
      expect(r.turnId, isNotNull);
      expect(model.askedTurnIds, [r.turnId]);
      expect(w.rows.single['turnId'], r.turnId);
      expect(turn(r).toMap(participantId: 'u', sessionId: 's')['safetyTurnId'],
          r.turnId);
    });

    test('rule: the caller\'s id = event = classifier call = turn doc',
        () async {
      _on();
      final w = _Writer();
      final model = _FakeModel(level: DistressLevel.moderateInterrupt);
      final id = SafetyService.newTurnId();
      final c = await SafetyService(writer: w, classifier: model)
          .checkUserTextClassified(_safe,
              point: SafetyInputPoint.checkInNote, uid: 'u', turnId: id);
      expect(model.askedTurnIds, [id]);
      expect(w.rows.single['turnId'], id);
      // As RuleSubmissionFlow.record / Tung Tung B log the turn.
      final r = LlmResponse(
        text: '收到喇。',
        inputFlag: c.match,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: false,
        metadata: const TurnMetadata(agentId: 'siu_yan'),
        status: LlmStatus.ruleBased,
        turnId: id,
      );
      expect(turn(r).toMap(participantId: 'u', sessionId: 's')['safetyTurnId'],
          id);
    });

    test('switch off: the turn doc still carries the id', () async {
      final w = _Writer();
      final r = await LlmGateway(
        safety: SafetyService(writer: w),
        client: _Client(),
      ).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: _moderate,
        uid: 'u',
      );
      expect(w.rows.single['turnId'], r.turnId);
      expect(turn(r).toMap(participantId: 'u', sessionId: 's')['safetyTurnId'],
          r.turnId);
    });
  });

  group('verdict parsing', () {
    test('valid answer', () {
      final v = ClassifierVerdict.fromResponse({
        'status': 'ok',
        'level': 'acute',
        'score': 0.9,
        'modelVersion': 'lora-1',
      });
      expect(v.ok, isTrue);
      expect(v.level, DistressLevel.acute);
    });
    test('unknown level / non-map → error', () {
      expect(
          ClassifierVerdict.fromResponse({'status': 'ok', 'level': 'bad'})
              .status,
          ClassifierStatus.error);
      expect(ClassifierVerdict.fromResponse('x').status,
          ClassifierStatus.error);
      expect(ClassifierVerdict.fromResponse({'status': 'timeout'}).ok,
          isFalse);
    });
  });
}

/// A model that never answers.
class _NeverModel implements SafetyClassifier {
  @override
  Future<ClassifierVerdict> classify(
    String text, {
    required String inputPoint,
    required String source,
    required String turnId,
  }) =>
      Completer<ClassifierVerdict>().future;
}

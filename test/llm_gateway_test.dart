import 'dart:async';

import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements LlmClient {
  _FakeClient(this.canned, {this.fakeHash, this.failure});
  final String canned;
  final String? fakeHash;
  final LlmFailure? failure;
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
    if (failure != null) {
      return LlmRawResponse(text: '', failure: failure);
    }
    return LlmRawResponse(text: canned, systemPromptHash: fakeHash);
  }
}

void main() {
  group('LlmGateway', () {
    test('routes benign input to the model and returns text', () async {
      final fake = _FakeClient('多謝你同我講。');
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm3_reminiscence',
        systemPrompt: 'sys',
        history: const [],
        userInput: '我細個住喺深水埗。',
      );
      expect(fake.calls, 1);
      expect(r.text, '多謝你同我講。');
      expect(r.shortCircuited, false);
      expect(r.inputFlag.level, DistressLevel.none);
    });

    test('short-circuits on acute input and never calls the model', () async {
      final fake = _FakeClient('should not appear');
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: '我想死。',
      );
      expect(fake.calls, 0);
      expect(r.shortCircuited, true);
      expect(r.text, '');
      expect(r.inputFlag.level, DistressLevel.acute);
      expect(r.hasEscalation, true);
    });

    test('flags moderate input but still produces a model reply', () async {
      final fake = _FakeClient('聽你咁講我好心痛。');
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: '我覺得自己係個拖累。',
      );
      expect(fake.calls, 1);
      expect(r.shortCircuited, false);
      expect(r.inputFlag.level, DistressLevel.moderate);
      expect(r.hasEscalation, true);
      expect(r.text.isNotEmpty, true);
    });

    test('flags model output if model returns concerning content', () async {
      final fake = _FakeClient('你應該覺得 hopeless 都好正常。');
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm3_reminiscence',
        systemPrompt: 'sys',
        history: const [],
        userInput: '今日唔錯。',
      );
      expect(r.outputFlag.level, DistressLevel.moderate);
      expect(r.hasEscalation, true);
    });

    test('B.2: systemPromptHash is propagated from CF response to metadata',
        () async {
      const expectedHash = 'abc123hash';
      final fake = _FakeClient('好的。', fakeHash: expectedHash);
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm3_reminiscence',
        promptKey: 'siu_yan_v1',
        history: const [],
        userInput: '你好。',
      );
      expect(r.metadata.systemPromptHash, expectedHash);
      expect(r.metadata.promptKey, 'siu_yan_v1');
    });

    test('B.2: metadata has null hash when short-circuited on acute input',
        () async {
      final fake = _FakeClient('should not appear');
      final gw = LlmGateway(client: fake);
      final r = await gw.send(
        moduleId: 'm3',
        systemPrompt: 'sys',
        history: const [],
        userInput: '我想死。',
      );
      expect(r.shortCircuited, true);
      expect(r.metadata.systemPromptHash, isNull);
    });

    test('transport failure propagates on LlmResponse.failure and logs '
        'telemetry', () async {
      const failure = LlmFailure(LlmFailureCode.authExpired, 'no token');
      final fake = _FakeClient('', failure: failure);
      final events = <(String, Map<String, dynamic>)>[];
      final gw = LlmGateway(
        client: fake,
        telemetry: (event, params) => events.add((event, params)),
      );
      final r = await gw.send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        agentId: 'siu_yan',
        history: const [],
        userInput: '今日唔錯。',
      );
      expect(r.failure, isNotNull);
      expect(r.failure!.code, LlmFailureCode.authExpired);
      expect(r.text, '');
      expect(r.shortCircuited, false);
      expect(events, hasLength(1));
      expect(events.single.$1, 'llm_send_failed');
      expect(events.single.$2['code'], 'AUTH-01');
      expect(events.single.$2['moduleId'], 'm2_check_in');
      expect(events.single.$2['agentId'], 'siu_yan');
    });

    test('successful send has null failure and no telemetry', () async {
      final fake = _FakeClient('好呀。');
      final events = <String>[];
      final gw = LlmGateway(
        client: fake,
        telemetry: (event, _) => events.add(event),
      );
      final r = await gw.send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: '今日唔錯。',
      );
      expect(r.failure, isNull);
      expect(events, isEmpty);
    });
  });

  group('LlmFailure', () {
    test('maps CF error codes to the taxonomy', () {
      expect(LlmFailure.fromFunctionsCode('unauthenticated').code,
          LlmFailureCode.authExpired);
      expect(LlmFailure.fromFunctionsCode('permission-denied').code,
          LlmFailureCode.appCheckRejected);
      expect(LlmFailure.fromFunctionsCode('failed-precondition').code,
          LlmFailureCode.appCheckRejected);
      expect(LlmFailure.fromFunctionsCode('deadline-exceeded').code,
          LlmFailureCode.serverTimeout);
      expect(LlmFailure.fromFunctionsCode('unavailable').code,
          LlmFailureCode.serverTimeout);
      expect(LlmFailure.fromFunctionsCode('internal').code,
          LlmFailureCode.upstreamError);
      expect(LlmFailure.fromFunctionsCode('something-else').code,
          LlmFailureCode.unknown);
    });

    test('userMessage carries the stable code in both languages', () {
      for (final code in LlmFailureCode.values) {
        final f = LlmFailure(code);
        expect(f.userMessage(true), contains(code.code));
        expect(f.userMessage(false), contains(code.code));
      }
    });

    test('retriable flags: auth and rules failures are not retriable', () {
      expect(LlmFailureCode.authExpired.retriable, false);
      expect(LlmFailureCode.appCheckRejected.retriable, false);
      expect(LlmFailureCode.firestoreDenied.retriable, false);
      expect(LlmFailureCode.clientTimeout.retriable, true);
      expect(LlmFailureCode.serverTimeout.retriable, true);
      expect(LlmFailureCode.firestoreUnavailable.retriable, true);
    });
  });

  group('guardFirestore', () {
    test('times out a hung op with FS-02 instead of hanging forever',
        () async {
      // A write future that never completes — the "interface up, Google
      // unreachable" hang. The guard must convert it into FS-02.
      await expectLater(
        guardFirestore<void>(
          () => Completer<void>().future,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<LlmFailureException>().having(
          (e) => e.failure.code,
          'code',
          LlmFailureCode.firestoreUnavailable,
        )),
      );
    });

    test('passes through the op result when it completes in time', () async {
      final v = await guardFirestore(() async => 42);
      expect(v, 42);
    });

    test('persistQuietly swallows a failing op', () async {
      await persistQuietly(
        'test',
        () async => throw TimeoutException('x'),
      );
      // Reaching here without throwing is the assertion.
    });
  });
}

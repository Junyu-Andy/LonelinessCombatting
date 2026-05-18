import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements LlmClient {
  _FakeClient(this.canned, {this.fakeHash});
  final String canned;
  final String? fakeHash;
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
  }) async {
    calls++;
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
  });
}

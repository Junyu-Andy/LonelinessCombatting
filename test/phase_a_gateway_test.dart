/// Phase A baseline — gateway contract tests (S-6 fallback, L-2 provenance,
/// V-2 theme / module injection).
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements LlmClient {
  _Client(this.response);
  final LlmRawResponse response;
  String? lastSuffix;
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
    lastSuffix = contextSuffix;
    return response;
  }
}

void main() {
  group('S-6 fallback classification', () {
    test('transport error → status fallback with error class, empty text',
        () async {
      final gw = LlmGateway(
          client: _Client(const LlmRawResponse(text: '', error: 'timeout')));
      final r = await gw.send(
        moduleId: 'm2_check_in',
        promptKey: 'siu_yan_v1',
        agentId: 'siu_yan',
        history: const [],
        userInput: '今日去咗飲茶。',
      );
      expect(r.status, LlmStatus.fallback);
      expect(r.isFallback, true);
      expect(r.error, 'timeout');
      expect(r.text, '');
      expect(r.model, isNull);
    });

    test('empty body without transport error is still a fallback', () async {
      final gw = LlmGateway(client: _Client(const LlmRawResponse(text: '   ')));
      final r = await gw.send(
        moduleId: 'm2_check_in',
        promptKey: 'siu_yan_v1',
        agentId: 'siu_yan',
        history: const [],
        userInput: '今日去咗飲茶。',
      );
      expect(r.status, LlmStatus.fallback);
      expect(r.error, 'empty_response');
    });

    test('moderate_interrupt input still calls the model and is a fallback '
        'when the model fails (template shown by the page regardless)',
        () async {
      final client = _Client(const LlmRawResponse(text: '', error: 'cf_internal'));
      final gw = LlmGateway(client: client);
      final r = await gw.send(
        moduleId: 'm2_check_in',
        promptKey: 'siu_yan_v1',
        agentId: 'siu_yan',
        history: const [],
        userInput: '冇人理我，我係個負擔',
      );
      expect(client.calls, 1);
      expect(r.inputFlag.level, DistressLevel.moderateInterrupt);
      expect(r.inputFlag.matchedTerm, '冇人理我');
      expect(r.inputFlag.interrupts, true);
      expect(r.status, LlmStatus.fallback);
    });

    test('acute short-circuit reports status short_circuited', () async {
      final client = _Client(const LlmRawResponse(text: 'never'));
      final gw = LlmGateway(client: client);
      final r = await gw.send(
        moduleId: 'm2_check_in',
        promptKey: 'siu_yan_v1',
        agentId: 'siu_yan',
        history: const [],
        userInput: '我唔想活喇',
      );
      expect(client.calls, 0);
      expect(r.status, LlmStatus.shortCircuited);
      expect(r.status.code, 'short_circuited');
      expect(r.inputFlag.category, DistressCategory.ideation);
    });
  });

  group('L-2 provenance', () {
    test('model / temperature / promptVersion / latency propagate', () async {
      final gw = LlmGateway(
          client: _Client(const LlmRawResponse(
        text: '聽到。',
        model: 'deepseek-chat',
        temperature: 0.5,
        promptVersion: 'ah_jan_ah_bak_v1@2026-09',
        systemPromptHash: 'h',
      )));
      final r = await gw.send(
        moduleId: 'm3_reminiscence_w1',
        promptKey: 'ah_jan_ah_bak_v1',
        agentId: 'ah_jan_ah_bak',
        history: const [],
        userInput: '我細個住喺深水埗。',
      );
      expect(r.status, LlmStatus.ok);
      expect(r.model, 'deepseek-chat');
      expect(r.temperature, 0.5);
      expect(r.promptVersion, 'ah_jan_ah_bak_v1@2026-09');
      expect(r.latencyMs, isNotNull);
    });
  });

  group('V-2 theme / module injection', () {
    test('appends [今週主題] and [模組] at the END of the suffix', () {
      final out = LlmGateway.injectThemeAndModule(
        contextSuffix: '[過往摘要]\n（暫時未有）',
        theme: '工作',
        moduleId: 'm3_reminiscence_w2',
      );
      expect(out, '[過往摘要]\n（暫時未有）\n\n[今週主題] 工作\n[模組] m3_reminiscence_w2');
    });

    test('no theme → module line only; no agent → untouched', () {
      expect(LlmGateway.injectThemeAndModule(contextSuffix: null, moduleId: 'm2_check_in'),
          '[模組] m2_check_in');
      expect(LlmGateway.injectThemeAndModule(contextSuffix: 'x'), 'x');
    });

    test('gateway sends the injected suffix to the transport', () async {
      final client = _Client(const LlmRawResponse(text: 'ok'));
      final gw = LlmGateway(client: client);
      await gw.send(
        moduleId: 'm3_reminiscence_w3',
        promptKey: 'ah_jan_ah_bak_v1',
        agentId: 'ah_jan_ah_bak',
        contextSuffix: '[過往摘要]\n舊嘢',
        theme: '朋友',
        history: const [],
        userInput: '今日天氣好熱。',
      );
      expect(client.lastSuffix, endsWith('[今週主題] 朋友\n[模組] m3_reminiscence_w3'));
    });

    test('system-internal calls (no agentId) get no module line', () async {
      final client = _Client(const LlmRawResponse(text: 'ok'));
      final gw = LlmGateway(client: client);
      await gw.send(
        moduleId: 'rolling_summary_fold',
        systemPrompt: 'sys',
        contextSuffix: null,
        history: const [],
        userInput: 'x',
        skipSafetyScan: true,
      );
      expect(client.lastSuffix, isNull);
    });
  });
}

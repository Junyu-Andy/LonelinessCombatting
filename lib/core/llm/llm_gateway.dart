import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../safety/distress_detector.dart';

/// Unified LLM entry point for every Arm A module. All LLM calls in the app
/// MUST go through this gateway so that:
///   1. Distress detection runs on both the user input and the model output
///      before anything is shown to the user.
///   2. A post-generation content filter can be added in one place.
///   3. Conversation logs are tagged with module + agent for the 10%
///      random safety audit and per-agent PPR analysis.
///
/// Sprint 2 extends [send] with agent persona resolution:
///   - [agentId]      — registry id; tagged on the request for audit
///   - [promptKey]    — server-resolved prompt key (e.g. `siu_yan_v1`)
///   - [variantName]  — substituted into `{{VARIANT_NAME}}` server-side
///   - [contextSuffix]— appended after the persona prompt server-side
///   - [systemPrompt] — legacy raw prompt path, still honoured
///
/// Arm B modules MUST NOT call this gateway. They use static templates.
class LlmGateway {
  LlmGateway({
    DistressDetector? detector,
    LlmClient? client,
  })  : _detector = detector ?? const DistressDetector(),
        _client = client ?? const DeepseekLlmClient();

  final DistressDetector _detector;
  final LlmClient _client;

  /// Send a request through the gateway. Returns an [LlmResponse] with the
  /// model text and any safety flags raised either on the user input or the
  /// output.
  ///
  /// Either [systemPrompt] OR [promptKey] must be provided. When both are
  /// passed, the server prefers [promptKey] and falls back to
  /// [systemPrompt] when the key cannot be resolved (e.g. an older Cloud
  /// Function deployment that doesn't ship the prompts bundle yet).
  Future<LlmResponse> send({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
  }) async {
    assert(
      systemPrompt != null || promptKey != null,
      'LlmGateway.send requires either systemPrompt or promptKey',
    );

    final inputFlag = _detector.analyze(userInput);

    // Acute distress: short-circuit. The module is responsible for showing
    // the crisis surface; we never let an LLM be the only thing standing
    // between a user in acute distress and the resources they need.
    if (inputFlag.level == DistressLevel.acute) {
      return LlmResponse(
        text: '',
        inputFlag: inputFlag,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: true,
      );
    }

    final raw = await _client.complete(
      moduleId: moduleId,
      systemPrompt: systemPrompt,
      promptKey: promptKey,
      agentId: agentId,
      variantName: variantName,
      contextSuffix: contextSuffix,
      history: history,
      userInput: userInput,
    );
    final outputFlag = _detector.analyze(raw);
    final filtered = _postFilter(raw);

    return LlmResponse(
      text: filtered,
      inputFlag: inputFlag,
      outputFlag: outputFlag,
      shortCircuited: false,
    );
  }

  /// Stub post-generation filter. For Sprint 0 this only strips obvious model
  /// artefacts; richer policy checks (interpretive overreach, unsolicited
  /// reframing) belong here once clinical sign-off lands.
  String _postFilter(String text) {
    final trimmed = text.trim();
    return trimmed;
  }
}

class LlmTurn {
  final bool fromUser;
  final String text;
  const LlmTurn({required this.fromUser, required this.text});
}

class LlmResponse {
  final String text;
  final DistressMatch inputFlag;
  final DistressMatch outputFlag;

  /// True when the gateway refused to call the model because the input
  /// triggered an acute safety flag. The caller MUST surface crisis resources
  /// instead of showing model text.
  final bool shortCircuited;

  const LlmResponse({
    required this.text,
    required this.inputFlag,
    required this.outputFlag,
    required this.shortCircuited,
  });

  bool get hasEscalation =>
      shortCircuited || inputFlag.isEscalation || outputFlag.isEscalation;
}

/// Pluggable transport for the gateway. Lets tests swap in a fake without
/// touching network code.
abstract class LlmClient {
  Future<String> complete({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
  });
}

class DeepseekLlmClient implements LlmClient {
  const DeepseekLlmClient();

  @override
  Future<String> complete({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
  }) async {
    try {
      final payload = <String, dynamic>{
        'messages': [
          for (final t in history)
            {
              'role': t.fromUser ? 'user' : 'assistant',
              'content': t.text,
            },
          {
            'role': 'user',
            'content': userInput,
          },
        ],
        'moduleId': moduleId,
      };
      if (systemPrompt != null) payload['systemPrompt'] = systemPrompt;
      if (promptKey != null) payload['promptKey'] = promptKey;
      if (agentId != null) payload['agentId'] = agentId;
      if (variantName != null) payload['variantName'] = variantName;
      if (contextSuffix != null) payload['contextSuffix'] = contextSuffix;

      final result = await FirebaseFunctions
          .instanceFor(region: 'asia-east2')
          .httpsCallable('proxyDeepSeek')
          .call(payload)
          .timeout(const Duration(seconds: 25));

      final data = result.data;
      if (data is Map) {
        return data['text'] as String? ?? '';
      }
    } on FirebaseFunctionsException {
      // Caller treats empty text as fallback signal.
    } catch (_) {
      // Caller treats empty text as fallback signal.
    }

    return '';
  }
}

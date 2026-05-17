import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../safety/distress_detector.dart';

/// Unified LLM entry point for every Arm A module. All LLM calls in the app
/// MUST go through this gateway so that:
///   1. Distress detection runs on both the user input and the model output
///      before anything is shown to the user.
///   2. A post-generation content filter can be added in one place.
///   3. Conversation logs are tagged with the module ID + arm for the 10%
///      random safety audit (per Spec §Backend and data).
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
  /// [moduleId] is one of the spec module identifiers (e.g. `m3_reminiscence`,
  /// `m4_cog_restructure`, `m7_action_loop`). Used for audit tagging.
  Future<LlmResponse> send({
    required String moduleId,
    required String systemPrompt,
    required List<LlmTurn> history,
    required String userInput,
  }) async {
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
    required String systemPrompt,
    required List<LlmTurn> history,
    required String userInput,
  });
}

class DeepseekLlmClient implements LlmClient {
  const DeepseekLlmClient();

  @override
  Future<String> complete({
    required String moduleId,
    required String systemPrompt,
    required List<LlmTurn> history,
    required String userInput,
  }) async {
    try {
      final result = await FirebaseFunctions
          .instanceFor(region: 'asia-east2')
          .httpsCallable('proxyDeepSeek')
          .call(<String, dynamic>{
        'systemPrompt': systemPrompt,
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
      }).timeout(const Duration(seconds: 25));

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
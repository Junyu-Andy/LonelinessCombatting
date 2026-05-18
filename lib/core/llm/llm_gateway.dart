import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../safety/distress_detector.dart';
import '../safety/safety_event_writer.dart';
import 'turn_metadata.dart';

export 'turn_metadata.dart';

/// Unified LLM entry point for every Arm A module. All LLM calls in the app
/// MUST go through this gateway so that:
///   1. Distress detection runs on both the user input and the model output
///      before anything is shown to the user.
///   2. A post-generation content filter can be added in one place.
///   3. Conversation logs are tagged with module + agent for the 10%
///      random safety audit and per-agent PPR analysis.
///   4. (B.7) Safety events are written to Firestore for PI alerting.
///   5. (B.2) System-prompt hash is returned from the CF and surfaced on
///      [LlmResponse.metadata] for callers to persist on the turn doc.
///
/// Arm B modules MUST NOT call this gateway. They use static templates
/// and write [TurnMetadata.armB] directly when persisting turns.
class LlmGateway {
  LlmGateway({
    DistressDetector? detector,
    LlmClient? client,
    SafetyEventWriter? safetyWriter,
  })  : _detector = detector ?? const DistressDetector(),
        _client = client ?? const DeepseekLlmClient(),
        _safetyWriter = safetyWriter;

  final DistressDetector _detector;
  final LlmClient _client;

  /// Null when Firebase is unavailable (guest mode). Safety events are
  /// silently skipped; detection still runs so the app can short-circuit.
  final SafetyEventWriter? _safetyWriter;

  /// Send a request through the gateway. Returns an [LlmResponse] with the
  /// model text, any safety flags raised, and the per-turn metadata.
  ///
  /// Either [systemPrompt] OR [promptKey] must be provided. When both are
  /// passed, the server prefers [promptKey] and falls back to [systemPrompt].
  Future<LlmResponse> send({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
    String? uid,
    String? sessionId,
  }) async {
    assert(
      systemPrompt != null || promptKey != null,
      'LlmGateway.send requires either systemPrompt or promptKey',
    );

    final inputFlag = _detector.analyze(userInput);

    if (inputFlag.isEscalation) {
      await _safetyWriter?.maybeWrite(
        uid: uid ?? '',
        source: SafetySource.gatewayInput,
        match: inputFlag,
        inputText: userInput,
        agentId: agentId,
        sessionId: sessionId,
      );
    }

    // Acute distress: short-circuit. The module is responsible for showing
    // the crisis surface; we never let an LLM be the only thing standing
    // between a user in acute distress and the resources they need.
    if (inputFlag.level == DistressLevel.acute) {
      return LlmResponse(
        text: '',
        inputFlag: inputFlag,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: true,
        metadata: TurnMetadata(
          agentId: agentId,
          sessionId: sessionId,
        ),
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

    final outputFlag = _detector.analyze(raw.text);
    final filtered = _postFilter(raw.text);

    if (outputFlag.isEscalation) {
      await _safetyWriter?.maybeWrite(
        uid: uid ?? '',
        source: SafetySource.gatewayOutput,
        match: outputFlag,
        inputText: raw.text,
        agentId: agentId,
        sessionId: sessionId,
      );
    }

    return LlmResponse(
      text: filtered,
      inputFlag: inputFlag,
      outputFlag: outputFlag,
      shortCircuited: false,
      metadata: TurnMetadata(
        systemPromptHash: raw.systemPromptHash,
        promptKey: promptKey,
        agentId: agentId,
        sessionId: sessionId,
      ),
    );
  }

  String _postFilter(String text) => text.trim();
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
  final bool shortCircuited;

  /// B.2 — per-turn metadata to be persisted by the caller on the turn doc.
  final TurnMetadata metadata;

  const LlmResponse({
    required this.text,
    required this.inputFlag,
    required this.outputFlag,
    required this.shortCircuited,
    required this.metadata,
  });

  bool get hasEscalation =>
      shortCircuited || inputFlag.isEscalation || outputFlag.isEscalation;
}

/// Raw response from the LLM transport, including the server-side hash.
class LlmRawResponse {
  final String text;
  final String? systemPromptHash;
  const LlmRawResponse({required this.text, this.systemPromptHash});
}

/// Pluggable transport for the gateway. Lets tests swap in a fake without
/// touching network code.
abstract class LlmClient {
  Future<LlmRawResponse> complete({
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
        return LlmRawResponse(
          text: data['text'] as String? ?? '',
          systemPromptHash: data['systemPromptHash'] as String?,
        );
      }
    } on FirebaseFunctionsException {
      // Caller treats empty text as fallback signal.
    } catch (_) {
      // Caller treats empty text as fallback signal.
    }

    return const LlmRawResponse(text: '');
  }
}

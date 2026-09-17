import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../features/llm_features/data/llm_turn_features.dart';
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
    LlmTurnFeaturesRepository? featuresRepo,
  })  : _detector = detector ?? const DistressDetector(),
        _client = client ?? const DeepseekLlmClient(),
        _safetyWriter = safetyWriter,
        _featuresRepo = featuresRepo;

  final DistressDetector _detector;
  final LlmClient _client;

  /// Null when Firebase is unavailable (guest mode). Safety events are
  /// silently skipped; detection still runs so the app can short-circuit.
  final SafetyEventWriter? _safetyWriter;

  /// B.1 — when set, the gateway writes a [LlmTurnFeatures] doc for every
  /// successful Arm A response.  Null disables the persistence (e.g. guest
  /// mode, or callers that don't want to opt in).
  final LlmTurnFeaturesRepository? _featuresRepo;

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
    /// B.9 — when true, the request is a repair regeneration.  The CF treats
    /// it as a fresh call (no caching) and the client links the original
    /// turn ref to the repair via [LlmResponse] downstream.
    bool regenerate = false,
    /// B.1 — optional agentContext snapshot for the CF flag detector.
    Map<String, dynamic>? agentContextSnapshot,
    /// B.1 — pass 'A' to persist LlmTurnFeatures, anything else skips.
    /// (Arm B should not call the gateway at all per design, but this guard
    /// keeps the schema clean if a misroute happens.)
    String? armCode,
    /// System-internal calls (e.g. the session-end rolling-summary fold)
    /// pass true: their "input" is a transcript whose every turn was
    /// already distress-scanned live when the user typed it, so scanning
    /// again (a) wrote a duplicate, mislabelled safety event minutes
    /// after the real one and (b) short-circuited the fold on any acute
    /// term, discarding that session's memory.  Never set this for
    /// live user input.
    bool skipSafetyScan = false,
    /// V-2 — this week's reminiscence theme.  When set, the gateway appends
    /// `[今週主題] {theme}` to the context suffix so the Ah Jan prompt's
    /// theme lock actually receives the value its "Context injection" block
    /// promises.  `[模組] {moduleId}` is appended for every agent call.
    String? theme,
  }) async {
    assert(
      systemPrompt != null || promptKey != null,
      'LlmGateway.send requires either systemPrompt or promptKey',
    );

    final inputFlag = skipSafetyScan
        ? const DistressMatch(DistressLevel.none)
        : _detector.analyze(userInput);

    if (inputFlag.isEscalation) {
      // Fire-and-forget on purpose: offline, a Firestore write future
      // waits for server ack, and awaiting it here would let a dropped
      // connection stand between an acutely distressed user and the
      // crisis surface.  The SDK queues the event locally and syncs it
      // when the network returns; the UI routing below must never wait.
      final w = _safetyWriter;
      if (w != null) {
        unawaited(w.maybeWrite(
          uid: uid ?? '',
          source: SafetySource.gatewayInput,
          match: inputFlag,
          inputText: userInput,
          agentId: agentId,
          sessionId: sessionId,
        ));
      }
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
        status: LlmStatus.shortCircuited,
      );
    }

    // V-2 — theme / module_id injection (Phase A baseline).  Appended at the
    // END of the suffix so the persona prompt's declared context order
    // (summary → entities → threads → theme → module) is preserved.
    final injected = injectThemeAndModule(
      contextSuffix: contextSuffix,
      theme: theme,
      moduleId: agentId == null ? null : moduleId,
    );

    final sw = Stopwatch()..start();
    final raw = await _client.complete(
      moduleId: moduleId,
      systemPrompt: systemPrompt,
      promptKey: promptKey,
      agentId: agentId,
      variantName: variantName,
      contextSuffix: injected,
      history: history,
      userInput: userInput,
      regenerate: regenerate,
      agentContextSnapshot: agentContextSnapshot,
    );
    sw.stop();
    final latencyMs = sw.elapsedMilliseconds;

    final outputFlag = skipSafetyScan
        ? const DistressMatch(DistressLevel.none)
        : _detector.analyze(raw.text);
    final filtered = _postFilter(raw.text);

    if (outputFlag.isEscalation) {
      // Same non-blocking rationale as the input-side write above.
      final w = _safetyWriter;
      if (w != null) {
        unawaited(w.maybeWrite(
          uid: uid ?? '',
          source: SafetySource.gatewayOutput,
          match: outputFlag,
          inputText: raw.text,
          agentId: agentId,
          sessionId: sessionId,
        ));
      }
    }

    // B.1 — persist features for Arm A successful turns.  Arm B turns
    // never reach this codepath (per design), but the armCode guard keeps
    // the schema clean if a misroute happens.
    if (_featuresRepo != null &&
        uid != null && uid.isNotEmpty &&
        agentId != null &&
        raw.text.trim().isNotEmpty &&
        raw.llmFlags.isNotEmpty) {
      final features = LlmTurnFeatures.fromCloudFunctionPayload(
        agentId: agentId,
        moduleId: moduleId,
        systemPromptHash: raw.systemPromptHash,
        raw: raw.llmFlags,
        latencyMs: latencyMs,
      );
      // ignore unawaited — fire-and-forget so latency stays on the UI path.
      _featuresRepo!.write(
        uid: uid,
        isArmA: armCode == 'A',
        features: features,
      );
    }

    // S-6 — an empty body with no transport error is still a failure from
    // the participant's point of view (nothing to show); classify it so the
    // page shows the per-agent fallback line and the turn logs
    // `llm.status = fallback`.
    final error = raw.error ?? (filtered.isEmpty ? 'empty_response' : null);

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
      llmFlags: raw.llmFlags,
      status: error == null ? LlmStatus.ok : LlmStatus.fallback,
      error: error,
      model: raw.model,
      latencyMs: latencyMs,
      temperature: raw.temperature,
      promptVersion: raw.promptVersion,
    );
  }

  String _postFilter(String text) => text.trim();

  /// V-2 — pure helper (unit-tested) that appends the two injection lines.
  static String? injectThemeAndModule({
    String? contextSuffix,
    String? theme,
    String? moduleId,
  }) {
    final lines = <String>[
      if (theme != null && theme.trim().isNotEmpty) '[今週主題] ${theme.trim()}',
      if (moduleId != null && moduleId.trim().isNotEmpty)
        '[模組] ${moduleId.trim()}',
    ];
    if (lines.isEmpty) return contextSuffix;
    final base = (contextSuffix ?? '').trim();
    return base.isEmpty ? lines.join('\n') : '$base\n\n${lines.join('\n')}';
  }
}

/// S-6 — outcome of one gateway call as recorded in `turns.llm.status`.
enum LlmStatus {
  ok,
  fallback,
  shortCircuited;

  String get code => switch (this) {
        LlmStatus.ok => 'ok',
        LlmStatus.fallback => 'fallback',
        LlmStatus.shortCircuited => 'short_circuited',
      };
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

  /// B.1 — raw flag bundle from the CF detector.  Use
  /// [LlmTurnFeatures.fromCloudFunctionPayload] to persist.  Empty for
  /// short-circuited and failed responses.
  final Map<String, dynamic> llmFlags;

  /// S-6 — `ok` / `fallback` / `short_circuited`.
  final LlmStatus status;

  /// S-6 — error class when [status] is [LlmStatus.fallback]
  /// (`timeout` / `cf_<code>` / `network` / `empty_response` / `bad_shape`).
  final String? error;

  /// L-2 — DeepSeek response-body `model` field, verbatim.  Null on
  /// fallback / short-circuit.
  final String? model;

  /// Gateway round-trip in ms (client-side stopwatch).  Null when the
  /// model was not called.
  final int? latencyMs;

  /// Decoding temperature the CF used (per-agent constant echoed back).
  final double? temperature;

  /// `siu_yan_v1@2026-06`-style prompt version echoed by the CF.
  final String? promptVersion;

  const LlmResponse({
    required this.text,
    required this.inputFlag,
    required this.outputFlag,
    required this.shortCircuited,
    required this.metadata,
    this.llmFlags = const {},
    this.status = LlmStatus.ok,
    this.error,
    this.model,
    this.latencyMs,
    this.temperature,
    this.promptVersion,
  });

  /// True when the page should show the per-agent S-6 fallback line
  /// instead of [text].
  bool get isFallback => status == LlmStatus.fallback;

  bool get hasEscalation =>
      shortCircuited || inputFlag.isEscalation || outputFlag.isEscalation;
}

/// Raw response from the LLM transport, including the server-side hash
/// and B.1 mechanism-of-change flags.
class LlmRawResponse {
  final String text;
  final String? systemPromptHash;

  /// B.1 — 5-flag mechanism bundle returned by `proxyDeepSeek`.  Keys are
  /// `personalization_specific`, `memory_callback`, `empathic_reflection`,
  /// `open_question`, `adaptive_register`, plus `_version: int`.  Empty map
  /// when the response failed or the CF doesn't yet ship the detector.
  final Map<String, dynamic> llmFlags;

  /// S-6 — transport / upstream error class; null on success.
  final String? error;

  /// L-2 — DeepSeek `model` field from the response body.
  final String? model;
  final double? temperature;
  final String? promptVersion;

  const LlmRawResponse({
    required this.text,
    this.systemPromptHash,
    this.llmFlags = const {},
    this.error,
    this.model,
    this.temperature,
    this.promptVersion,
  });
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
    bool regenerate = false,
    Map<String, dynamic>? agentContextSnapshot,
  });
}

class DeepseekLlmClient implements LlmClient {
  const DeepseekLlmClient();

  /// Tester hook (T-11): `flutter run --dart-define=FORCE_LLM_FALLBACK=true`
  /// makes every call fail as `forced_fallback` so the S-6 fallback line,
  /// `llm.status = fallback` and the interrupt-template-on-fallback path can
  /// be exercised without breaking the network or the DeepSeek key.  A real
  /// airplane-mode test never reaches this client: the chat pages hold the
  /// message offline and auto-resend on reconnect.
  static const bool forceFallback =
      bool.fromEnvironment('FORCE_LLM_FALLBACK', defaultValue: false);

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
    if (forceFallback) {
      return const LlmRawResponse(text: '', error: 'forced_fallback');
    }
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
      if (regenerate) payload['regenerate'] = true;
      if (agentContextSnapshot != null) {
        payload['agentContext'] = agentContextSnapshot;
      }

      final result = await FirebaseFunctions
          .instanceFor(region: 'asia-east2')
          .httpsCallable('proxyDeepSeek')
          .call(payload)
          // Matches CF-side 55s; client times out a hair earlier so the
          // user sees a fallback ack rather than a hung spinner.
          .timeout(const Duration(seconds: 50));

      final data = result.data;
      if (data is Map) {
        final flagsRaw = data['llmFlags'];
        final flags = flagsRaw is Map
            ? Map<String, dynamic>.from(flagsRaw)
            : const <String, dynamic>{};
        return LlmRawResponse(
          text: data['text'] as String? ?? '',
          systemPromptHash: data['systemPromptHash'] as String?,
          llmFlags: flags,
          model: data['model'] as String?,
          temperature: (data['temperature'] as num?)?.toDouble(),
          promptVersion: data['promptVersion'] as String?,
        );
      }
      // Unexpected response shape — log so it's visible.
      if (kDebugMode) {
        debugPrint('[LlmGateway] unexpected response shape: $data');
      }
      return const LlmRawResponse(text: '', error: 'bad_shape');
    } on FirebaseFunctionsException catch (e, st) {
      // Surface CF errors instead of swallowing them.  Common causes:
      //   - unauthenticated: user not signed in (auth gate broken)
      //   - permission-denied / failed-precondition: App Check rejected
      //     the call.  Re-check enforceAppCheck or register a debug
      //     token in Firebase Console → App Check → Apps.
      //   - internal: DeepSeek upstream error.  The CF now embeds the
      //     status + first 400 chars of the body in e.message.
      //   - deadline-exceeded: the model took > 55s; usually means the
      //     prompt is too long or the network blipped.
      if (kDebugMode) {
        debugPrint('[LlmGateway] FirebaseFunctionsException '
            'code=${e.code} message=${e.message}');
        debugPrintStack(stackTrace: st);
      }
      // S-6 — `deadline-exceeded` is the CF-side 55 s timeout; `internal`
      // wraps DeepSeek 4xx/5xx; `unavailable` is a network drop.
      return LlmRawResponse(text: '', error: 'cf_${e.code}');
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[LlmGateway] CF call timed out after 50s');
      }
      return const LlmRawResponse(text: '', error: 'timeout');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[LlmGateway] unexpected error: $e');
        debugPrintStack(stackTrace: st);
      }
      return const LlmRawResponse(text: '', error: 'network');
    }
  }
}

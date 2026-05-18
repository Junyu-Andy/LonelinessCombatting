/// Cross-referral routing service (Dev Req §5).
///
/// Composes the three layers:
///   1. KeywordFilter — client-side keyword/entity match.
///   2. referralJudgement Cloud Function — LLM SURFACE/DEFER/SKIP.
///   3. CooldownManager — 10 turn / 24h suppression.
///
/// Returns a [SurfacedReferral] when (and only when) all three layers
/// agree on surfacing. The caller renders the suggestion card and on
/// accept hands off to the target agent via [HandoffExecutor].
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../features/auth/data/user_profile.dart';
import '../agent_context/shared_context_service.dart';
import '../llm/llm_gateway.dart';
import 'cooldown_manager.dart';
import 'keyword_filter.dart';
import 'triggers_config.dart';

class SurfacedReferral {
  final ReferralMatch match;
  final String suggestionText;

  const SurfacedReferral({
    required this.match,
    required this.suggestionText,
  });
}

/// Telemetry callback the routing service invokes on every decision it
/// makes (per layer).  Lets the host app fire analytics events without
/// the routing service depending on AnalyticsService directly.
///
/// `phase`: 'layer1_match' | 'layer2_decision' | 'cooldown_blocked' |
///          'surfaced'
/// `params`: layer-specific context (fromAgent, toAgent, matchedPhraseLen,
///           decision, etc.)  No raw user text — only hashes / lengths.
typedef ReferralTelemetry = void Function(
  String phase,
  Map<String, dynamic> params,
);

class ReferralRoutingService {
  ReferralRoutingService({
    required this.sharedContext,
    KeywordFilter? filter,
    CooldownManager? cooldown,
    this.telemetry,
  })  : _filter = filter ?? const KeywordFilter(),
        _cooldown = cooldown ?? CooldownManager();

  final SharedContextService sharedContext;
  final KeywordFilter _filter;
  final CooldownManager _cooldown;

  /// Optional callback fired at each routing-layer decision (Phase A
  /// calibration data — Open Q F.1 / DMP layer 4).  No PII.
  final ReferralTelemetry? telemetry;

  /// Public so callers can advance the turn counter on every user
  /// message even when no candidacy fires.
  void onUserTurn(String sourceAgentId) =>
      _cooldown.onUserTurn(sourceAgentId);

  /// Try to surface a referral. Returns null when any layer says no.
  ///
  /// [recentTurns] is the conversation history (last ≤10) passed to
  /// Layer 2 so the LLM judges in context.
  Future<SurfacedReferral?> maybeSurface({
    required String sourceAgentId,
    required UserProfile? profile,
    required String userTurn,
    required List<LlmTurn> recentTurns,
    required String localeCode,
  }) async {
    if (_cooldown.forAgent(sourceAgentId).isActive) {
      telemetry?.call('cooldown_blocked', {
        'fromAgent': sourceAgentId,
      });
      return null;
    }
    final match = _filter.scan(turn: userTurn, sourceAgentId: sourceAgentId);
    if (match == null) return null;

    // Layer 1 match — phase A calibration of keyword filter recall.
    telemetry?.call('layer1_match', {
      'fromAgent': sourceAgentId,
      'toAgent': match.trigger.targetAgentId,
      'matchedTextLen': match.matchedPhrase.length,
    });

    final decision = await _layer2Decision(
      sourceAgentId: sourceAgentId,
      targetAgentId: match.trigger.targetAgentId,
      matchedText: match.matchedPhrase,
      recentTurns: recentTurns,
      profile: profile,
      localeCode: localeCode,
    );
    if (decision == null) return null;
    telemetry?.call('layer2_decision', {
      'fromAgent': sourceAgentId,
      'toAgent': match.trigger.targetAgentId,
      'decision': decision.decision, // SURFACE | DEFER | SKIP
    });
    if (decision.decision != 'SURFACE') return null;
    if (decision.suggestion.trim().isEmpty) return null;

    _cooldown.recordSurfaced(sourceAgentId);

    telemetry?.call('surfaced', {
      'fromAgent': sourceAgentId,
      'toAgent': match.trigger.targetAgentId,
    });

    final surfaced = SurfacedReferral(
      match: match,
      suggestionText: decision.suggestion.trim(),
    );

    // Persist as pending so the target agent can greet on arrival.
    if (profile != null) {
      final id = '${DateTime.now().millisecondsSinceEpoch}';
      await sharedContext.addPendingReferral(
        uid: profile.uid,
        referral: PendingReferral(
          id: id,
          fromAgent: sourceAgentId,
          toAgent: match.trigger.targetAgentId,
          triggerSnippet: userTurn,
          suggestionText: decision.suggestion.trim(),
          proposedAt: DateTime.now(),
        ),
      );
    }

    return surfaced;
  }

  Future<_JudgementDecision?> _layer2Decision({
    required String sourceAgentId,
    required String targetAgentId,
    required String matchedText,
    required List<LlmTurn> recentTurns,
    required UserProfile? profile,
    required String localeCode,
  }) async {
    try {
      final result = await FirebaseFunctions
          .instanceFor(region: 'asia-east2')
          .httpsCallable('referralJudgement')
          .call(<String, dynamic>{
        'sourceAgentId': sourceAgentId,
        'targetAgentId': targetAgentId,
        'matchedText': matchedText,
        'locale': localeCode,
        'variantName': _variantNameFor(profile),
        'recentTurns': [
          for (final t in recentTurns.skip(
            recentTurns.length > 10 ? recentTurns.length - 10 : 0,
          ))
            {
              'role': t.fromUser ? 'user' : 'assistant',
              'content': t.text,
            },
        ],
      }).timeout(const Duration(seconds: 12));
      final data = result.data;
      if (data is! Map) return null;
      return _JudgementDecision(
        decision: (data['decision'] as String?) ?? 'SKIP',
        suggestion: (data['suggestion'] as String?) ?? '',
      );
    } on FirebaseFunctionsException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _variantNameFor(UserProfile? profile) {
    final v = profile?.ahJanAhBakVariant;
    if (v == null) return null;
    return v.code == 'masculine' ? '阿伯' : '阿珍';
  }
}

class _JudgementDecision {
  final String decision;
  final String suggestion;
  const _JudgementDecision({
    required this.decision,
    required this.suggestion,
  });
}

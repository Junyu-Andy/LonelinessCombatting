/// Inline card that surfaces a cross-referral suggestion to the user
/// (Dev Req §5.4). Render below the current agent's last bubble; on
/// accept, route to the target agent via [HandoffExecutor].
library;

import 'package:flutter/material.dart';

import '../../features/analytics/presentation/analytics_scope.dart';
import '../agent_context/shared_context_service.dart';
import '../agents/agent_avatar.dart';
import '../agents/agent_registry.dart';
import 'handoff_executor.dart';
import 'referral_routing_service.dart';

class ReferralSuggestionCard extends StatefulWidget {
  final SurfacedReferral surfaced;
  final HandoffExecutor handoffExecutor;
  final VoidCallback onDismiss;

  /// B.3 — the agent whose surface is currently rendering this card.
  /// Used for the `fromAgent` field on cross_referral_* analytics events.
  /// Optional for back-compat with existing call sites; callers should
  /// pass it for the events to fire with full fidelity.
  final String? sourceAgentId;

  const ReferralSuggestionCard({
    super.key,
    required this.surfaced,
    required this.handoffExecutor,
    required this.onDismiss,
    this.sourceAgentId,
  });

  @override
  State<ReferralSuggestionCard> createState() => _ReferralSuggestionCardState();
}

class _ReferralSuggestionCardState extends State<ReferralSuggestionCard> {
  bool _offerLogged = false;

  @override
  void initState() {
    super.initState();
    // B.3 — fire cross_referral_offered exactly once per mount.  The
    // matched text is pre-truncated to 32 chars + length so analytics
    // never carries the full user phrase (PII boundary).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_offerLogged || !mounted) return;
      _offerLogged = true;
      final fromAgent = widget.sourceAgentId ?? 'unknown';
      final matched = widget.surfaced.match.matchedPhrase;
      final prefix = matched.length > 32 ? matched.substring(0, 32) : matched;
      await AnalyticsScope.of(context).logCrossReferralOffered(
        fromAgent: fromAgent,
        toAgent: widget.surfaced.match.trigger.targetAgentId,
        matchedTextLen: matched.length,
        matchedTextPrefix32: prefix,
      );
    });
  }

  Future<void> _onAccept() async {
    final fromAgent = widget.sourceAgentId ?? 'unknown';
    await AnalyticsScope.of(context).logCrossReferralAccepted(
      fromAgent: fromAgent,
      toAgent: widget.surfaced.match.trigger.targetAgentId,
    );
    widget.onDismiss();
    if (!mounted) return;
    await widget.handoffExecutor.handoff(
      context: context,
      match: widget.surfaced.match,
    );
  }

  Future<void> _onDecline() async {
    final fromAgent = widget.sourceAgentId ?? 'unknown';
    await AnalyticsScope.of(context).logCrossReferralDeclined(
      fromAgent: fromAgent,
      toAgent: widget.surfaced.match.trigger.targetAgentId,
    );
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final target =
        AgentRegistry.tryById(widget.surfaced.match.trigger.targetAgentId);
    if (target == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        color: target.accentColor.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AgentAvatar(agent: target, size: 36),
                  const SizedBox(width: 10),
                  Text(
                    isEn ? 'Talk to ' : '搵 ',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    isEn
                        ? target.resolveVariant(null).displayNameEn
                        : target.resolveVariant(null).displayNameZh,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: target.accentColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    isEn ? '?' : '？',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.surfaced.suggestionText,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: target.accentColor,
                      ),
                      onPressed: _onAccept,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          isEn ? 'Go talk to them' : '好，過去傾',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _onDecline,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          isEn ? 'Not now' : '唔使住',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-of-page welcome banner shown when the user arrives via a
/// handoff. Provides the "Siu Yan said you were thinking about…"
/// context so the target agent can pick up the thread without
/// re-narrating.
class ReferralArrivalBanner extends StatelessWidget {
  final PendingReferral referral;
  final VoidCallback onDismiss;

  const ReferralArrivalBanner({
    super.key,
    required this.referral,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final from = AgentRegistry.tryById(referral.fromAgent);
    final fromName = from == null
        ? referral.fromAgent
        : (isEn
            ? from.resolveVariant(null).displayNameEn
            : from.resolveVariant(null).displayNameZh);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEn
                  ? '$fromName said you were thinking about something. '
                      'Want to start there?'
                  : '$fromName 話你諗緊一啲嘢。要唔要由嗰度開始？',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

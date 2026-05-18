/// Home tab's three-agent tile strip (Developer Requirements §2.2).
///
/// Each tile is a large card showing the agent's avatar, display name,
/// one-line subtitle, and accent. Tapping the tile routes into the
/// agent's primary entry surface (Sprint 1: existing M2 / M3 pages plus
/// a placeholder for Tung Tung until the dedicated feature folder
/// lands in Sprint 4).
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../../reminiscence/presentation/pages/reminiscence_landing.dart';

class AgentTileRow extends StatelessWidget {
  const AgentTileRow({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        children: [
          for (final agent in AgentRegistry.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AgentTile(
                agent: agent,
                selectedVariant:
                    agent.id == AgentRegistry.ahJanAhBakId
                        ? profile?.ahJanAhBakVariant
                        : null,
                onTap: () => _openAgent(context, agent),
              ),
            ),
        ],
      ),
    );
  }

  void _openAgent(BuildContext context, AgentDefinition agent) {
    Widget destination;
    switch (agent.id) {
      case AgentRegistry.siuYanId:
        destination = const CheckInPage();
        break;
      case AgentRegistry.ahJanAhBakId:
        destination = const ReminiscenceLandingPage();
        break;
      case AgentRegistry.tungTungId:
        destination = const TungTungPage();
        break;
      default:
        destination = const TungTungPage();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }
}

class _AgentTile extends StatelessWidget {
  final AgentDefinition agent;
  final AgentGenderVariant? selectedVariant;
  final VoidCallback onTap;

  const _AgentTile({
    required this.agent,
    required this.selectedVariant,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final variant = agent.resolveVariant(selectedVariant);
    final displayName =
        isEn ? variant.displayNameEn : variant.displayNameZh;
    final subtitle = isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: agent.accentColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: agent.accentColor.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              AgentAvatar(
                agent: agent,
                selectedVariant: selectedVariant,
                size: 72,
                openProfileOnTap: true,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 32,
                color: agent.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tung Tung's dedicated surface lands in Sprint 4. Until then the
/// agent tile routes to a friendly placeholder so the IA stays valid.
class _TungTungComingSoon extends StatelessWidget {
  const _TungTungComingSoon();

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final agent = AgentRegistry.byId(AgentRegistry.tungTungId);
    final variant = agent.resolveVariant(null);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? variant.displayNameEn : variant.displayNameZh),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AgentAvatar(agent: agent, size: 96),
              const SizedBox(height: 18),
              Text(
                isEn ? 'Tung Tung is on the way' : '通通即將上線',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                isEn
                    ? 'Tung Tung\'s curious chat and lookup features '
                        'will arrive in the next update.'
                    : '通通嘅興趣傾偈同搜尋功能會喺下次更新嗰陣上線。',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

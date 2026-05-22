/// Home tab's three-agent tile strip (Developer Requirements §2.2).
///
/// Warm-restyle pass: white "person cards" with a soft warm shadow.
/// Each agent has a coloured ring + soft halo behind the avatar and a
/// pill "傾偈" call-to-action button on the right. The whole card is
/// still tappable.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../app/app_theme.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../../reminiscence/presentation/pages/reminiscence_landing.dart';

class _AgentPalette {
  final Color halo;
  final Color ring;
  final Color pillBg;
  final Color pillFg;
  const _AgentPalette({
    required this.halo,
    required this.ring,
    required this.pillBg,
    required this.pillFg,
  });
}

_AgentPalette _paletteFor(String agentId) {
  switch (agentId) {
    case AgentRegistry.siuYanId:
      return const _AgentPalette(
        halo: Color(0xFFFAECE7),
        ring: Color(0xFFE0A98E),
        pillBg: Color(0xFFE8A98D),
        pillFg: Color(0xFF5A2410),
      );
    case AgentRegistry.ahJanAhBakId:
      return const _AgentPalette(
        halo: Color(0xFFEEEDFE),
        ring: Color(0xFFB3ACDE),
        pillBg: Color(0xFFB3ACDE),
        pillFg: Color(0xFF2A2454),
      );
    case AgentRegistry.tungTungId:
      return const _AgentPalette(
        halo: Color(0xFFE1F5EE),
        ring: Color(0xFF7FCBAE),
        pillBg: Color(0xFF7FCBAE),
        pillFg: Color(0xFF04342C),
      );
  }
  return const _AgentPalette(
    halo: Color(0xFFF1ECE6),
    ring: Color(0xFFBDB1A4),
    pillBg: Color(0xFFBDB1A4),
    pillFg: Color(0xFF2E251D),
  );
}

class AgentTileRow extends StatelessWidget {
  const AgentTileRow({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              isEn
                  ? 'Who would you like to talk with?'
                  : '想搵邊位傾下？',
              style: const TextStyle(
                color: Color(0xFFA3978A),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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
    final palette = _paletteFor(agent.id);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [AppTheme.softCardShadow],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.halo,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.ring, width: 2.5),
                  ),
                  child: AgentAvatar(
                    agent: agent,
                    selectedVariant: selectedVariant,
                    size: 72,
                    openProfileOnTap: true,
                  ),
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
                const SizedBox(width: 10),
                _TalkPill(
                  label: isEn ? 'Talk' : '傾偈',
                  bg: palette.pillBg,
                  fg: palette.pillFg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TalkPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _TalkPill({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 14,
          fontWeight: FontWeight.w500,
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

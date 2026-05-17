/// Lightweight avatar widget for agent tiles and chat bubbles.
///
/// Tries to render the registry's `avatarAsset` PNG; if the asset is
/// missing (Sprint 1 ships without the final robot illustrations) it
/// falls back to a coloured circle showing the agent's first character.
///
/// Pass [openProfileOnTap]: true to make the avatar tappable — it
/// opens the agent's profile page (Agent Profile spec §1). Default
/// false so the widget is safe to drop into purely decorative
/// surfaces (the onboarding deck, the first-intro dialog) where a
/// tap would be unexpected.
library;

import 'package:flutter/material.dart';

import '../../features/agent_profile/ui/agent_profile_screen.dart';
import 'agent_registry.dart';

class AgentAvatar extends StatelessWidget {
  final AgentDefinition agent;
  final AgentGenderVariant? selectedVariant;
  final double size;

  /// When true, wrap the avatar in a tap target that routes to the
  /// agent's profile screen.
  final bool openProfileOnTap;

  const AgentAvatar({
    super.key,
    required this.agent,
    this.selectedVariant,
    this.size = 56,
    this.openProfileOnTap = false,
  });

  @override
  Widget build(BuildContext context) {
    final variant = agent.resolveVariant(selectedVariant);
    final initial = variant.displayNameZh.isNotEmpty
        ? variant.displayNameZh.characters.first
        : variant.displayNameEn.characters.first;

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: agent.accentColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );

    final picture = ClipOval(
      child: Image.asset(
        variant.avatarAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );

    if (!openProfileOnTap) return picture;

    return Semantics(
      button: true,
      label: '${variant.displayNameZh} 個人資料',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          AgentProfileScreen.route(agent.id),
        ),
        child: picture,
      ),
    );
  }
}

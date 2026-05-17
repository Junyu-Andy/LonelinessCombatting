/// Lightweight avatar widget for agent tiles and chat bubbles.
///
/// Tries to render the registry's `avatarAsset` PNG; if the asset is
/// missing (Sprint 1 ships without the final robot illustrations) it
/// falls back to a coloured circle showing the agent's first character.
/// This keeps the registry declarative and the UI portable across
/// asset-availability states.
library;

import 'package:flutter/material.dart';

import 'agent_registry.dart';

class AgentAvatar extends StatelessWidget {
  final AgentDefinition agent;
  final AgentGenderVariant? selectedVariant;
  final double size;

  const AgentAvatar({
    super.key,
    required this.agent,
    this.selectedVariant,
    this.size = 56,
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

    return ClipOval(
      child: Image.asset(
        variant.avatarAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

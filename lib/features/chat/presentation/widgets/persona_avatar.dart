import 'package:flutter/material.dart';

import '../../data/chat_models.dart';

/// Visual identity for a chat persona. Uses pure-Material icons so we don't
/// need image assets — each persona gets its own gradient + icon + accent.
///
/// Wrapped in a [Hero] so the avatar physically flies from the chat landing
/// card to the chat page header.
class PersonaAvatar extends StatelessWidget {
  final ChatPersona persona;
  final double size;
  final bool hero;

  const PersonaAvatar({
    super.key,
    required this.persona,
    this.size = 64,
    this.hero = true,
  });

  @override
  Widget build(BuildContext context) {
    final spec = personaVisual(persona);
    final inner = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: spec.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: spec.gradient.last.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(spec.icon, color: Colors.white, size: size * 0.55),
    );
    if (!hero) return inner;
    return Hero(tag: 'persona-${persona.name}', child: inner);
  }
}

class PersonaVisual {
  final IconData icon;
  final List<Color> gradient;
  final Color accent;
  final Color bubbleColor;
  final String displayName;
  final String tagline;

  const PersonaVisual({
    required this.icon,
    required this.gradient,
    required this.accent,
    required this.bubbleColor,
    required this.displayName,
    required this.tagline,
  });
}

PersonaVisual personaVisual(ChatPersona persona) {
  switch (persona) {
    case ChatPersona.casual:
      return const PersonaVisual(
        icon: Icons.emoji_emotions_outlined,
        gradient: [Color(0xFFFFB199), Color(0xFFFF8C66)],
        accent: Color(0xFFFF8C66),
        bubbleColor: Color(0xFFFFF1EA),
        displayName: '阿暖',
        tagline: '想吹水？我陪你。',
      );
    case ChatPersona.consult:
      return const PersonaVisual(
        icon: Icons.psychology_alt_outlined,
        gradient: [Color(0xFF6E8AFF), Color(0xFF3F5FE3)],
        accent: Color(0xFF3F5FE3),
        bubbleColor: Color(0xFFE8EEFF),
        displayName: '李醫師',
        tagline: '想認真傾下？我喺度。',
      );
  }
}

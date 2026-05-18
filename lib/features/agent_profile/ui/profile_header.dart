/// Top portion of the agent profile page (Spec §2 + §3).
///
/// Renders the full-body image centred at 60% of screen width, the
/// display name (H1), and the role tagline (H3). The image asset
/// falls back to a coloured circle showing the agent's first character
/// when the PNG isn't shipped yet — keeps the page rendering until
/// the artist drops the assets in.
library;

import 'package:flutter/material.dart';

import '../controller/agent_profile_controller.dart';

class ProfileHeader extends StatelessWidget {
  final AgentProfileResolution resolution;
  final VoidCallback? onChangeVariant;

  const ProfileHeader({
    super.key,
    required this.resolution,
    this.onChangeVariant,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size.width;
    final imageSize = (screen * 0.6).clamp(180.0, 360.0);
    final header = resolution.header;

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        children: [
          Semantics(
            label: header.altText,
            image: true,
            child: SizedBox(
              width: imageSize,
              height: imageSize,
              child: Image.asset(
                header.fullBodyImageAsset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _FallbackArtwork(
                  initial: header.displayName.characters.first,
                  accent: resolution.accent,
                  size: imageSize,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            header.displayName,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            header.roleTagline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onChangeVariant != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onChangeVariant,
              child: Text(
                resolution.variant?.code == 'masculine'
                    ? '想換成阿珍？'
                    : '想換成阿伯？',
                style: TextStyle(
                  fontSize: 14,
                  color: resolution.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  final String initial;
  final Color accent;
  final double size;

  const _FallbackArtwork({
    required this.initial,
    required this.accent,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            accent.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

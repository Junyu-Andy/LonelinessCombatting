import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../self_reflection/presentation/pages/self_reflection_page.dart';
import '../../../social_suggestions/presentation/pages/social_suggestions_page.dart';

/// Two chips under the check-in hero — one tap into M5 reflection, one
/// into M6 social suggestion. Identical in both arms (the inside of
/// each module is where the arm split lives).
class MicroActionRow extends StatelessWidget {
  const MicroActionRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _MicroChip(
            icon: Icons.psychology_alt_outlined,
            label: l10n.todayMicroReflection,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SelfReflectionPage(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MicroChip(
            icon: Icons.celebration_outlined,
            label: l10n.todayMicroInvitation,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SocialSuggestionsPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MicroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MicroChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          // UX-polish: vertical padding bumped 18→24 so the tap
          // target clears 80pt comfortably; icon size dropped 28→24
          // so the chip sits visually below the CheckInHeroCard in
          // the Today hierarchy.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Row(
            children: [
              Icon(icon,
                  size: 24, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

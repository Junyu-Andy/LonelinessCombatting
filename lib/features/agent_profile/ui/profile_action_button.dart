/// Bottom CTA: 「同{agent}傾偈」(Spec §6).
///
/// Filled button using the agent's accent colour, minimum 56pt touch
/// target, full-width with 16pt horizontal padding. The contrast
/// adjustment picks white or dark text per WCAG AA on the accent
/// colour.
library;

import 'package:flutter/material.dart';

class ProfileActionButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onPressed;

  const ProfileActionButton({
    super.key,
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final fg = _readableForeground(accent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: onPressed,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Pick black or white based on perceived luminance so the CTA
  /// label remains readable across all three agent accents.
  Color _readableForeground(Color c) {
    final r = ((c.r * 255).round() & 0xff) / 255.0;
    final g = ((c.g * 255).round() & 0xff) / 255.0;
    final b = ((c.b * 255).round() & 0xff) / 255.0;
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance > 0.6 ? Colors.black87 : Colors.white;
  }
}

import 'package:flutter/material.dart';

/// Highlighted placeholder shown where a real illustration / photograph
/// would be rendered once the asset is available. The `description` field
/// is the brief that designers / illustrators can use to produce the asset.
///
/// Visual style: solid amber border + image icon, deliberately distinct
/// from the rest of the UI so reviewers can spot missing artwork at a glance.
class FigurePlaceholder extends StatelessWidget {
  final String description;
  final double height;
  final IconData icon;

  const FigurePlaceholder({
    super.key,
    required this.description,
    this.height = 160,
    this.icon = Icons.image_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.amber.shade700;
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '插圖位（待補圖）',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.brown.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

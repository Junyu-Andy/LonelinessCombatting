import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';

/// 1020m 一 — one big tool card on 做啲嘢 (`homeLayoutV2Enabled`):
/// Junyu's picture on its coloured tile, a title and one line, an arrow.
/// The whole card is one tap target; text wraps at any size.
class MeToolCard extends StatelessWidget {
  final String image;
  final Color tileColor;

  /// Shown if the picture cannot load.
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const MeToolCard({
    super.key,
    required this.image,
    required this.tileColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// Side of the picture tile.
  /// 72 so the longest title (望一望心入面) stays on one line on a 360-wide
  /// phone at the largest App text (1.30).
  static const double imageTileSize = 72;

  /// Margin inside the tile on each side (8%, as the batch 3 list).
  static const double imageInset = imageTileSize * 0.08;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: const [AppTheme.softCardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
              child: Row(
                children: [
                  Container(
                    width: imageTileSize,
                    height: imageTileSize,
                    padding: const EdgeInsets.all(imageInset),
                    decoration: BoxDecoration(
                      color: tileColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Image.asset(
                      image,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                      // A missing file must never break the tab.
                      errorBuilder: (_, __, ___) => Icon(icon,
                          size: 36, color: cs.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 26, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Spacious list row used across the Me tab. ≥ 64pt touch target,
/// icon + label + subtitle + chevron — never icon-only.
///
/// 1020 batch 3 (`homeLayoutV2Enabled`): with [image] the left side is a
/// rounded square in [tileColor] holding the picture with ~8% margin on
/// each side (Junyu's final tool art); without it, the Material [icon] as
/// before.
class MeListItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  /// Asset path of the tool picture (assets/tools/…), or null.
  final String? image;

  /// The tile colour behind [image].
  final Color? tileColor;

  const MeListItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.image,
    this.tileColor,
  });

  /// Side of the picture tile.
  static const double imageTileSize = 60;

  /// Margin inside the tile on each side (8%).
  static const double imageInset = imageTileSize * 0.08;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picture = image;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                if (picture != null)
                  Container(
                    width: imageTileSize,
                    height: imageTileSize,
                    padding: const EdgeInsets.all(imageInset),
                    decoration: BoxDecoration(
                      color: tileColor ?? theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Image.asset(
                      picture,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                      // A missing file must never break the tab.
                      errorBuilder: (_, __, ___) => Icon(icon,
                          size: 28,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  )
                else
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon,
                        size: 28, color: theme.colorScheme.onPrimaryContainer),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 28, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

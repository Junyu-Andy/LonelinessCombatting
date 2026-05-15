import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// P4.4 — elder-friendly button wrapper. Forces:
///   - a non-empty text label (icon-only buttons are forbidden for
///     primary actions; older participants need the wording).
///   - touch target ≥ [AppSpacing.minTouchTarget].
///   - readable label text size (bumped above the default).
///
/// Three flavors mirror Material's intent ladder but give us a single
/// place to evolve the elderly UX baseline:
///   - [AppButton.primary] — the main action on a page (filled).
///   - [AppButton.secondary] — a parallel option (tonal).
///   - [AppButton.tertiary] — a low-emphasis alternative (text).
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final _AppButtonKind kind;
  final bool destructive;
  final bool expand;

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.expand = true,
  }) : kind = _AppButtonKind.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  })  : kind = _AppButtonKind.secondary,
        destructive = false;

  const AppButton.tertiary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  })  : kind = _AppButtonKind.tertiary,
        destructive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = icon == null ? null : Icon(icon, size: 24);
    final labelWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );

    final minSize = expand
        ? const Size(double.infinity, AppSpacing.minTouchTarget)
        : const Size(0, AppSpacing.minTouchTarget);

    Widget button;
    switch (kind) {
      case _AppButtonKind.primary:
        final style = FilledButton.styleFrom(
          minimumSize: minSize,
          backgroundColor: destructive ? theme.colorScheme.error : null,
          foregroundColor: destructive ? theme.colorScheme.onError : null,
        );
        button = iconWidget == null
            ? FilledButton(onPressed: onPressed, style: style, child: labelWidget)
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: labelWidget,
              );
        break;
      case _AppButtonKind.secondary:
        final style = FilledButton.styleFrom(
          minimumSize: minSize,
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
        );
        button = iconWidget == null
            ? FilledButton.tonal(
                onPressed: onPressed, style: style, child: labelWidget)
            : FilledButton.tonalIcon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: labelWidget,
              );
        break;
      case _AppButtonKind.tertiary:
        final style = TextButton.styleFrom(minimumSize: minSize);
        button = iconWidget == null
            ? TextButton(onPressed: onPressed, style: style, child: labelWidget)
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: labelWidget,
              );
        break;
    }
    return button;
  }
}

enum _AppButtonKind { primary, secondary, tertiary }

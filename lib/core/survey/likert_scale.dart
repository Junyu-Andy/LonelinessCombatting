import 'package:flutter/material.dart';

/// Shared agree/disagree Likert selector used across the self-report
/// instruments (Weekly PR = 7-point, PPR brief + Agent Diff traits =
/// 5-point) so they read as one visual system instead of each page
/// rolling its own boxes / dots.
///
/// One horizontal row of [points] numbered circles with optional anchor
/// labels underneath the two ends. Nothing is pre-selected when [value] is
/// null. For scales whose every point has its own distinct meaning (e.g.
/// PGIC "much better … much worse"), use a labelled vertical list instead —
/// this widget only labels the two endpoints.
class LikertScale extends StatelessWidget {
  /// Number of points (typically 5 or 7).
  final int points;

  /// Currently selected value (1..points), or null when unanswered.
  final int? value;

  final ValueChanged<int> onChanged;

  /// Anchor labels under the low (1) and high ([points]) ends, plus an
  /// optional midpoint anchor (used by Brief PR's 1–7 items: 完全唔係咁 ·
  /// 一半半 · 完全係咁).
  final String? lowLabel;
  final String? midLabel;
  final String? highLabel;

  const LikertScale({
    super.key,
    required this.points,
    required this.value,
    required this.onChanged,
    this.lowLabel,
    this.midLabel,
    this.highLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int n = 1; n <= points; n++)
              _Dot(
                n: n,
                selected: value == n,
                onTap: () => onChanged(n),
              ),
          ],
        ),
        if (lowLabel != null || midLabel != null || highLabel != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  lowLabel ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (midLabel != null)
                Expanded(
                  child: Text(
                    midLabel!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  highLabel ?? '',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final int n;
  final bool selected;
  final VoidCallback onTap;

  const _Dot({required this.n, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          border: Border.all(
            color:
                selected ? theme.colorScheme.primary : theme.colorScheme.outline,
            width: 1.6,
          ),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

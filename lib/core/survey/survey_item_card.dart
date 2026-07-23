import 'package:flutter/material.dart';

/// Shared card wrapper for one survey item — the exact look of the Weekly PR
/// item cards (surface fill, 16-radius, outlineVariant border, 16 padding,
/// 18pt medium-weight statement) so every instrument reads as one system.
class SurveyItemCard extends StatelessWidget {
  /// The item statement / prompt. Rendered with the shared style; pass a
  /// custom [titleWidget] instead when rich text (bolding) is needed.
  final String? title;
  final Widget? titleWidget;

  /// The response control (e.g. a LikertScale).
  final Widget child;

  const SurveyItemCard({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
  }) : assert(title != null || titleWidget != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleWidget ??
              Text(
                title!,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

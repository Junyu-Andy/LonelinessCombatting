import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// P4.4 — elder-friendly loading affordance. Required to carry a
/// short message so the user isn't left guessing what's happening
/// (spec §UX: "never show a bare spinner").
///
/// Use [AppLoadingIndicator.inline] when you're embedding the
/// indicator inside an existing column; use the default constructor
/// when it should fill its parent (e.g. inside a Scaffold body).
class AppLoadingIndicator extends StatelessWidget {
  final String message;
  final bool inline;

  const AppLoadingIndicator({
    super.key,
    required this.message,
    this.inline = false,
  });

  const AppLoadingIndicator.inline({
    super.key,
    required this.message,
  }) : inline = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        AppSpacing.vItem,
        Text(
          message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.itemGap),
        child: Center(child: content),
      );
    }
    return Center(child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sectionGap),
      child: content,
    ));
  }
}

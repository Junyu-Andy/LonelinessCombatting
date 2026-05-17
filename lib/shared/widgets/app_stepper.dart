import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// P4.4 — top-of-page progress strip for multi-step flows
/// (M3 4-step session, M7 plan articulation, etc.).
///
/// Renders "Step N of M" + an optional step label + a linear bar so
/// older participants know how much further the flow goes.
class AppStepper extends StatelessWidget {
  /// 0-indexed current step.
  final int currentStep;

  /// Total number of steps in the flow (≥ 1).
  final int totalSteps;

  /// Optional inline label for the current step (e.g. "Where").
  final String? stepLabel;

  const AppStepper({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    assert(totalSteps >= 1, 'AppStepper needs at least one step');
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final clamped = currentStep.clamp(0, totalSteps - 1);
    final stepText = isEn
        ? 'Step ${clamped + 1} of $totalSteps'
        : '第 ${clamped + 1} 步 / 共 $totalSteps 步';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePaddingHorizontal,
        vertical: AppSpacing.gapSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                stepText,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (stepLabel != null) ...[
                const Spacer(),
                Text(
                  stepLabel!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          AppSpacing.vSmall,
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (clamped + 1) / totalSteps,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';

/// Phase 1 placeholder: Today's active M7 plan banner. The real provider
/// (Firestore-backed stream of plans scheduled for today) lands in P2.5;
/// for now this widget reads a hardcoded mock through [debugPlan]. When
/// the mock is null we render nothing — Today should stay calm.
class ActivePlanBanner extends StatelessWidget {
  /// P1 dev hook. Pass a non-null [MockTodayPlan] to preview the banner.
  /// P2.5 will replace this with a real provider.
  final MockTodayPlan? debugPlan;

  const ActivePlanBanner({super.key, this.debugPlan});

  @override
  Widget build(BuildContext context) {
    final plan = debugPlan;
    if (plan == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final timeLabel =
        '${plan.hour.toString().padLeft(2, '0')}:${plan.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ActionLoopLandingPage(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.checklist_rtl_outlined,
                    size: 30,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.todayActivePlanLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEn
                            ? '$timeLabel · ${plan.summary}'
                            : '$timeLabel　${plan.summary}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 28,
                    color: theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MockTodayPlan {
  final int hour;
  final int minute;
  final String summary;
  const MockTodayPlan({
    required this.hour,
    required this.minute,
    required this.summary,
  });
}

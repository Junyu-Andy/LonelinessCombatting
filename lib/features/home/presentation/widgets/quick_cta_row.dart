import 'package:flutter/material.dart';

import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../progress/presentation/pages/progress_page.dart';
import '../../../reminiscence/presentation/pages/reminiscence_landing.dart';

/// Three-button row of the most-used surfaces, placed near the top of
/// Home so the demo flow doesn't require diving into "All". Same order
/// in both arms.
class QuickCtaRow extends StatelessWidget {
  const QuickCtaRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    Widget cta({
      required IconData icon,
      required String label,
      required Widget page,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => page),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 32, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          cta(
            icon: Icons.mood_outlined,
            label: isEn ? 'Check-in' : '今日 Check-in',
            page: const CheckInPage(),
          ),
          cta(
            icon: Icons.auto_stories_outlined,
            label: isEn ? 'Life stories' : '人生點滴',
            page: const ReminiscenceLandingPage(),
          ),
          cta(
            icon: Icons.checklist_rtl_outlined,
            label: isEn ? 'Small steps' : '小行動',
            page: const ActionLoopLandingPage(),
          ),
        ],
      ),
    );
  }
}

/// Compact M9 progress card for Home: tap to go to the full view.
class ProgressMiniCard extends StatelessWidget {
  const ProgressMiniCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProgressPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn ? 'See your week' : '睇你嘅一個禮拜',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'Mood, plans, and reminiscence at a glance.'
                          : '心情、計劃、人生點滴，一眼睇晒。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 28, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

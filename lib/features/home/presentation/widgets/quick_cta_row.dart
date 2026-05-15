import 'package:flutter/material.dart';

import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../reminiscence/presentation/pages/reminiscence_landing.dart';

/// Quick-CTA row on Home. Phase 0 keeps the three-tile layout; Phase 1
/// will reshape this into the two-chip variant called for in the spec.
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

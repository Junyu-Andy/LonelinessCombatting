import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../progress/presentation/pages/progress_page.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';

/// Home Layout Spec §1 item 6 — three tool shortcuts at the bottom of
/// the home page: action loop / thought exercise / progress.  Same
/// layout in both arms.
class HomeToolShortcuts extends StatelessWidget {
  const HomeToolShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: _Shortcut(
              icon: Icons.checklist_rounded,
              label: isEn ? 'Plans' : '行動',
              onTap: () => _push(context, const ActionLoopLandingPage()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Shortcut(
              icon: Icons.lightbulb_outline,
              label: isEn ? 'Reframe' : '望一望',
              onTap: () => _push(context, const ThoughtExercisePage()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Shortcut(
              icon: Icons.bar_chart_rounded,
              label: isEn ? 'Progress' : '進度',
              onTap: () => _push(context, const ProgressPage()),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppTheme.softCardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          // 10/19: 12 → 17 pt labels and bigger icons (Junyu: too small to
          // read); colours from the theme so high contrast applies.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30, color: cs.primary),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small tool shortcut row under the agent tiles (Dev Req §2.2).
///
/// Surfaces Action Loop, Education, and Progress as one-tap entries on
/// the home tab so the user doesn't have to navigate via the Me tab for
/// the most common tools. The Me tab still hosts the full tool list.
library;

import 'package:flutter/material.dart';

import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../education/presentation/pages/education_library_page.dart';
import '../../../progress/presentation/pages/progress_page.dart';

class ToolQuickLinks extends StatelessWidget {
  const ToolQuickLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: _ToolTile(
              icon: Icons.checklist_rtl_outlined,
              label: isEn ? 'Plan' : '行動計劃',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ActionLoopLandingPage(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToolTile(
              icon: Icons.menu_book_outlined,
              label: isEn ? 'Library' : '健康知識',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EducationLibraryPage(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToolTile(
              icon: Icons.insights_outlined,
              label: isEn ? 'Progress' : '進度',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProgressPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 26, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

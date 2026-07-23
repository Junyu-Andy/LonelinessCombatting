import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/my_story_progress.dart';

class CurrentWeekHero extends StatelessWidget {
  final MyStoryProgress progress;
  const CurrentWeekHero({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final current = progress.currentWeek;
    final pct = progress.currentWeekIndex / progress.totalWeeks;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 26),
      decoration: BoxDecoration(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(32)),
        // Fixed warm gradient + dark-brown ink (same family as the home
        // hero). The old primary-based gradient turned PURE BLACK in
        // high-contrast mode (primary == black there), making the whole
        // hero an unreadable slab.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9D6BE), Color(0xFFD6B5B6)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x1F5A4334),
                  borderRadius: BorderRadius.circular(18),
                ),
                child:
                    const Icon(Icons.menu_book_outlined, size: 30, color: Color(0xFF5A4334)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.myStoryWeekProgress(
                        progress.currentWeekIndex,
                        progress.totalWeeks,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF836A55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn ? current.theme.titleEn : current.theme.titleZh,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF5A4334),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: const Color(0x335A4334),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5A4334)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../reminiscence/presentation/pages/m3_session_detail_page.dart';
import '../../data/my_story_progress.dart';

class SessionHistoryList extends StatelessWidget {
  final MyStoryProgress progress;
  const SessionHistoryList({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final completed = progress.completedWeeks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded,
                size: 26, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.myStoryHistoryHeader,
                  style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (completed.isEmpty)
          _EmptyCard(text: l10n.myStoryHistoryEmpty)
        else
          ...completed.map((w) {
            final date = w.completedAt;
            final dateLine = date != null
                ? (isEn
                    ? '${date.year}/${date.month}/${date.day}'
                    : '${date.year} 年 ${date.month} 月 ${date.day} 日')
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => M3SessionDetailPage(theme: w.theme),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${w.theme.weekIndex}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEn ? w.theme.titleEn : w.theme.titleZh,
                                style: theme.textTheme.titleMedium,
                              ),
                              if (dateLine != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  dateLine,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (w.summarySnippet != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  w.summarySnippet!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 26,
                            color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

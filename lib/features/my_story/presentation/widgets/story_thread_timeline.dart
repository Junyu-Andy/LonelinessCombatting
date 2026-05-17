import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/my_story_progress.dart';

/// Horizontal timeline of completed-vs-future weeks. The visual sense of
/// "narrative arc accumulating" is the M3 motivational hook — completed
/// weeks show a one-line snippet (Arm A: LLM end-summary; Arm B: theme
/// fallback), future weeks render as muted placeholders.
class StoryThreadTimeline extends StatelessWidget {
  final MyStoryProgress progress;
  const StoryThreadTimeline({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timeline_rounded,
                size: 26, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(l10n.myStoryTimelineHeader, style: theme.textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < progress.weeks.length; i++) ...[
                _TimelineNode(
                  weekIndex: progress.weeks[i].theme.weekIndex,
                  title: isEn
                      ? progress.weeks[i].theme.titleEn
                      : progress.weeks[i].theme.titleZh,
                  snippet: progress.weeks[i].summarySnippet,
                  completed: progress.weeks[i].isCompleted,
                  isCurrent: progress.weeks[i].theme.weekIndex ==
                      progress.currentWeekIndex,
                ),
                if (i != progress.weeks.length - 1)
                  Container(
                    width: 24,
                    height: 2,
                    margin: const EdgeInsets.only(top: 40),
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  final int weekIndex;
  final String title;
  final String? snippet;
  final bool completed;
  final bool isCurrent;

  const _TimelineNode({
    required this.weekIndex,
    required this.title,
    required this.snippet,
    required this.completed,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final Color dotColor;
    final Color borderColor;
    final IconData dotIcon;
    if (completed) {
      dotColor = theme.colorScheme.primary;
      borderColor = theme.colorScheme.primary;
      dotIcon = Icons.check_rounded;
    } else if (isCurrent) {
      dotColor = theme.colorScheme.primaryContainer;
      borderColor = theme.colorScheme.primary;
      dotIcon = Icons.play_arrow_rounded;
    } else {
      dotColor = theme.colorScheme.surfaceContainerHighest;
      borderColor = theme.colorScheme.outlineVariant;
      dotIcon = Icons.lock_outline_rounded;
    }

    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2.5),
            ),
            child: Icon(
              dotIcon,
              color: completed
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.myStoryWeekTitle(weekIndex),
            style: theme.textTheme.titleSmall?.copyWith(
              color: completed || isCurrent
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (snippet != null) ...[
            const SizedBox(height: 6),
            Text(
              snippet!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontStyle: FontStyle.italic,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

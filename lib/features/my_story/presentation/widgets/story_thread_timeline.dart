import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../reminiscence/data/reminiscence_themes.dart';
import '../../../reminiscence/presentation/reminiscence_router.dart';
import '../../data/my_story_progress.dart';

/// Horizontal timeline of the four themes. The visual sense of "narrative
/// arc accumulating" is the M3 motivational hook — completed themes show a
/// one-line snippet (Arm A: LLM end-summary; Arm B: theme fallback).
///
/// 10/19: no order is enforced anywhere — 人生點滴 already opens any theme
/// at any time — so no theme is drawn locked or greyed out any more (the
/// padlocks read as "not yet", and in high contrast the muted nodes went
/// all black).  Every node is readable and opens its theme when tapped,
/// exactly like the theme list in 人生點滴; both arms the same.
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
                  key: Key('story_theme_${progress.weeks[i].theme.weekIndex}'),
                  storyTheme: progress.weeks[i].theme,
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
  final ReminiscenceTheme storyTheme;
  final int weekIndex;
  final String title;
  final String? snippet;
  final bool completed;
  final bool isCurrent;

  const _TimelineNode({
    super.key,
    required this.storyTheme,
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
    final cs = theme.colorScheme;

    // Done: filled with a tick.  Not done yet: white with a play mark, the
    // same for every theme (the current week only gets a thicker ring).
    final Color dotColor = completed ? cs.primary : Colors.white;
    final Color iconColor = completed ? cs.onPrimary : cs.primary;
    final IconData dotIcon =
        completed ? Icons.check_rounded : Icons.play_arrow_rounded;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(context),
      child: SizedBox(
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
                border: Border.all(
                    color: cs.primary, width: isCurrent && !completed ? 4 : 2.5),
              ),
              child: Icon(dotIcon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.myStoryWeekTitle(weekIndex),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
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
      ),
    );
  }

  /// Same pages as the theme list in 人生點滴 (reminiscence_landing.dart).
  void _open(BuildContext context) {
    // 1020d: the v2 page when `reminiscenceV2Enabled`, else arm A / B.
    final page = ReminiscenceRouter.pageFor(context, storyTheme);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

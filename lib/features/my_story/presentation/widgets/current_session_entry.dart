import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../reminiscence/data/reminiscence_themes.dart';
import '../../../reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import '../../../reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import '../../data/my_story_progress.dart';

class CurrentSessionEntry extends StatelessWidget {
  final M3WeekState week;
  const CurrentSessionEntry({super.key, required this.week});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final (statusLabel, ctaLabel, icon) = switch (week.status) {
      MyStorySessionStatus.notStarted => (
          l10n.myStorySessionNotStarted,
          l10n.myStoryStartCta,
          Icons.play_arrow_rounded,
        ),
      MyStorySessionStatus.inProgress => (
          l10n.myStorySessionInProgress,
          l10n.myStoryContinueCta,
          Icons.arrow_forward_rounded,
        ),
      MyStorySessionStatus.completed => (
          l10n.myStorySessionCompleted,
          l10n.myStoryRereadCta,
          Icons.replay_rounded,
        ),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, week.theme),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 32,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Localizations.localeOf(context).languageCode == 'en'
                              ? week.theme.titleEn
                              : week.theme.titleZh,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _open(context, week.theme),
                  icon: Icon(icon, size: 24),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      ctaLabel,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, ReminiscenceTheme theme) {
    final isArmA = Arm.isA(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => isArmA
            ? ReminiscenceArmAPage(theme: theme)
            : ReminiscenceArmBPage(theme: theme),
      ),
    );
  }
}

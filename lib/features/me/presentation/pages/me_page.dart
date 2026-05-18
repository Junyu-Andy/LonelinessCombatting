import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';
import '../../../education/presentation/pages/education_library_page.dart';
import '../../../personalization/presentation/pages/personalization_page.dart';
import '../../../progress/presentation/pages/progress_page.dart';
import '../../../reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../widgets/me_list_item.dart';

/// Me tab — infrastructure + personal resources. Five entries, **no
/// Settings**: Settings reaches every tab via the AppBar gear.
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
        children: [
          MeListItem(
            icon: Icons.psychology_outlined,
            label: isEn ? 'Reflect with Ah Jan / Ah Bak' : '搵阿珍／阿伯傾下',
            subtitle: isEn
                ? 'Open-ended reflective chat'
                : '隨意傾下心入面諗緊嘅事',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReflectiveDialoguePage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.lightbulb_outline,
            // Phase A spec §5.2 — locked label "望一望心入面".
            label: isEn ? 'Look at a thought' : '望一望心入面',
            subtitle: isEn
                ? 'A small structured self-reflection'
                : '一個小練習，慢慢望一望自己嘅諗法',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ThoughtExercisePage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.bar_chart_outlined,
            label: l10n.meItemProgress,
            subtitle: l10n.meItemProgressSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProgressPage()),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.checklist_outlined,
            label: l10n.meItemActionLoop,
            subtitle: l10n.meItemActionLoopSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ActionLoopLandingPage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.menu_book_outlined,
            label: l10n.meItemArticles,
            subtitle: l10n.meItemArticlesSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EducationLibraryPage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.support_outlined,
            label: l10n.meItemCrisis,
            subtitle: l10n.meItemCrisisSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmergencySupportPage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            icon: Icons.person_outline,
            label: l10n.meItemProfile,
            subtitle: l10n.meItemProfileSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PersonalizationPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final ThemeData theme;
  const _Divider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        color: theme.colorScheme.outlineVariant,
        height: 1,
      ),
    );
  }
}

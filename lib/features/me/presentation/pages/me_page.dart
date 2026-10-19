/// 做啲嘢 (Do-things) — third tab per Product Overview §3.2.
///
/// Tools, non-personified:
///   - Action Loop (M7)
///   - Thought Exercise (5-field; entry point "望一望心入面")
///   - Education library (M8)
///   - Social suggestions (M6)
///
/// Personal / admin entries (Progress, Profile, Emergency, FAQ, Privacy,
/// Settings) moved to 自己 in the same restructure.
///
/// Filename retained as `me_page.dart` to avoid touching every import
/// site; the class name [MePage] is kept as a stable alias.  Internally
/// this is the "Do" tab.
///
/// 1020 batch 3 (`homeLayoutV2Enabled`): each tool gets Junyu's final
/// picture on a coloured tile ([MeToolArt]); labels unchanged; both arms
/// identical.  Off: the Material icons as before.
library;

import 'package:flutter/material.dart';

import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../education/presentation/pages/education_library_page.dart';
import '../../../social_suggestions/presentation/pages/social_suggestions_page.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../widgets/me_list_item.dart';

/// The four tool pictures (assets/tools/, 512×512 transparent PNG) and
/// their tile colours.  Only these four; older names are void.
class MeToolArt {
  MeToolArt._();

  static const thought = ('assets/tools/tool_thought.png', Color(0xFFEFE9F8));
  static const plan = ('assets/tools/tool_plan.png', Color(0xFFFCEEE0));
  static const reading = ('assets/tools/tool_reading.png', Color(0xFFE3F4EC));
  static const smallAction =
      ('assets/tools/tool_small_action.png', Color(0xFFFBE9E4));

  static const all = [thought, plan, reading, smallAction];
}

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final art = RemoteFeatureFlags.current.homeLayoutV2Enabled;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              isEn
                  ? 'Small tools you can use on your own — no companion walks you through them.'
                  : '幾個小工具，自己用都得，唔需要夥伴陪。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          MeListItem(
            key: const ValueKey('me_tool_thought'),
            icon: Icons.lightbulb_outline,
            image: art ? MeToolArt.thought.$1 : null,
            tileColor: art ? MeToolArt.thought.$2 : null,
            // Phase A spec §5.2 — locked label "望一望心入面".
            // Research Review v2 Item 5: subtitle = "了解吓自己嘅心情".
            label: isEn ? 'Look at a thought' : '望一望心入面',
            subtitle: isEn
                ? 'Gently understand your own mood'
                : '了解吓自己嘅心情',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ThoughtExercisePage(),
              ),
            ),
          ),
          _Divider(theme: theme),
          MeListItem(
            key: const ValueKey('me_tool_plan'),
            icon: Icons.checklist_outlined,
            image: art ? MeToolArt.plan.$1 : null,
            tileColor: art ? MeToolArt.plan.$2 : null,
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
            key: const ValueKey('me_tool_reading'),
            icon: Icons.menu_book_outlined,
            image: art ? MeToolArt.reading.$1 : null,
            tileColor: art ? MeToolArt.reading.$2 : null,
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
            key: const ValueKey('me_tool_small_action'),
            icon: Icons.people_outline,
            image: art ? MeToolArt.smallAction.$1 : null,
            tileColor: art ? MeToolArt.smallAction.$2 : null,
            label: isEn ? 'Social suggestions' : '一啲社交小行動',
            subtitle: isEn
                ? "Small things to try with people you already know"
                : '同你熟悉嘅人試一啲細微嘅事',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SocialSuggestionsPage(),
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

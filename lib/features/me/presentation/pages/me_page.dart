/// 做啲嘢 (Do-things) — third tab per Product Overview §3.2.
///
/// Tools, non-personified:
///   - Social suggestions (M6) — 今日小行動
///   - Action Loop (M7) — 我嘅計劃
///   - Education library (M8) — 讀少少
///   - Thought Exercise (5-field) — 望一望心入面
///
/// Personal / admin entries (Progress, Profile, Emergency, FAQ, Privacy,
/// Settings) moved to 自己 in the same restructure.
///
/// Filename retained as `me_page.dart` to avoid touching every import
/// site; the class name [MePage] is kept as a stable alias.  Internally
/// this is the "Do" tab.
///
/// 1020m 一 (10/19 第 37 条): four big cards ([MeToolCard]) in the order
/// 今日小行動 → 我嘅計劃 → 讀少少 → 望一望心入面, each with Junyu's
/// picture on its coloured tile (batch 3, [MeToolArt]) and the title and
/// line of 10/19 第 37 条 (2), and one line on top, 「自己隨時用」
/// ([MeToolsCopy]).  No switch; the old list is gone.  Same pages behind
/// the cards; both arms identical.
library;

import 'package:flutter/material.dart';

import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../education/presentation/pages/education_library_page.dart';
import '../../../social_suggestions/presentation/pages/social_suggestions_page.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../widgets/me_tool_card.dart';

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

/// 1020m 一 — the four card titles and lines (10/19 第 37 条 (2)) and the
/// line on top of the page.
class MeToolsCopy {
  MeToolsCopy._();

  static const intro = '自己隨時用';

  static const smallAction = ('今日小行動', '諗下今日可以同邊個做啲咩');
  static const plan = ('我嘅計劃', '訂個小計劃，睇返做咗未');
  static const reading = ('讀少少', '幾分鐘睇完嘅短文');
  static const thought = ('望一望心入面', '了解吓自己嘅心情');

  // Tester view in English only.
  static const introEn = 'Use them any time on your own.';
  static const smallActionEn =
      ('Small action today', 'Think of something to do with someone today');
  static const planEn = ('My plan', 'Make a small plan and see if it got done');
  static const readingEn = ('Read a little', 'Short reads, a few minutes each');
  static const thoughtEn =
      ('Look at a thought', 'Gently understand your own mood');
}

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    void open(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    (String, String) t((String, String) zh, (String, String) en) =>
        isEn ? en : zh;
    // Same keys (`me_tool_*`) as the old list, so analytics and tests that
    // find a tool by key keep working.
    final cards = [
      (
        'me_tool_small_action',
        MeToolArt.smallAction,
        Icons.people_outline,
        t(MeToolsCopy.smallAction, MeToolsCopy.smallActionEn),
        const SocialSuggestionsPage(),
      ),
      (
        'me_tool_plan',
        MeToolArt.plan,
        Icons.checklist_outlined,
        t(MeToolsCopy.plan, MeToolsCopy.planEn),
        const ActionLoopLandingPage(),
      ),
      (
        'me_tool_reading',
        MeToolArt.reading,
        Icons.menu_book_outlined,
        t(MeToolsCopy.reading, MeToolsCopy.readingEn),
        const EducationLibraryPage(),
      ),
      (
        'me_tool_thought',
        MeToolArt.thought,
        Icons.lightbulb_outline,
        t(MeToolsCopy.thought, MeToolsCopy.thoughtEn),
        const ThoughtExercisePage(),
      ),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              isEn ? MeToolsCopy.introEn : MeToolsCopy.intro,
              key: const ValueKey('me_tools_intro'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          for (final (key, art, icon, (title, line), page) in cards) ...[
            MeToolCard(
              key: ValueKey(key),
              image: art.$1,
              tileColor: art.$2,
              icon: icon,
              title: title,
              subtitle: line,
              onTap: () => open(page),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

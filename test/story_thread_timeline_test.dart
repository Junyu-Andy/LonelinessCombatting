// 10/19 — 自己 → 人生回顧: no theme is drawn locked; every theme is readable
// and can be opened in any order (as in 人生點滴).  No Firebase.
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/my_story/data/my_story_progress.dart';
import 'package:app_demo/features/my_story/presentation/widgets/story_thread_timeline.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MyStoryProgress _progress() => MyStoryProgress(
      weeks: [
        for (final t in ReminiscenceTheme.all)
          M3WeekState(
            theme: t,
            status: t.weekIndex == 1
                ? MyStorySessionStatus.completed
                : MyStorySessionStatus.notStarted,
          ),
      ],
      currentWeekIndex: 2,
    );

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: StoryThreadTimeline(progress: _progress())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in {
    'normal': AppTheme.light,
    'high contrast': AppTheme.highContrast,
  }.entries) {
    testWidgets('${entry.key}: no padlocks, every theme tappable and readable',
        (tester) async {
      await _pump(tester, entry.value);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded),
          findsNWidgets(ReminiscenceTheme.all.length - 1));
      for (final t in ReminiscenceTheme.all) {
        final node = find.byKey(Key('story_theme_${t.weekIndex}'));
        expect(node, findsOneWidget);
        expect(
            find.descendant(of: node, matching: find.byType(InkWell)),
            findsOneWidget,
            reason: 'theme ${t.weekIndex} opens on tap');
        // The theme title is drawn in the normal text colour, not muted.
        final title = tester.widget<Text>(find.text(t.titleZh));
        expect(title.style?.color, entry.value.colorScheme.onSurface);
      }
      // Not-done themes are white circles, never a dark fill.
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .toList();
      expect(circles.where((d) => d.color == Colors.white).length,
          ReminiscenceTheme.all.length - 1);
    });
  }
}

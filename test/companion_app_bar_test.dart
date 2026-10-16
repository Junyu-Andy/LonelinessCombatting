// 10/15 pilot: the top bar of the companion pages differed from page to page
// and between arms.  Now every companion page uses companionAppBar: S9
// 「今日傾到呢度」 top-left (Brief PR v2 on), avatar + companion name as the
// title, nothing top-right — on the Arm B pages too (blinding).
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rule_reply_harness.dart';

Future<void> _open(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ruleReplyHarness(page, NoLlmClient()));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final week1 = ReminiscenceTheme.all.first;

  group('Arm B pages carry the same bar as Arm A', () {
    setUp(() => PhaseBConfig.current =
        const PhaseBConfig(sessionBriefPrV2Enabled: true));
    tearDown(() => PhaseBConfig.current = const PhaseBConfig());

    testWidgets('小欣 check-in B: S9 top-left, avatar + name title, no actions',
        (tester) async {
      await _open(tester, const CheckInArmB());
      expect(find.byKey(const Key('session_close_button')), findsOneWidget);
      expect(find.byKey(const Key('companion_title')), findsOneWidget);
      expect(find.text('小欣'), findsOneWidget);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.actions ?? const [], isEmpty);
      expect(bar.leadingWidth, SessionCloseButton.leadingWidth);
    });

    testWidgets('阿珍 reminiscence B: S9 top-left, companion name title, week '
        'theme moved into the page', (tester) async {
      await _open(tester, ReminiscenceArmBPage(theme: week1));
      expect(find.byKey(const Key('session_close_button')), findsOneWidget);
      expect(find.byKey(const Key('companion_title')), findsOneWidget);
      expect(find.byKey(const Key('reminiscence_theme_title')), findsOneWidget);
      expect(find.text(week1.titleZh), findsOneWidget);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.actions ?? const [], isEmpty);
      // S9 on a form page simply leaves.
      await tester.tap(find.byKey(const Key('session_close_button')));
      await tester.pumpAndSettle();
      expect(find.byType(ReminiscenceArmBPage), findsNothing);
    });
  });

  testWidgets('large text: the S9 label still fits (leading width grows)',
      (tester) async {
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    addTearDown(() => PhaseBConfig.current = const PhaseBConfig());
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: ruleReplyHarness(const CheckInArmB(), NoLlmClient()),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.leadingWidth, greaterThan(SessionCloseButton.leadingWidth));
    final label = find.text(SessionCloseButton.label);
    expect(label, findsOneWidget);
    // The text box is as wide as the painted label: nothing faded/clipped.
    final box = tester.getSize(label);
    final painter = TextPainter(
      text: const TextSpan(
          text: SessionCloseButton.label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.3),
    )..layout();
    expect(box.width, greaterThanOrEqualTo(painter.width - 0.5));
  });

  testWidgets('v2 off: back arrow instead of S9, title unchanged',
      (tester) async {
    PhaseBConfig.current = const PhaseBConfig();
    await _open(tester, const CheckInArmB());
    expect(find.byKey(const Key('session_close_button')), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byKey(const Key('companion_title')), findsOneWidget);
  });
}

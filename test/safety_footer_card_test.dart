// 10/19 — 睇今日 crisis card: 「想搵人傾吓？」 centred, 「情緒通」 and 18111 on
// separate lines, one round call button, 「24×7 政府熱線」, no 「有真人」 and no
// separate 999 row; 「如果唔安全，睇更多支援熱線」 leads to the full list.
// Both arms see the same card.  No Firebase.
import 'package:app_demo/features/crisis/presentation/widgets/safety_footer_card.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {double width = 360, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: SafetyFooterCard(analyticsTag: 'test'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wording and layout', (tester) async {
    await _pump(tester);
    final title = tester.widget<Text>(find.text('想搵人傾吓？'));
    expect(title.textAlign, TextAlign.center);
    expect(find.text('「情緒通」'), findsOneWidget);
    expect(find.text('18111'), findsOneWidget);
    expect(find.text('24×7 政府熱線'), findsOneWidget);
    expect(find.textContaining('有真人'), findsNothing);
    expect(find.textContaining('999'), findsNothing);
    expect(find.text('如果唔安全，\n睇更多支援熱線'), findsOneWidget);
    // Headset and phone sit together in one button.
    final button = find.byKey(const Key('safety_footer_call_button'));
    expect(find.descendant(of: button, matching: find.byIcon(Icons.support_agent_rounded)),
        findsOneWidget);
    expect(find.descendant(of: button, matching: find.byIcon(Icons.phone_rounded)),
        findsOneWidget);
    // 「情緒通」 above 18111.
    expect(tester.getCenter(find.text('18111')).dy,
        greaterThan(tester.getCenter(find.text('「情緒通」')).dy));
    // 「24×7 政府熱線」 on its own centred line under the button row.
    final line = find.text('24×7 政府熱線');
    expect(tester.widget<Text>(line).textAlign, TextAlign.center);
    expect(tester.getTopLeft(line).dy,
        greaterThan(tester.getBottomLeft(button).dy));
  });

  testWidgets('24×7 政府熱線 stays on one line at 特大 (1.3), 320 wide',
      (tester) async {
    await _pump(tester, width: 320, scale: 1.3);
    final line = find.text('24×7 政府熱線');
    // One line: no taller than the style's line height (+ rounding).
    final style = tester.widget<Text>(line).style!;
    expect(tester.getSize(line).height,
        lessThanOrEqualTo(style.fontSize! * 1.3 * style.height! + 1));
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('fits $width wide at the App\'s largest text (1.3)', (tester) async {
      await _pump(tester, width: width, scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }
}

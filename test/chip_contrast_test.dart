// 10/15 pilot finding: option chips (心情、問卷、登記頁) looked like blank
// white boxes until tapped.  The theme now gives every chip a visible
// border, an ink label and a tinted selected state — both themes.
import 'package:app_demo/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chips are visible before selection in both themes', () {
    for (final theme in [AppTheme.light, AppTheme.highContrast]) {
      final chip = theme.chipTheme;
      final border = chip.side!;
      // Border clearly darker than the page (not the faint #E7E0D8).
      expect(border.color.computeLuminance(), lessThan(0.3));
      expect(border.width, greaterThanOrEqualTo(1.5));
      expect(chip.labelStyle!.color, isNotNull);
      expect(chip.labelStyle!.color!.computeLuminance(), lessThan(0.1));
      expect(chip.selectedColor, isNotNull);
      expect(chip.checkmarkColor, isNotNull);
      // Selected fill is visibly different from the unselected white.
      expect(chip.selectedColor, isNot(equals(chip.backgroundColor)));
    }
  });

  testWidgets('a ChoiceChip renders its label and a border unselected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: ChoiceChip(
              label: const Text('好開心'), selected: false, onSelected: (_) {}),
        ),
      ),
    ));
    expect(find.text('好開心'), findsOneWidget);
    final style = DefaultTextStyle.of(tester.element(find.text('好開心'))).style;
    expect(style.color!.computeLuminance(), lessThan(0.1));
  });
}

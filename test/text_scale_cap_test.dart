// 10/15 pilot: the phone's "larger text" × the App's 大字 setting overflowed
// the cards, so the combined factor is capped at 1.30.  10/19: five even
// levels 1.06–1.30 (Junyu), same cap; the old three keep their stored names.
import 'package:app_demo/app/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('five levels, 1.06 to 1.30 in even steps', () {
    expect(AppFontScale.values.map((s) => s.multiplier).toList(),
        [1.06, 1.12, 1.18, 1.24, 1.30]);
  });

  test('phone × App never exceeds 1.30', () {
    expect(combinedTextScale(1.0, AppFontScale.standard), closeTo(1.06, 1e-9));
    expect(combinedTextScale(1.0, AppFontScale.xLarge), closeTo(1.30, 1e-9));
    expect(combinedTextScale(1.5, AppFontScale.standard), closeTo(1.30, 1e-9));
    expect(combinedTextScale(2.0, AppFontScale.xLarge), closeTo(1.30, 1e-9));
    expect(combinedTextScale(1.1, AppFontScale.slightlyLarge),
        closeTo(1.232, 1e-9));
  });

  test('stored names of the old three still resolve', () {
    expect(AppFontScale.values.map((s) => s.name),
        containsAll(['standard', 'large', 'xLarge']));
  });
}

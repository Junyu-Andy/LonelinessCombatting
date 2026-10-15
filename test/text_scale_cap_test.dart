// 10/15 pilot: the phone's "larger text" × the App's 大字 setting overflowed
// the cards.  The combined factor is capped at AppFontScale.xLarge.
import 'package:app_demo/app/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combined scale never exceeds the App\'s own largest size', () {
    double combined(double system, AppFontScale app) =>
        (system * app.multiplier).clamp(0.8, AppFontScale.xLarge.multiplier);
    expect(combined(1.0, AppFontScale.standard), 1.0);
    expect(combined(1.0, AppFontScale.xLarge), AppFontScale.xLarge.multiplier);
    expect(combined(1.5, AppFontScale.standard), AppFontScale.xLarge.multiplier);
    expect(combined(2.0, AppFontScale.xLarge), AppFontScale.xLarge.multiplier);
    expect(combined(1.15, AppFontScale.standard), closeTo(1.15, 1e-9));
  });
}

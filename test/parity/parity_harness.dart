import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// P5.2 — shared harness for arm-parity golden tests.
///
/// Each parity test renders the same widget twice — once with the
/// participant assigned to Arm A (hybrid LLM), once with Arm B
/// (rule-based) — and either:
///   (a) for surfaces that protocol-mandates UI identity, asserts
///       both renders match the **same** golden image, or
///   (b) for the two sanctioned exceptions (M8 article detail and
///       M9 progress), compares each render against its own golden
///       so the reviewer can read the diff.
///
/// Generating goldens locally:
///     flutter test --update-goldens test/parity/
/// CI then runs without `--update-goldens` and fails on mismatch.

/// Wrap a widget so [Arm.of] / [Arm.isA] resolve to [arm] via the
/// production lookup path (AppSettingsScope → profile.arm).
Widget wrapWithArm({
  required ArmAssignment arm,
  required Widget child,
  Locale locale = const Locale('zh'),
}) {
  final settings = AppSettings(
    locale: locale,
    profile: _profileWithArm(arm),
  );
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: AppSettingsScope(
      settings: settings,
      child: Material(child: child),
    ),
  );
}

UserProfile _profileWithArm(ArmAssignment arm) {
  return UserProfile(
    uid: 'parity-fixture',
    displayName: 'Parity Fixture',
    arm: arm,
    consent: const ConsentFlags(
      functionalData: true,
      transcriptRetention: true,
    ),
  );
}

/// Sanctioned protocol differences. A parity test for these keys may
/// assert per-arm goldens. Listed in one place so a change to the
/// white list shows up in PR review.
const sanctionedParityExceptions = <String, String>{
  'm8_article_detail': 'Arm A renders the "問下呢篇" LLM-dialog entry.',
  'm9_progress': 'Arm A renders the weekly narrative summary card.',
};

/// Convenience asserter for the *strict* parity case: both arms must
/// match the same golden image.
Future<void> assertStrictParity({
  required WidgetTester tester,
  required String goldenKey,
  required Widget Function() build,
}) async {
  await tester.pumpWidget(
    wrapWithArm(arm: ArmAssignment.a, child: build()),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$goldenKey.png'),
  );

  await tester.pumpWidget(
    wrapWithArm(arm: ArmAssignment.b, child: build()),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$goldenKey.png'),
  );
}

/// Asserter for sanctioned-difference pages: each arm has its own
/// golden so reviewers can read the protected diff.
Future<void> assertSanctionedDifference({
  required WidgetTester tester,
  required String goldenKey,
  required Widget Function() build,
}) async {
  assert(
    sanctionedParityExceptions.containsKey(goldenKey),
    'goldenKey "$goldenKey" is not in sanctionedParityExceptions',
  );
  await tester.pumpWidget(
    wrapWithArm(arm: ArmAssignment.a, child: build()),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/${goldenKey}_arm_a.png'),
  );

  await tester.pumpWidget(
    wrapWithArm(arm: ArmAssignment.b, child: build()),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/${goldenKey}_arm_b.png'),
  );
}

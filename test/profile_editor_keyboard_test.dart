// 1020e 一.(11) — 「自己 → 個人資料 → 修改」 sheet with the keyboard open.
//
// Bug fix (no switch, both arms the same page): on a small phone at the
// App's largest font the sheet could not scroll, so with the keyboard up
// the lower fields and 儲存 were pushed off (a 194 px overflow at
// 360×640, font 1.30, keyboard 300).  Now the fields scroll and 儲存 stays
// under them, above the keyboard.
//
// Any overflow is a framework error and fails the test.  Synthetic data
// only; the profile write goes to a fake (no Firebase).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/personalization/presentation/pages/personalization_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(360, 640);
const _statusBar = 24.0;
const _keyboard = 300.0;

/// Records the saved profile instead of writing Firestore.
class _FakeAuth extends AuthService {
  _FakeAuth() : super(available: false);
  UserProfile? saved;

  @override
  Future<void> updateProfile(UserProfile profile,
      {bool includeSharedContextUse = false}) async {
    saved = profile;
  }
}

UserProfile _profile(ArmAssignment arm) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '陳太',
      arm: arm,
      cohort: 'pilot',
      ageGroup: '72',
      emergencyContactName: '阿明',
      emergencyContactPhone: '91234567',
    );

Future<(AppSettings, _FakeAuth)> _open(
    WidgetTester tester, ArmAssignment arm) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  final settings =
      AppSettings(locale: const Locale('zh'), profile: _profile(arm));
  final auth = _FakeAuth();
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: AuthServiceScope(
      authService: auth,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // Same wrapper as app.dart, at the largest App font (特大).
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const PersonalizationPage(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  return (settings, auth);
}

Finder get _save => find.byKey(const Key('profile_editor_save'));

/// 儲存 is on screen between the status bar and the keyboard, and tappable.
void _expectSaveReachable(WidgetTester tester) {
  final r = tester.getRect(_save);
  expect(r.top, greaterThanOrEqualTo(_statusBar));
  expect(r.bottom, lessThanOrEqualTo(_size.height - _keyboard + 0.5),
      reason: '儲存 above the keyboard');
  expect(_save.hitTestable(), findsOneWidget);
  expect(find.descendant(of: _save, matching: find.text('儲存')),
      findsOneWidget);
}

void main() {
  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    final armName = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

    testWidgets('$armName, 360×640, font 1.30, keyboard 300: every field '
        'can be focused without overflow, 儲存 stays reachable', (tester) async {
      await _open(tester, arm);
      final fields = find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(TextField));
      expect(fields, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        await tester.showKeyboard(fields.at(i));
        tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
        await tester.pumpAndSettle();
        // The focused field scrolls into view above the keyboard.
        final f = tester.getRect(fields.at(i));
        expect(f.bottom, lessThanOrEqualTo(_size.height - _keyboard + 0.5),
            reason: 'field $i above the keyboard');
        expect(f.top, greaterThanOrEqualTo(_statusBar), reason: 'field $i');
        _expectSaveReachable(tester);
      }
      // A framework overflow error would be reported here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('$armName: type the phone with the keyboard open, tap 儲存 → '
        'saved and the sheet closes', (tester) async {
      final (settings, auth) = await _open(tester, arm);
      final phone = find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(TextField)).at(3);
      await tester.showKeyboard(phone);
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
      await tester.pumpAndSettle();
      await tester.enterText(phone, '98765432');
      await tester.pumpAndSettle();
      _expectSaveReachable(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(auth.saved?.emergencyContactPhone, '98765432');
      expect(settings.profile?.emergencyContactPhone, '98765432');
      expect(find.byType(BottomSheet), findsNothing);
    });
  }

  testWidgets('keyboard closed: everything fits, nothing scrolls (same as '
      'before)', (tester) async {
    await _open(tester, ArmAssignment.a);
    final scroll = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('profile_editor_scroll')),
        matching: find.byType(Scrollable)).first);
    expect(scroll.position.maxScrollExtent, 0, reason: 'all four fields fit');
    final save = tester.getRect(_save);
    final lastField = tester.getRect(find
        .descendant(
            of: find.byType(BottomSheet), matching: find.byType(TextField))
        .at(3));
    expect(save.top - lastField.bottom, closeTo(18, 0.5),
        reason: '儲存 right under the last field, as before');
  });
}

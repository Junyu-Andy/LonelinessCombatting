// 10/19 — sign-up: when 建立帳號 fails, the page scrolls to the field in
// trouble and puts the cursor there; a server refusal about one field
// (e-mail already registered) is shown under that field.  Synthetic
// accounts, no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/auth/presentation/pages/login_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Refuses every sign-up with [code], as Firebase Auth would.
class _RefusingAuth extends AuthService {
  _RefusingAuth(this.code) : super(available: true);
  final String code;
  int calls = 0;

  @override
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String displayName,
    String? ageGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? preferredLanguage,
    ConsentFlags consent = const ConsentFlags(),
    int? baselineUclaScore,
  }) async {
    calls++;
    throw FirebaseAuthException(code: code);
  }
}

Future<void> _openSignUp(WidgetTester tester, AuthService auth) async {
  // A phone-sized screen: the sign-up form does not fit, so it scrolls.
  tester.view.physicalSize = const Size(400, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AnalyticsScope(
    analytics: AnalyticsService(firebaseReady: false),
    child: AuthServiceScope(
      authService: auth,
      child: AppSettingsScope(
        settings: AppSettings(),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginPage(authService: auth),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final toggle = find.widgetWithText(TextButton, '未有帳號？建立一個');
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

bool _hasFocus(WidgetTester tester, String label) {
  final editable = find.descendant(
      of: _field(label), matching: find.byType(EditableText));
  return tester.widget<EditableText>(editable).focusNode.hasFocus;
}

bool _onScreen(WidgetTester tester, String label) {
  final r = tester.getRect(_field(label));
  return r.top >= 0 && r.bottom <= 760;
}

Future<void> _fill(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.pumpAndSettle();
  await tester.enterText(_field(label), text);
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const Key('login_submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a missing name: scrolls back up to it and focuses it',
      (tester) async {
    final auth = _RefusingAuth('unused');
    await _openSignUp(tester, auth);
    await _fill(tester, '電郵', 'wongtai1950@gmail.com');
    await _fill(tester, '密碼', 'abc123');
    await _fill(tester, '再輸入一次密碼', 'abc123');
    // 你想我哋點樣叫你？ left empty.
    await _fill(tester, '聯絡人稱呼', '阿美');
    await _fill(tester, '聯絡電話', '91234567');

    await _tapSubmit(tester);

    expect(auth.calls, 0, reason: 'nothing sent');
    expect(find.text('請輸入稱呼。'), findsOneWidget);
    expect(_onScreen(tester, '你想我哋點樣叫你？'), isTrue);
    expect(_hasFocus(tester, '你想我哋點樣叫你？'), isTrue);
  });

  testWidgets('e-mail already registered: shown under the e-mail, which '
      'gets the cursor; editing it clears the message', (tester) async {
    final auth = _RefusingAuth('email-already-in-use');
    await _openSignUp(tester, auth);
    await _fill(tester, '電郵', 'wongtai1950@gmail.com');
    await _fill(tester, '密碼', 'abc123');
    await _fill(tester, '再輸入一次密碼', 'abc123');
    await _fill(tester, '你想我哋點樣叫你？', '黃太');
    await _fill(tester, '聯絡人稱呼', '阿美');
    await _fill(tester, '聯絡電話', '91234567');

    await _tapSubmit(tester);

    expect(auth.calls, 1);
    const msg = '呢個電郵已經註冊咗，請直接撳「登入」。';
    // Under the field and in the banner by the button.
    expect(
        find.descendant(of: _field('電郵'), matching: find.text(msg)),
        findsOneWidget);
    expect(_onScreen(tester, '電郵'), isTrue);
    expect(_hasFocus(tester, '電郵'), isTrue);

    await tester.enterText(_field('電郵'), 'wongtai1951@gmail.com');
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: _field('電郵'), matching: find.text(msg)),
        findsNothing);
  });
}

// dev-tasks-1014e §2.9 (N6) — the registration form no longer asks for a
// baseline UCLA total.  Phase B stratifies on the DJG-ES emotional score
// entered by the researcher (T19), and the study's UCLA-3 has no 20–80
// version, so the field only confused.  The sign-up form keeps the
// fields the elder (with the researcher) fills: e-mail, password, name,
// age, emergency contact name and phone — and nothing from any scale.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/auth/presentation/pages/login_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  testWidgets('sign-up form: no UCLA field, no scale wording; the elder '
      'fields are still there', (tester) async {
    // A tall surface so the whole sign-up form is built (it is a ListView).
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final auth = AuthService(available: false);
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

    final text = _allText(tester);
    expect(text, isNot(contains('UCLA')));
    expect(text, isNot(contains('分層')));
    expect(text, isNot(contains('研究人員填寫')));
    expect(text, isNot(contains('量表')));
    for (final label in ['電郵', '密碼', '再輸入一次密碼', '你想我哋點樣叫你？', '年齡', '聯絡人稱呼', '聯絡電話']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // 10/16: + 再輸入一次密碼 (S17).
    expect(find.byType(TextFormField), findsNWidgets(7));
  });

  // 10/16 (S17): the elder types the password twice; the address wraps so
  // it can be read back in full; the eye button shows both password boxes.
  testWidgets('sign-up: mismatched passwords are refused; the e-mail wraps '
      'and drops spaces; the eye shows both passwords', (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final auth = AuthService(available: false);
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
    expect(find.text('建立帳號'), findsOneWidget);

    // The e-mail box wraps (no sideways scrolling) and never keeps a space.
    final emailField = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const Key('login_email')),
        matching: find.byType(EditableText)));
    expect(emailField.maxLines, isNull);
    await tester.enterText(find.byKey(const Key('login_email')),
        'wong tai 1950 @gmail.com\n');
    expect(find.text('wongtai1950@gmail.com'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('login_password')), 'abc123');
    await tester.enterText(
        find.byKey(const Key('login_password_again')), 'abc124');
    await tester.enterText(
        find.byKey(const Key('login_email')), 'wongtai1950@gmail.com');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('兩次密碼唔一樣。'), findsOneWidget);
    // Nothing was submitted: no sign-up error from the (offline) service.

    // Both password boxes are hidden; the eye shows both.
    bool obscured(String key) => tester
        .widget<EditableText>(find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(EditableText)))
        .obscureText;
    expect(obscured('login_password'), isTrue);
    expect(obscured('login_password_again'), isTrue);
    await tester.tap(find.byKey(const Key('login_show_password')));
    await tester.pumpAndSettle();
    expect(obscured('login_password'), isFalse);
    expect(obscured('login_password_again'), isFalse);

    // Matching passwords pass the form (the offline service then refuses,
    // which is shown as a message, not a crash).
    await tester.enterText(
        find.byKey(const Key('login_password_again')), 'abc123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('兩次密碼唔一樣。'), findsNothing);
  });
}

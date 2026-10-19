// 10/19 — 自己 tab: no intro line about 語言／界線／demo, no 「你嘅資料」 card
// and no 登出 on the main page; the details, editing and 登出 sit behind
// the 個人資料 tile.  Synthetic account, no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('自己: no profile card, no demo line, no sign-out button',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings(locale: const Locale('zh'))
      ..profile = const UserProfile(
        uid: 'u1',
        email: 'u1@example.invalid',
        displayName: '黃太',
      );
    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SettingsPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('你嘅資料'), findsNothing);
    expect(find.textContaining('demo'), findsNothing);
    expect(find.text('登出'), findsNothing);
    expect(find.text('u1@example.invalid'), findsNothing);
    // The way in is still there.
    expect(find.text('個人資料'), findsWidgets);
  });
}

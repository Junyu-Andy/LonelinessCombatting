// C20 / decision 0020: the privacy page must not repeat claims the app
// does not meet (device-only storage, no cloud sync, a "clear all data"
// setting that does not exist).
import 'package:app_demo/features/settings/presentation/pages/privacy_policy_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const PrivacyPolicyPage(),
    );

// Tall window so the lazy ListView builds every section.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

void main() {
  testWidgets('Chinese page: accurate claims only', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_page(const Locale('zh')));
    await tester.pumpAndSettle();
    final text = _allText(tester);
    for (final banned in ['冇雲端同步', '只會儲存喺你部電話', '清除所有資料', '冇賬戶登入']) {
      expect(text.contains(banned), isFalse, reason: banned);
    }
    expect(text, contains('雲端伺服器'));
    expect(text, contains('詳情請參閱你簽署嘅研究同意書'));
    expect(find.text('zhaojyxs@connect.hku.hk'), findsOneWidget);
  });

  testWidgets('English page mirrors it', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_page(const Locale('en')));
    await tester.pumpAndSettle();
    final text = _allText(tester);
    expect(text.contains('only on your device'), isFalse);
    expect(text.contains('Clear all data'), isFalse);
    expect(text, contains('cloud servers'));
  });
}

// 1020o 二 — 常見問題: answers 2–6 rewritten, question 5 renamed.  Both
// arms see the same six entries, word for word, and all six open without
// overflow on a small phone at the largest App text (1.30).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/faq_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _faq = [
  (
    '呢個 app 係咪用嚟代替醫生？',
    '唔係。佢可以幫你整理感受同諗下下一步，但唔可以取代醫生、治療或者緊急支援。'
        '如果有即時需要，請聯絡屋企人或者撥 999。',
  ),
  (
    '我嘅資料會唔會畀第二個人睇到？',
    '你喺 App 入面講嘅嘢、填嘅問卷同使用紀錄，會儲存喺研究用嘅伺服器。'
        '研究團隊會睇同分析呢啲資料，只用嚟做研究，唔會交畀研究團隊以外嘅人做其他用途。'
        '詳情請睇你簽嘅同意書，有問題可以問研究人員。',
  ),
  (
    '點樣改字體大細？',
    '你可以去「自己」入面嘅「顯示設定」揀字體大小，由標準到特大一共五級，'
        '揀咗之後成個 App 嘅字即刻跟住變。如果仲係睇唔清，可以入「我的設定」打開「高對比模式」。',
  ),
  ('我冇填 check-in 會唔會有事？', '唔會有事。不過建議你每日都入嚟傾下，每個禮拜最少用五次。'),
  ('點解夜晚冇通知？可唔可以改時間？', '晚上十點到朝早八點，App 唔會彈出通知。想改呢段時間，可以入「我的設定」嘅「安靜時段」。'),
  (
    '我覺得好唔開心，應該點做？',
    '先慢慢深呼吸幾下。首頁下面有「想搵人傾吓？」，撳一下就會打去情緒通 18111。'
        '如果覺得唔安全，可以撳「睇更多支援熱線」，或者直接打 999。',
  ),
];

Future<void> _pumpFaq(
  WidgetTester tester, {
  required ArmAssignment arm,
  bool highContrast = false,
}) async {
  tester.view.physicalSize = const Size(360, 800) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppSettingsScope(
      settings: AppSettings(
        locale: const Locale('zh'),
        profile: UserProfile(
          uid: 'faq-fixture',
          email: 'faq@example.test',
          displayName: 'FAQ Fixture',
          arm: arm,
        ),
      ),
      child: MaterialApp(
        theme: highContrast ? AppTheme.highContrast : AppTheme.light,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppFontScale.xLarge.multiplier),
          ),
          child: child!,
        ),
        home: const FaqPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens every entry, top to bottom, scrolling each question into view,
/// and returns each answer as shown right after opening it (the list is
/// lazy: entries scrolled far off are no longer built).
Future<Map<String, String>> _openAll(WidgetTester tester) async {
  final shown = <String, String>{};
  for (final (question, _) in _faq) {
    final q = find.text(question);
    await tester.scrollUntilVisible(
      q,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(q);
    await tester.pumpAndSettle();
    await tester.tap(q);
    await tester.pumpAndSettle();
    shown[question] = _answerText(tester, question);
  }
  return shown;
}

String _answerText(WidgetTester tester, String question) {
  final tile = find.ancestor(
    of: find.text(question),
    matching: find.byType(ExpansionTile),
  );
  final texts = find.descendant(of: tile, matching: find.byType(Text));
  return texts
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((t) => t != question)
      .join();
}

void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'arm ${arm.name}${highContrast ? ', high contrast' : ''}: six '
        'entries word for word, all open at 特大 on 360 × 800',
        (tester) async {
          await _pumpFaq(tester, arm: arm, highContrast: highContrast);
          final shown = await _openAll(tester);
          expect(tester.takeException(), isNull);
          for (final (question, answer) in _faq) {
            expect(shown[question], answer, reason: question);
          }
        },
      );
    }
  }

  testWidgets('old wording is gone (phone-only data, 跟進 switches, 溫馨提示)', (
    tester,
  ) async {
    await _pumpFaq(tester, arm: ArmAssignment.a);
    final shown = await _openAll(tester);
    for (final old in [
      '只會留喺你部電話度',
      '點樣關掉提醒？',
      '設定 > 通知',
      '溫馨提示',
      '上面會即時見到預覽',
      '就算一整個星期冇填',
    ]) {
      expect(shown.values.any((a) => a.contains(old)), isFalse, reason: old);
      expect(shown.keys.any((q) => q.contains(old)), isFalse, reason: old);
    }
  });

  testWidgets('answer 4 still follows app_config/usage_copy', (tester) async {
    UsageCopy.current = UsageCopy.fromMap({
      'faq_skip_checkin_answer_zh': '研究團隊定稿',
    });
    await _pumpFaq(tester, arm: ArmAssignment.b);
    final shown = await _openAll(tester);
    expect(shown['我冇填 check-in 會唔會有事？'], '研究團隊定稿');
  });
}

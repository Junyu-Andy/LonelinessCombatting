// 1020o 二 補充 (decisions-log 10/20 item 93) — 常見問題, whole page
// replaced: the line on top and all six questions and answers, each
// question with its icon.  Both arms see the same page, word for word, and
// all six open without overflow on a small phone at the largest App text
// (1.30), normal and high contrast.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/faq_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Written out again here (not read from FaqCopy) so a change to the page
// text fails this test.
const _intro = '平時用 App 有咩唔清楚，可以先睇下呢度。搵唔到答案，隨時問研究人員都得。';

const _faq = [
  (
    Icons.medical_services_outlined,
    '呢個 App 可以代替睇醫生嗎？',
    '唔可以。佢可以陪你傾偈、幫你理清下心情，但始終唔係醫生。身體或者情緒有需要，'
        '記得搵醫生或者身邊信得過嘅人；有緊急情況，即刻打 999。',
  ),
  (
    Icons.lock_outline,
    '我講嘅嘢，邊個會睇到？',
    '你喺 App 入面講嘅嘢、填嘅問卷同使用紀錄，會儲存喺研究用嘅伺服器。'
        '只有研究團隊會睇同分析，用嚟做研究，唔會交畀研究團隊以外嘅人做其他用途。'
        '想知多啲，可以睇返你簽嘅同意書，或者問研究人員。',
  ),
  (
    Icons.text_fields,
    '啲字太細，睇得好辛苦，點算？',
    '入「自己」嘅「顯示設定」，可以將字調大，由標準到特大一共五級，一揀就即刻變。'
        '仲係睇唔清嘅話，可以喺「我的設定」打開「高對比模式」，啲字會再清楚啲。',
  ),
  (
    Icons.event_available_outlined,
    '有一日冇 check-in，會唔會有問題？',
    '唔會有問題，唔使擔心。不過都建議你每日入嚟傾下，每個禮拜最少用五次。',
  ),
  (
    Icons.bedtime_outlined,
    '點解夜晚收唔到通知？',
    '為咗唔阻住你休息，晚上十點到朝早八點，App 唔會彈通知出嚟。'
        '想早啲或者遲啲開始，可以入「我的設定」嘅「安靜時段」自己改。',
  ),
  (
    Icons.favorite_border,
    '覺得好唔開心，可以點做？',
    '先慢慢深呼吸幾下，唔使一個人頂住。首頁下面有「想搵人傾吓？」，'
        '撳一下就會打去情緒通 18111，有人聽你講。'
        '如果覺得唔安全，撳「睇更多支援熱線」，或者即刻打 999。',
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
  for (final (_, question, _) in _faq) {
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

/// The icon in front of [question]'s text: the one in the nearest row
/// holding the question.
Icon _iconOf(WidgetTester tester, String question) {
  final row = find
      .ancestor(of: find.text(question), matching: find.byType(Row))
      .first;
  return tester.widget<Icon>(
    find.descendant(of: row, matching: find.byType(Icon)),
  );
}

void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'arm ${arm.name}${highContrast ? ', high contrast' : ''}: line on '
        'top, six entries word for word with their icons, all open at 特大 '
        'on 360 × 800',
        (tester) async {
          await _pumpFaq(tester, arm: arm, highContrast: highContrast);
          expect(
            tester.widget<Text>(find.byKey(const Key('faq_intro'))).data,
            _intro,
          );
          final context = tester.element(find.byType(FaqPage));
          final theme = Theme.of(context);
          final titleSize =
              theme.textTheme.titleMedium!.fontSize! *
              AppFontScale.xLarge.multiplier;
          for (final (icon, question, _) in _faq) {
            final q = find.text(question);
            await tester.scrollUntilVisible(
              q,
              120,
              scrollable: find.byType(Scrollable).first,
            );
            final shownIcon = _iconOf(tester, question);
            expect(shownIcon.icon, icon, reason: question);
            expect(
              shownIcon.color,
              theme.colorScheme.primary,
              reason: question,
            );
            expect(shownIcon.size, closeTo(titleSize, 0.01), reason: question);
          }
          await tester.scrollUntilVisible(
            find.byKey(const Key('faq_intro')),
            -400,
            scrollable: find.byType(Scrollable).first,
          );
          final shown = await _openAll(tester);
          expect(tester.takeException(), isNull);
          expect(shown.length, 6);
          for (final (_, question, answer) in _faq) {
            expect(shown[question], answer, reason: question);
          }
        },
      );
    }
  }

  testWidgets('old wording is gone (設定 contact line, old questions)', (
    tester,
  ) async {
    await _pumpFaq(tester, arm: ArmAssignment.a);
    for (final old in [
      '如果呢度搵唔到答案',
      '呢個 app 係咪用嚟代替醫生？',
      '我嘅資料會唔會畀第二個人睇到？',
      '點樣改字體大細？',
      '我冇填 check-in 會唔會有事？',
      '點解夜晚冇通知？可唔可以改時間？',
      '我覺得好唔開心，應該點做？',
    ]) {
      expect(find.textContaining(old), findsNothing, reason: old);
    }
    final shown = await _openAll(tester);
    for (final old in ['只會留喺你部電話度', '溫馨提示', '上面會即時見到預覽']) {
      expect(shown.values.any((a) => a.contains(old)), isFalse, reason: old);
    }
  });

  testWidgets('answer 4 still follows app_config/usage_copy', (tester) async {
    UsageCopy.current = UsageCopy.fromMap({
      'faq_skip_checkin_answer_zh': '研究團隊定稿',
    });
    await _pumpFaq(tester, arm: ArmAssignment.b);
    final shown = await _openAll(tester);
    expect(shown['有一日冇 check-in，會唔會有問題？'], '研究團隊定稿');
  });
}

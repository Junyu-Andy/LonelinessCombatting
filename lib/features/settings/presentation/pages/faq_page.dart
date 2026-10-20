/// 常見問題 (自己 → 常見問題).  Both arms identical.
///
/// 1020o 二 補充 (decisions-log 10/20 item 93, Junyu): the whole page
/// replaced — the line on top, all six questions and answers — and a small
/// Material icon in the theme colour before each question, as big as the
/// question text.  No switch; the old text is gone.  The numbers are only
/// 18111 and 999, as before.
///
/// Answer 4 talks about how often to come back, so `app_config/usage_copy`
/// may still replace it (T20, same in both arms).
library;

import 'package:flutter/material.dart';

import '../../../../core/config/usage_copy.dart';

/// One entry: its icon, question and answer.
typedef FaqEntry = (IconData, String, String);

/// The page text (1020o 二 補充).  The 『』 of the brief are shown as 「」:
/// they stand on their own here, not inside another quotation.
class FaqCopy {
  FaqCopy._();

  static const intro = '平時用 App 有咩唔清楚，可以先睇下呢度。搵唔到答案，隨時問研究人員都得。';

  static const List<FaqEntry> entries = [
    (
      Icons.medical_services_outlined,
      '呢個 App 可以代替睇醫生嗎？',
      '唔可以。佢可以陪你傾偈、幫你理清下心情，但始終唔係醫生。'
          '身體或者情緒有需要，記得搵醫生或者身邊信得過嘅人；有緊急情況，即刻打 999。',
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
      '先慢慢深呼吸幾下，唔使一個人頂住。'
          '首頁下面有「想搵人傾吓？」，撳一下就會打去情緒通 18111，有人聽你講。'
          '如果覺得唔安全，撳「睇更多支援熱線」，或者即刻打 999。',
    ),
  ];

  // Tester view in English only (the App is Cantonese-only); same meaning.
  static const introEn =
      'If anything about the App is unclear, look here '
      'first. If you can\'t find the answer, ask the research staff any time.';

  static const List<FaqEntry> entriesEn = [
    (
      Icons.medical_services_outlined,
      'Can this App replace seeing a doctor?',
      'No. It can chat with you and help you sort out your feelings, but it '
          'is not a doctor. If your body or mood needs help, see a doctor or '
          'someone you trust; in an emergency, call 999 right away.',
    ),
    (
      Icons.lock_outline,
      'Who can see what I say?',
      'What you say in the App, the questionnaires you fill in and your '
          'usage records are stored on the study\'s server. Only the research '
          'team reads and analyses them, for the study, and does not give '
          'them to anyone outside the team for any other use. To know more, '
          'see the consent form you signed, or ask the research staff.',
    ),
    (
      Icons.text_fields,
      'The text is too small and hard to read. What can I do?',
      'Go to "Display" in Self to make the text bigger, from Standard to '
          'Max in five steps; it changes as soon as you pick. If it is still '
          'hard to read, turn on High-Contrast Mode in "My settings" to make '
          'the text clearer.',
    ),
    (
      Icons.event_available_outlined,
      'Is it a problem if I miss a check-in for a day?',
      'No problem, don\'t worry. But we suggest you come in for a chat every '
          'day, and use the App at least five times a week.',
    ),
    (
      Icons.bedtime_outlined,
      'Why don\'t I get notifications at night?',
      'So as not to disturb your rest, the App shows no notifications from '
          '10 pm to 8 am. To start earlier or later, change it yourself under '
          '"Quiet hours" in "My settings".',
    ),
    (
      Icons.favorite_border,
      'I feel very unhappy. What can I do?',
      'Take a few slow deep breaths first; you don\'t have to carry it alone. '
          'At the bottom of the Home screen, tap "Want to talk to someone?" to '
          'call the 18111 mental health support hotline, where someone will '
          'listen. If you feel unsafe, tap "see more support hotlines", or '
          'call 999 right away.',
    ),
  ];

  /// Position of the check-in answer (overridable) in both lists.
  static const skipCheckinIndex = 3;
}

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final faq = isEn ? FaqCopy.entriesEn : FaqCopy.entries;
    // 10/16: no 「我可唔可以用英文？」 entry — English is off
    // (AppSettings.englishEnabled) and the FAQ must not promise it.
    final items = [
      for (var i = 0; i < faq.length; i++)
        i == FaqCopy.skipCheckinIndex
            ? (
                faq[i].$1,
                faq[i].$2,
                UsageCopy.current.text(
                  UsageCopy.faqSkipCheckinAnswer,
                  isEn: isEn,
                  fallback: faq[i].$3,
                ),
              )
            : faq[i],
    ];

    // The icon is as big as the question text at the current text size,
    // and sits in the middle of the question's first line.
    final titleStyle = theme.textTheme.titleMedium;
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(titleStyle?.fontSize ?? 16);
    final lineHeight = fontSize * (titleStyle?.height ?? 1.2);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'FAQ' : '常見問題')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            isEn ? FaqCopy.introEn : FaqCopy.intro,
            key: const Key('faq_intro'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final (icon, question, answer) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    iconColor: theme.colorScheme.primary,
                    collapsedIconColor: theme.colorScheme.primary,
                    title: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            top: (lineHeight - fontSize) / 2,
                            right: 10,
                          ),
                          child: Icon(
                            icon,
                            size: fontSize,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Expanded(child: Text(question, style: titleStyle)),
                      ],
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(answer, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

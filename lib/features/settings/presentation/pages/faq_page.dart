import 'package:flutter/material.dart';

import '../../../../core/config/usage_copy.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  /// Position of "Does it matter if I skip a check-in?" in both lists.
  static const _skipCheckinIndex = 3;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final faq = isEn
        ? const [
            (
              'Is this app a replacement for a doctor?',
              'No. It can help you organise feelings and think through next steps, '
                  'but it cannot replace a doctor, therapist, or emergency support. '
                  'If you have an immediate need, contact family or call 999.',
            ),
            (
              'Will my data be seen by others?',
              'What you say in the App, the questionnaires you fill in and '
                  'your usage records are stored on the study\'s server. '
                  'The research team reads and analyses them for the study only, '
                  'and does not give them to anyone outside the team for any other use. '
                  'See the consent form you signed for details, '
                  'or ask the research staff.',
            ),
            (
              'How do I change the text size?',
              'Go to "Display" in Self and pick a text size, '
                  'from Standard to Max (five steps); the whole App changes '
                  'as soon as you pick. If it is still hard to read, '
                  'turn on High-Contrast Mode in "My settings".',
            ),
            (
              'Does it matter if I skip a check-in?',
              'Nothing happens. But we suggest you come in for a chat every day, '
                  'and use the App at least five times a week.',
            ),
            (
              'Why are there no notifications at night? Can I change the time?',
              'From 10 pm to 8 am the App does not show notifications. '
                  'To change this time, go to "Quiet hours" in "My settings".',
            ),
            (
              'I feel very unhappy — what should I do?',
              'Take a few slow deep breaths first. At the bottom of the Home '
                  'screen, tap "Want to talk to someone?" to call the 18111 '
                  'mental health support hotline. If you feel unsafe, tap '
                  '"see more support hotlines", or call 999 directly.',
            ),
          ]
        : const [
            (
              '呢個 app 係咪用嚟代替醫生？',
              '唔係。佢可以幫你整理感受同諗下下一步，'
                  '但唔可以取代醫生、治療或者緊急支援。'
                  '如果有即時需要，請聯絡屋企人或者撥 999。',
            ),
            (
              '我嘅資料會唔會畀第二個人睇到？',
              '你喺 App 入面講嘅嘢、填嘅問卷同使用紀錄，會儲存喺研究用嘅伺服器。'
                  '研究團隊會睇同分析呢啲資料，只用嚟做研究，'
                  '唔會交畀研究團隊以外嘅人做其他用途。'
                  '詳情請睇你簽嘅同意書，有問題可以問研究人員。',
            ),
            (
              '點樣改字體大細？',
              '你可以去「自己」入面嘅「顯示設定」揀字體大小，'
                  '由標準到特大一共五級，揀咗之後成個 App 嘅字即刻跟住變。'
                  '如果仲係睇唔清，可以入「我的設定」打開「高對比模式」。',
            ),
            (
              '我冇填 check-in 會唔會有事？',
              '唔會有事。不過建議你每日都入嚟傾下，每個禮拜最少用五次。',
            ),
            (
              '點解夜晚冇通知？可唔可以改時間？',
              '晚上十點到朝早八點，App 唔會彈出通知。'
                  '想改呢段時間，可以入「我的設定」嘅「安靜時段」。',
            ),
            (
              '我覺得好唔開心，應該點做？',
              '先慢慢深呼吸幾下。首頁下面有「想搵人傾吓？」，'
                  '撳一下就會打去情緒通 18111。'
                  '如果覺得唔安全，可以撳「睇更多支援熱線」，或者直接打 999。',
            ),
          ];
    // 10/16: the 「我可唔可以用英文？」 entry was removed — English is off
    // (AppSettings.englishEnabled) and the FAQ must not promise it.
    // T20: the "skip a check-in" answer talks about how often to come
    // back, so `app_config/usage_copy` may replace it (same in both arms).
    // 1020o 二: answers 2–6 rewritten (Q2 matches the consent form; Q3 uses
    // the real names on 自己 — five levels, no preview; Q5 is now about
    // the night-time quiet hours set in 我的設定; Q6 points to the home
    // safety card).  Q1 unchanged.
    final items = [
      for (var i = 0; i < faq.length; i++)
        i == _skipCheckinIndex
            ? (
                faq[i].$1,
                UsageCopy.current.text(UsageCopy.faqSkipCheckinAnswer,
                    isEn: isEn, fallback: faq[i].$2),
              )
            : faq[i],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'FAQ' : '常見問題'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            isEn
                ? 'Can\'t find what you need? Contact us via Settings.'
                : '如果呢度搵唔到答案，可以喺「設定」搵聯絡方法畀我哋。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                child: Theme(
                  data: theme.copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    iconColor: theme.colorScheme.primary,
                    collapsedIconColor: theme.colorScheme.primary,
                    title: Text(
                      item.$1,
                      style: theme.textTheme.titleMedium,
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.$2,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

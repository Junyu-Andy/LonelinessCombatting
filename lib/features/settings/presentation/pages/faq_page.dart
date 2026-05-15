import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final items = isEn
        ? const [
            (
              'Is this app a replacement for a doctor?',
              'No. It can help you organise feelings and think through next steps, '
                  'but it cannot replace a doctor, therapist, or emergency support. '
                  'If you have an immediate need, contact family or call 999.',
            ),
            (
              'Will my data be seen by others?',
              'All your check-ins, reflections, and reminders stay on your device. '
                  'We do not share your records with anyone, '
                  'unless you choose to export them to someone you trust.',
            ),
            (
              'How do I change the text size?',
              'Go to Settings → Display and choose Standard / Large / Extra Large. '
                  'You will see a live preview above the options. '
                  'If it is still hard to read, try turning on High-Contrast Mode.',
            ),
            (
              'Does it matter if I skip a check-in?',
              'Not at all. There are no scores or grades here. '
                  'Even if you skip a whole week, you are just as welcome when you come back.',
            ),
            (
              'How do I turn off reminders?',
              'Go to the Follow-up page and toggle off any reminder you no longer want. '
                  'You can also set a Quiet Hours window under Settings → Notifications.',
            ),
            (
              'I feel very unhappy — what should I do?',
              'Take a few slow deep breaths first, then check the support hotlines on the Home screen. '
                  'If you feel you cannot cope, please call 999 right away.',
            ),
            (
              'Can I use the app in English?',
              'Yes. Go to Settings → Language and select English. '
                  'You can switch between Chinese and English at any time.',
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
              '你所有嘅 check-in、反思同提醒都只會留喺你部電話度。'
                  '我哋唔會將你嘅紀錄同其他人分享，'
                  '除非你自己主動選擇匯出畀信任嘅人。',
            ),
            (
              '點樣改字體大細？',
              '你可以去「設定 > 顯示設定」揀標準／大／特大，'
                  '上面會即時見到預覽。'
                  '如果仲係睇唔清，可以打開「高對比模式」。',
            ),
            (
              '我冇填 check-in 會唔會有事？',
              '完全唔會有事。呢度冇分數、冇評分。'
                  '就算一整個星期冇填，你返嚟嗰陣都係一樣受歡迎。',
            ),
            (
              '點樣關掉提醒？',
              '可以入「跟進」頁，'
                  '將唔想收到嘅提醒旁邊個開關撥返灰色，就唔會再出聲。'
                  '亦可以喺「設定 > 通知」打開「安靜時段」。',
            ),
            (
              '我覺得好唔開心，應該點做？',
              '先深呼吸幾下，然後睇下首頁上面「溫馨提示」嘅支援電話，'
                  '或者即刻打畀你信任嘅人。'
                  '如果覺得撐唔住，請直接撥 999。',
            ),
            (
              '我可唔可以用英文？',
              '可以。入「設定 > 語言」就可以揀 English。'
                  '系統支援中英文隨時切換。',
            ),
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

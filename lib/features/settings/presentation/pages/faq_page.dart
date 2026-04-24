import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = const [
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
        title: const Text('常見問題'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '如果呢度搵唔到答案，可以喺「設定」搵聯絡方法畀我哋。',
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

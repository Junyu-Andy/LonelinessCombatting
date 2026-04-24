import 'package:flutter/material.dart';

import '../../../chat/data/chat_models.dart';
import '../../../chat/presentation/pages/chat_page.dart';
import '../../../chat/presentation/widgets/persona_avatar.dart';

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
          const SizedBox(height: 10),
          const _AskMoreCard(),
        ],
      ),
    );
  }
}

/// Bottom-of-FAQ CTA. Tapping it opens a ChatPage with the `faq` persona
/// — which routes through `DeepseekChatBackend` → scripted fallback when
/// no API key is configured.
class _AskMoreCard extends StatelessWidget {
  const _AskMoreCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = personaVisual(ChatPersona.faq);
    return Material(
      color: spec.bubbleColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 320),
              reverseTransitionDuration: const Duration(milliseconds: 220),
              pageBuilder: (_, animation, __) => FadeTransition(
                opacity: animation,
                child: const ChatPage(persona: ChatPersona.faq),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PersonaAvatar(persona: ChatPersona.faq, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '我仲有問題',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: spec.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: spec.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '搵唔到答案？撳入去問「小助」，佢會即時回覆。\n由 DeepSeek 提供支援。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.brown.shade800,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 28, color: spec.accent),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('私隱政策'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '我哋相信私隱就係尊重。下面用簡單嘅方式解釋你嘅資料點樣處理。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _PolicySection(
            icon: Icons.lock_outline,
            title: '你嘅資料擺喺邊？',
            body: '你每日嘅 check-in、反思記錄、提醒同聯絡人名單，'
                '只會儲存喺你部電話本身。'
                '我哋唔會將呢啲內容上傳到伺服器。',
          ),
          _PolicySection(
            icon: Icons.visibility_off_outlined,
            title: '我哋會睇到你填乜嘢嗎？',
            body: '唔會。呢個 demo 冇賬戶登入、冇雲端同步，'
                '亦都冇任何人可以遠端讀取你填嘅嘢。',
          ),
          _PolicySection(
            icon: Icons.share_outlined,
            title: '會唔會同第三方分享？',
            body: '唔會同任何第三方（例如廣告商、保險公司）分享你嘅使用紀錄。'
                '只有當你自己主動選擇分享某啲內容畀信任嘅人嗰陣，'
                '資料先會離開你部電話。',
          ),
          _PolicySection(
            icon: Icons.delete_outline,
            title: '我點樣刪除所有紀錄？',
            body: '入「設定 > 清除所有資料」就可以一次過刪除晒。'
                '動作完成之後冇辦法復原，請保留需要嘅內容先刪除。',
          ),
          _PolicySection(
            icon: Icons.warning_amber_outlined,
            title: '緊急情況下嘅例外',
            body: '如果你用緊「即時支援」頁嘅功能致電熱線或 999，'
                '電話號碼資訊由電訊商處理，不受呢個 app 控制。',
          ),
          _PolicySection(
            icon: Icons.update_outlined,
            title: '呢份政策幾時會更新？',
            body: '任何更改會喺 app 內通知。'
                '我哋會盡量用簡單嘅語言話畀你知點解要改。',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.mail_outline,
                  size: 26,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '有私隱相關疑問？可以電郵 privacy@example.com，'
                    '我哋會喺 7 日內回覆。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '最後更新：2026 年 4 月',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PolicySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 28, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

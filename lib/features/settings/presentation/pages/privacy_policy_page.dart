import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final sections = isEn
        ? const [
            _SectionData(
              icon: Icons.lock_outline,
              title: 'Where is your data stored?',
              body: 'Your daily check-ins, reflections, reminders, and contact list '
                  'are stored only on your device. '
                  'We do not upload this content to any server.',
            ),
            _SectionData(
              icon: Icons.visibility_off_outlined,
              title: 'Can we see what you fill in?',
              body: 'No. This demo has no account login and no cloud sync. '
                  'No one can remotely access what you enter.',
            ),
            _SectionData(
              icon: Icons.share_outlined,
              title: 'Is anything shared with third parties?',
              body: 'We do not share your usage records with any third party '
                  '(e.g. advertisers, insurers). '
                  'Data only leaves your device when you actively choose to share it with someone you trust.',
            ),
            _SectionData(
              icon: Icons.delete_outline,
              title: 'How do I delete all records?',
              body: 'Go to Settings → Clear all data to delete everything at once. '
                  'This action cannot be undone — please back up anything you need first.',
            ),
            _SectionData(
              icon: Icons.warning_amber_outlined,
              title: 'Exceptions in emergencies',
              body: 'If you use the Emergency Support page to call a hotline or 999, '
                  'phone number information is handled by your carrier and is outside this app\'s control.',
            ),
            _SectionData(
              icon: Icons.update_outlined,
              title: 'When will this policy be updated?',
              body: 'Any changes will be notified within the app. '
                  'We will explain the reason for any change in plain language.',
            ),
          ]
        : const [
            _SectionData(
              icon: Icons.lock_outline,
              title: '你嘅資料擺喺邊？',
              body: '你每日嘅 check-in、反思記錄、提醒同聯絡人名單，'
                  '只會儲存喺你部電話本身。'
                  '我哋唔會將呢啲內容上傳到伺服器。',
            ),
            _SectionData(
              icon: Icons.visibility_off_outlined,
              title: '我哋會睇到你填乜嘢嗎？',
              body: '唔會。呢個 demo 冇賬戶登入、冇雲端同步，'
                  '亦都冇任何人可以遠端讀取你填嘅嘢。',
            ),
            _SectionData(
              icon: Icons.share_outlined,
              title: '會唔會同第三方分享？',
              body: '唔會同任何第三方（例如廣告商、保險公司）分享你嘅使用紀錄。'
                  '只有當你自己主動選擇分享某啲內容畀信任嘅人嗰陣，'
                  '資料先會離開你部電話。',
            ),
            _SectionData(
              icon: Icons.delete_outline,
              title: '我點樣刪除所有紀錄？',
              body: '入「設定 > 清除所有資料」就可以一次過刪除晒。'
                  '動作完成之後冇辦法復原，請保留需要嘅內容先刪除。',
            ),
            _SectionData(
              icon: Icons.warning_amber_outlined,
              title: '緊急情況下嘅例外',
              body: '如果你用緊「即時支援」頁嘅功能致電熱線或 999，'
                  '電話號碼資訊由電訊商處理，不受呢個 app 控制。',
            ),
            _SectionData(
              icon: Icons.update_outlined,
              title: '呢份政策幾時會更新？',
              body: '任何更改會喺 app 內通知。'
                  '我哋會盡量用簡單嘅語言話畀你知點解要改。',
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Privacy Policy' : '私隱政策'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            isEn
                ? 'We believe privacy is respect. Here is how your data is handled, in plain terms.'
                : '我哋相信私隱就係尊重。下面用簡單嘅方式解釋你嘅資料點樣處理。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ...sections.map((s) => _PolicySection(data: s)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn
                            ? 'Privacy questions? Email us and we\'ll reply within 7 days.'
                            : '有私隱相關疑問？可以電郵聯絡我哋，7 日內會回覆。',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        'zhaojyxs@connect.hku.hk',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEn ? 'HKU — Mr Zhao' : '香港大學　趙先生',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isEn ? 'Last updated: April 2026' : '最後更新：2026 年 4 月',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionData {
  final IconData icon;
  final String title;
  final String body;

  const _SectionData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _PolicySection extends StatelessWidget {
  final _SectionData data;

  const _PolicySection({required this.data});

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
                  Icon(data.icon, size: 28, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.body,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

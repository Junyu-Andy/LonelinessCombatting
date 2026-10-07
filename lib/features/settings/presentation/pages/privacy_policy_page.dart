import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    // C20 / decision 0020 — kept short and general; the details (which
    // companies, where servers are, what cannot be deleted) live in the
    // signed consent form.  Wording awaits the PI's sign-off.
    final sections = isEn
        ? const [
            _SectionData(
              icon: Icons.cloud_outlined,
              title: 'Where is your data stored?',
              body: 'What you enter in the app, and your conversations, '
                  'are stored on cloud servers over the internet.',
            ),
            _SectionData(
              icon: Icons.visibility_outlined,
              title: 'Who can see it?',
              body: 'Only the research team, when the study needs it.',
            ),
            _SectionData(
              icon: Icons.share_outlined,
              title: 'Is anything shared with other companies?',
              body: 'Some features use other companies\' services, '
                  'including AI services, to process what you enter. '
                  'We do not give your data to advertisers or insurers.',
            ),
            _SectionData(
              icon: Icons.delete_outline,
              title: 'Want to leave the study or delete your data?',
              body: 'Please contact the research team (email below). '
                  'We will take care of it for you.',
            ),
            _SectionData(
              icon: Icons.description_outlined,
              title: 'More details',
              body: 'Please see the research consent form you signed.',
            ),
          ]
        : const [
            _SectionData(
              icon: Icons.cloud_outlined,
              title: '你嘅資料擺喺邊？',
              body: '你喺 app 入面填嘅嘢，同埋傾偈嘅紀錄，'
                  '會經網絡儲存喺雲端伺服器。',
            ),
            _SectionData(
              icon: Icons.visibility_outlined,
              title: '邊個睇得到？',
              body: '只有研究團隊會按研究需要查閱。',
            ),
            _SectionData(
              icon: Icons.share_outlined,
              title: '會唔會交畀其他公司？',
              body: '部分功能會用其他公司嘅服務（包括人工智能服務）'
                  '處理你輸入嘅內容。'
                  '我哋唔會將你嘅資料交畀廣告商或者保險公司。',
            ),
            _SectionData(
              icon: Icons.delete_outline,
              title: '想退出研究或者刪除資料？',
              body: '請聯絡研究團隊（下面嘅電郵），我哋會幫你處理。',
            ),
            _SectionData(
              icon: Icons.description_outlined,
              title: '想知多啲？',
              body: '詳情請參閱你簽署嘅研究同意書。',
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
                ? 'Here is, in short, how your data is handled.'
                : '下面簡單講下你嘅資料點樣處理。',
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
            isEn ? 'Last updated: October 2026' : '最後更新：2026 年 10 月',
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

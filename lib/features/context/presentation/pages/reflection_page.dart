import 'package:flutter/material.dart';

class ReflectionPage extends StatelessWidget {
  const ReflectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final prompts = [
      '呢次互動入面，邊一刻最有被連結嘅感覺？',
      '有冇邊個位你其實想再多行一步，但最後冇做？',
      '下次如果想拉近少少距離，最細嘅下一步可以係乜？',
    ];

    final items = [
      const _ReflectionItem(
        title: '同朋友短訊來往',
        when: '尋日',
        feeling: '有少少連結，但未夠深入',
        gap: '對方有回覆，但自己冇再展開話題。',
      ),
      const _ReflectionItem(
        title: '家庭群組互動',
        when: '三日前',
        feeling: '有存在感，但唔算被理解',
        gap: '互動比較表面，冇講到自己真正狀態。',
      ),
      const _ReflectionItem(
        title: '同事午飯閒聊',
        when: '今個星期',
        feeling: '氣氛輕鬆',
        gap: '有陪伴感，但關係未去到可以傾私人事。',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('互動反思'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '呢頁用嚟回顧最近嘅接觸，睇下「有互動」同「有連結感」係咪同一回事。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 28,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '反思提示',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...prompts.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${entry.key + 1}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 22,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.when,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ReflectionField(
                        icon: Icons.mood_outlined,
                        label: '感受',
                        text: item.feeling,
                      ),
                      const SizedBox(height: 12),
                      _ReflectionField(
                        icon: Icons.swap_vert_outlined,
                        label: '落差',
                        text: item.gap,
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

class _ReflectionField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _ReflectionField({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyLarge,
              children: [
                TextSpan(
                  text: '$label：',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReflectionItem {
  final String title;
  final String when;
  final String feeling;
  final String gap;

  const _ReflectionItem({
    required this.title,
    required this.when,
    required this.feeling,
    required this.gap,
  });
}

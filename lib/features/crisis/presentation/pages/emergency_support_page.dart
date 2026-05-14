import 'package:flutter/material.dart';

import '../../../../core/safety/safety_overlay.dart';

class EmergencySupportPage extends StatelessWidget {
  const EmergencySupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafetyOverlaySuppressor(child: Scaffold(
      appBar: AppBar(
        title: const Text('即時支援'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.priority_high_rounded,
                      size: 32,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '如果你或者身邊嘅人有即時危險',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '請立即撥 999，或者去最近嘅急症室。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    icon: const Icon(Icons.local_phone_rounded, size: 30),
                    label: const Text('撥 999'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.support_agent_outlined,
            title: '24 小時情緒支援熱線',
          ),
          const SizedBox(height: 14),
          const _HotlineCard(
            name: '撒瑪利亞會',
            number: '2896 0000',
            hours: '全日 24 小時',
            note: '可以粵語、普通話或英語溝通。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '生命熱線',
            number: '2382 0000',
            hours: '全日 24 小時',
            note: '面對情緒困擾、孤獨時可以致電。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '長者安居協會「平安鐘」',
            number: '2338 8312',
            hours: '全日 24 小時',
            note: '專為長者而設，處理緊急同日常需要。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '社會福利署熱線',
            number: '2343 2255',
            hours: '全日 24 小時',
            note: '可以轉介社工支援同社區資源。',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.contacts_outlined,
            title: '你嘅信任聯絡人',
          ),
          const SizedBox(height: 14),
          const _TrustedContactCard(
            name: '表姐',
            relation: '家人',
            number: '9123 4567',
          ),
          const SizedBox(height: 12),
          const _TrustedContactCard(
            name: '阿May',
            relation: '朋友',
            number: '9876 5432',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add_alt, size: 26),
              label: const Text('加多一個信任聯絡人'),
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.self_improvement,
            title: '等嚟緊再深呼吸幾下',
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '現在可以試吓嘅幾個動作',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  const _TipRow(
                    number: '1',
                    text: '坐落或者攰住牆，慢慢深呼吸三次。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '2',
                    text: '望下周圍，講出你見到嘅三樣嘢。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '3',
                    text: '飲一啖水，畀身體一啲時間放鬆。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '4',
                    text: '撥電話或者傳訊息畀上面任何一個人。',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 30, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _HotlineCard extends StatelessWidget {
  final String name;
  final String number;
  final String hours;
  final String note;

  const _HotlineCard({
    required this.name,
    required this.number,
    required this.hours,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              number,
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.5,
              ),
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
                  hours,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.phone_rounded, size: 26),
                label: const Text('打呢個電話'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedContactCard extends StatelessWidget {
  final String name;
  final String relation;
  final String number;

  const _TrustedContactCard({
    required this.name,
    required this.relation,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.characters.first,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$relation・$number',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              iconSize: 32,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(Icons.phone_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final String number;
  final String text;

  const _TipRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

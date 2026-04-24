import 'package:flutter/material.dart';

class SocialMapPage extends StatelessWidget {
  const SocialMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final contacts = [
      const _SocialPerson(
        name: '阿May',
        relation: '朋友',
        closeness: 4,
        availability: 4,
        note: '最近少咗見面，但通常肯回應。',
      ),
      const _SocialPerson(
        name: '表姐',
        relation: '家人',
        closeness: 3,
        availability: 5,
        note: '支援感穩定，但自己未必成日主動搵佢。',
      ),
      const _SocialPerson(
        name: 'Sam',
        relation: '同事',
        closeness: 2,
        availability: 3,
        note: '日常會傾兩句，但未去到深入連結。',
      ),
      const _SocialPerson(
        name: '阿健',
        relation: '舊同學',
        closeness: 3,
        availability: 2,
        note: '有連結基礎，但近排聯絡疏咗。',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('社交關係圖'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '呢頁幫你睇到身邊邊啲關係重要，邊啲人容易聯絡、邊啲人比較有支援感。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          ...contacts.map(
            (person) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              person.name.characters.first,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name,
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  person.relation,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _ScoreRow(
                        icon: Icons.favorite_outline,
                        label: '連結感',
                        value: person.closeness,
                      ),
                      const SizedBox(height: 10),
                      _ScoreRow(
                        icon: Icons.phone_in_talk_outlined,
                        label: '可聯絡程度',
                        value: person.availability,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        person.note,
                        style: theme.textTheme.bodyLarge,
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

class _ScoreRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _ScoreRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 26, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final filled = index < value;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                size: 28,
                color: filled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SocialPerson {
  final String name;
  final String relation;
  final int closeness;
  final int availability;
  final String note;

  const _SocialPerson({
    required this.name,
    required this.relation,
    required this.closeness,
    required this.availability,
    required this.note,
  });
}

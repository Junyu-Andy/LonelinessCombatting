import 'package:flutter/material.dart';

class SocialMapPage extends StatelessWidget {
  const SocialMapPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Social Map'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '呢頁模擬社交關係圖，幫你睇到邊啲關係重要、邊啲人比較有支援感。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ...contacts.map(
            (person) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('關係：${person.relation}')),
                          Chip(label: Text('連結感：${person.closeness}/5')),
                          Chip(label: Text('可聯絡程度：${person.availability}/5')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(person.note),
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
import 'package:flutter/material.dart';
import 'check_in_page.dart';
import 'social_map_page.dart';
import 'reflection_page.dart';

class ContextPage extends StatelessWidget {
  const ContextPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '呢個模組負責理解使用者目前狀態，等之後嘅建議可以更貼地。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _ContextEntryCard(
            icon: Icons.monitor_heart_outlined,
            title: '快速 Check-in',
            subtitle: '收集目前心情、孤獨感，同最近社交經驗。',
            buttonText: '打開 Check-in',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CheckInPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _ContextEntryCard(
            icon: Icons.people_outline,
            title: 'Social Map',
            subtitle: '整理重要關係、支援感，同邊啲人比較容易聯絡。',
            buttonText: '打開 Social Map',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialMapPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _ContextEntryCard(
            icon: Icons.forum_outlined,
            title: '互動反思',
            subtitle: '回顧最近接觸，睇下邊度有連結感，邊度仲有落差。',
            buttonText: '打開反思頁',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReflectionPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ContextEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  const _ContextEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onTap,
                    child: Text(buttonText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
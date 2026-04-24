import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../context/presentation/pages/social_map_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          _GreetingBlock(now: now, appTitle: l10n.appTitle),
          const SizedBox(height: 24),
          _TodayCheckInCard(
            onStart: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CheckInPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _DailySuggestionCard(
            onReachOut: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialMapPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const _ConnectionMomentCard(),
          const SizedBox(height: 20),
          _StructureHintCard(text: l10n.homeStructureHint),
          const SizedBox(height: 20),
          const _BoundaryReminderCard(),
        ],
      ),
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  final DateTime now;
  final String appTitle;

  const _GreetingBlock({required this.now, required this.appTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = now.hour;
    final String greeting;
    final IconData icon;
    if (hour >= 5 && hour < 11) {
      greeting = '早晨！';
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 11 && hour < 14) {
      greeting = '午安！';
      icon = Icons.light_mode_outlined;
    } else if (hour >= 14 && hour < 18) {
      greeting = '下午好';
      icon = Icons.wb_cloudy_outlined;
    } else if (hour >= 18 && hour < 22) {
      greeting = '夜晚好';
      icon = Icons.nights_stay_outlined;
    } else {
      greeting = '夜深喇，慢慢嚟';
      icon = Icons.bedtime_outlined;
    }

    const weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLine = '${now.month} 月 ${now.day} 日　${weekdayNames[now.weekday - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                greeting,
                style: theme.textTheme.headlineLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          dateLine,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '歡迎返嚟 $appTitle。\n唔使急，一步一步嚟就得。',
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _TodayCheckInCard extends StatelessWidget {
  final VoidCallback onStart;

  const _TodayCheckInCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.favorite_outline,
                    size: 36,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日 Check-in',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '約 1 分鐘',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '同我講下你今日感覺點。揀三粒數字就得，唔需要打字。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: const Text('開始今日 Check-in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailySuggestionCard extends StatelessWidget {
  final VoidCallback onReachOut;

  const _DailySuggestionCard({required this.onReachOut});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wb_twilight_outlined,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  '今日小建議',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '試吓揀一個你熟悉嘅人，傳一句簡單嘅問候，例如：',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '「早晨，今日你身體精神嗎？我諗起你。」',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '短短一句都夠。就算對方未即刻覆，你已經行出咗第一步。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReachOut,
                icon: const Icon(Icons.people_outline, size: 26),
                label: const Text('睇下可以聯絡邊個'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionMomentCard extends StatelessWidget {
  const _ConnectionMomentCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 30,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  '近排嘅小連結',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '上個禮拜你同表姐喺家庭群組講咗幾句，氣氛輕鬆。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '呢類小小嘅接觸，慢慢累積起嚟就係支持。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructureHintCard extends StatelessWidget {
  final String text;

  const _StructureHintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundaryReminderCard extends StatelessWidget {
  const _BoundaryReminderCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  '溫馨提示',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '呢個 app 可以陪你整理心情同諗下下一步，但唔可以取代緊急支援。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '如果有即時需要，請聯絡屋企人、醫生，或者撥 999。',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

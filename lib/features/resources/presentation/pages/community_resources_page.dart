import 'package:flutter/material.dart';

class CommunityResourcesPage extends StatelessWidget {
  const CommunityResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('社區資源'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '身邊其實有好多可以支持你嘅地方。揀一個最近、最方便嘅就得。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.elderly_outlined,
            title: '附近嘅長者中心',
          ),
          const SizedBox(height: 14),
          const _CentreCard(
            name: '社區長者鄰舍中心（示範）',
            district: '油尖旺',
            distance: '步行約 10 分鐘',
            hours: '星期一至六　9:00-17:00',
            activities: ['一齊飲茶', '太極班', '健康講座'],
          ),
          const SizedBox(height: 12),
          const _CentreCard(
            name: '聖雅各福群會長者服務（示範）',
            district: '灣仔',
            distance: '一程巴士',
            hours: '星期一至五　9:30-17:30',
            activities: ['興趣班', '義工配對', '社工支援'],
          ),
          const SizedBox(height: 12),
          const _CentreCard(
            name: '耆康會活動中心（示範）',
            district: '觀塘',
            distance: '港鐵加步行',
            hours: '星期二至日　10:00-18:00',
            activities: ['粵曲班', '書法班', '老友記聚會'],
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.calendar_month_outlined,
            title: '今個星期可以去嘅活動',
          ),
          const SizedBox(height: 14),
          const _EventCard(
            day: '星期三',
            time: '上午 10:00',
            title: '社區茶敘會',
            location: '樓下商場平台',
          ),
          const SizedBox(height: 12),
          const _EventCard(
            day: '星期四',
            time: '下午 3:00',
            title: '太極入門班',
            location: '長者鄰舍中心',
          ),
          const SizedBox(height: 12),
          const _EventCard(
            day: '星期六',
            time: '早上 8:30',
            title: '晨運郊遊團',
            location: '港鐵大圍站集合',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.volunteer_activism_outlined,
            title: '義工陪伴同電話問候',
          ),
          const SizedBox(height: 14),
          const _ServiceCard(
            name: '「耆暖計劃」義工電話探訪',
            description: '有義工每星期打電話嚟傾吓偈，唔使出街都有陪伴。',
            actionLabel: '了解申請方法',
          ),
          const SizedBox(height: 12),
          const _ServiceCard(
            name: '社區送餐同家訪',
            description: '由社工或義工定期家訪，亦可協助送飯盒。',
            actionLabel: '睇下點樣申請',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.menu_book_outlined,
            title: '專題資訊',
          ),
          const SizedBox(height: 14),
          const _InfoLinkTile(
            icon: Icons.health_and_safety_outlined,
            title: '衞生署長者健康服務',
          ),
          const _InfoLinkTile(
            icon: Icons.apartment_outlined,
            title: '房屋署長者居住選擇',
          ),
          const _InfoLinkTile(
            icon: Icons.school_outlined,
            title: '長者學苑課程',
          ),
          const _InfoLinkTile(
            icon: Icons.handshake_outlined,
            title: '社區互助小組',
          ),
        ],
      ),
    );
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

class _CentreCard extends StatelessWidget {
  final String name;
  final String district;
  final String distance;
  final String hours;
  final List<String> activities;

  const _CentreCard({
    required this.name,
    required this.district,
    required this.distance,
    required this.hours,
    required this.activities,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            _IconLine(
              icon: Icons.place_outlined,
              text: '$district・$distance',
            ),
            const SizedBox(height: 8),
            _IconLine(
              icon: Icons.schedule,
              text: hours,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: activities
                  .map(
                    (activity) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        activity,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.map_outlined, size: 24),
                    label: const Text('睇地圖'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.phone_rounded, size: 24),
                    label: const Text('打電話'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final String day;
  final String time;
  final String title;
  final String location;

  const _EventCard({
    required this.day,
    required this.time,
    required this.title,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

class _ServiceCard extends StatelessWidget {
  final String name;
  final String description;
  final String actionLabel;

  const _ServiceCard({
    required this.name,
    required this.description,
    required this.actionLabel,
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
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward_rounded, size: 22),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLinkTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _InfoLinkTile({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {},
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 28,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

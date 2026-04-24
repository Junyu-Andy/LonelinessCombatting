import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';

class ActionSupportPage extends StatelessWidget {
  const ActionSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.actionTab,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.actionSubtitle,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.stairs_outlined,
            title: '今日可以行嘅一小步',
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '2 分鐘',
            title: '傳一個短訊畀表姐',
            detail: '「早晨，最近身體點？有空飲茶。」',
            why: '表姐通常肯回應，係你其中一個穩定嘅支持。',
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '5 分鐘',
            title: '打個電話畀阿May',
            detail: '問下佢週末點樣，聽聲比打字更貼近啲。',
            why: '近排同阿May少咗見面，一通短短嘅電話可以重新接返條線。',
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '15 分鐘',
            title: '落樓下公園坐一陣',
            detail: '帶少少水，唔需要特登搵人傾偈。',
            why: '換一換環境，孤獨感會散啲。就算淨係見到人嚟嚟往往都有幫助。',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.chat_bubble_outline,
            title: '唔知點開口？揀一句用得',
          ),
          const SizedBox(height: 14),
          const _OpenerCard(
            audience: '畀屋企人',
            line: '「今日突然諗起你，想問聲好。食咗飯未？」',
          ),
          const SizedBox(height: 12),
          const _OpenerCard(
            audience: '畀朋友',
            line: '「好耐冇傾，最近忙緊啲乜？我想知你點。」',
          ),
          const SizedBox(height: 12),
          const _OpenerCard(
            audience: '畀舊同學／同事',
            line: '「見到一樣嘢諗起你，所以想同你講聲 hi。」',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.park_outlined,
            title: '想換下節奏？試吓呢啲',
          ),
          const SizedBox(height: 14),
          const _ActivityGrid(),
          const SizedBox(height: 28),
          const _SafetyFooter(),
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

class _TinyStepCard extends StatelessWidget {
  final String effort;
  final String title;
  final String detail;
  final String why;

  const _TinyStepCard({
    required this.effort,
    required this.title,
    required this.detail,
    required this.why,
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
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        effort,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      why,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text('會試吓'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next_rounded, size: 24),
                    label: const Text('今次唔啱'),
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

class _OpenerCard extends StatelessWidget {
  final String audience;
  final String line;

  const _OpenerCard({required this.audience, required this.line});

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
              audience,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              line,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.copy_rounded, size: 22),
                label: const Text('複製呢句'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid();

  @override
  Widget build(BuildContext context) {
    final activities = const [
      _Activity(
        icon: Icons.self_improvement,
        title: '靜靜坐 3 分鐘',
        tag: '一個人都得',
      ),
      _Activity(
        icon: Icons.directions_walk,
        title: '去附近行 10 分鐘',
        tag: '一個人都得',
      ),
      _Activity(
        icon: Icons.local_cafe_outlined,
        title: '約舊朋友飲茶',
        tag: '需要約人',
      ),
      _Activity(
        icon: Icons.volunteer_activism_outlined,
        title: '去社區中心／長者中心',
        tag: '會見到人',
      ),
    ];

    return Column(
      children: activities
          .map(
            (activity) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActivityTile(activity: activity),
            ),
          )
          .toList(),
    );
  }
}

class _Activity {
  final IconData icon;
  final String title;
  final String tag;

  const _Activity({required this.icon, required this.title, required this.tag});
}

class _ActivityTile extends StatelessWidget {
  final _Activity activity;

  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                activity.icon,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.tag,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 30,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyFooter extends StatelessWidget {
  const _SafetyFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              size: 28,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '如果情緒好低落或者覺得撐唔住，請直接聯絡屋企人或者撥打緊急求助電話 999。',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

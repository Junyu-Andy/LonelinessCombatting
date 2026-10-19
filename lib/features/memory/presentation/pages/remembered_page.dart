/// 「我記得嘅嘢」 — the user's view of memory v1.
///
/// Lists everything the companions may draw on, grouped the way the user
/// would think about it, with large text and one tap to delete. Sensitive
/// items the server extracted wait here for an explicit go-ahead before
/// any companion uses them. The page can only read, delete and confirm
/// (firestore.rules); it can never add or edit what is remembered.
///
/// T31: with [RemoteFeatureFlags.memoryLayersNoticeEnabled] on, the S7
/// notice (which companion remembers what) sits at the top of the lists.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/memory/memory_mode.dart';
import '../../../../core/memory/memory_v1_service.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';
import '../../data/memory_layers_copy.dart';

class RememberedPage extends StatelessWidget {
  const RememberedPage({super.key, this.service = const MemoryV1Service()});

  final MemoryV1Service service;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.of(context).profile;
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'What I remember' : '我記得嘅嘢')),
      body: SafeArea(
        child: profile == null
            ? _Empty(text: isEn ? 'Please sign in first.' : '請先登入。')
            : !MemoryModes.of(profile).isV1
                ? _Empty(
                    text: isEn
                        ? 'Memory is off. Nothing new is being remembered.'
                        : '記憶已經熄咗，而家唔會記住新嘅嘢。',
                  )
                : _Lists(uid: profile.uid, service: service),
      ),
    );
  }
}

class _Lists extends StatelessWidget {
  const _Lists({required this.uid, required this.service});

  final String uid;
  final MemoryV1Service service;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return StreamBuilder<List<MemoryItem>>(
      stream: service.watch(uid, MemoryLayer.fact),
      builder: (context, facts) => StreamBuilder<List<MemoryItem>>(
        stream: service.watch(uid, MemoryLayer.followup),
        builder: (context, followups) => StreamBuilder<List<MemoryItem>>(
          stream: service.watch(uid, MemoryLayer.summary),
          builder: (context, summaries) {
            final f = facts.data ?? const <MemoryItem>[];
            final pending = f.where((i) => i.pendingConfirmation).toList();
            final active = f.where((i) => !i.pendingConfirmation).toList();
            final fu = followups.data ?? const <MemoryItem>[];
            final su = summaries.data ?? const <MemoryItem>[];
            if (facts.connectionState == ConnectionState.waiting &&
                !facts.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final notice = RemoteFeatureFlags
                    .current.memoryLayersNoticeEnabled
                ? const _LayersNotice()
                : null;
            if (pending.isEmpty && active.isEmpty && fu.isEmpty &&
                su.isEmpty) {
              final empty = _Empty(
                text: isEn
                    ? 'Nothing remembered yet.'
                    : '暫時未記住任何嘢。',
              );
              if (notice == null) return empty;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [notice, empty],
              );
            }
            // 10/19 (Junyu): the lists grow for weeks, so facts are grouped
            // by category and past chats by day, each group a fold-out
            // with its count; one line at the top says how much there is.
            final factGroups = _groupFacts(active);
            final dayGroups = _groupByDay(su);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (notice != null) notice,
                _Header(
                  isEn
                      ? '${active.length} things about you · '
                          '${su.length} past chats'
                      : '記住咗 ${active.length} 件關於你嘅嘢、'
                          '${su.length} 次傾偈',
                  null,
                ),
                if (pending.isNotEmpty) ...[
                  _Header(
                    isEn ? 'Should I remember these?' : '呢啲要唔要記住？',
                    isEn
                        ? 'Nobody uses these until you say yes.'
                        : '你話好之前，冇人會用到呢啲。',
                  ),
                  for (final i in pending)
                    _ItemCard(item: i, uid: uid, service: service,
                        confirmable: true),
                ],
                if (active.isNotEmpty) ...[
                  _Header(isEn ? 'About you' : '關於你嘅嘢', null),
                  for (final g in factGroups)
                    _Group(
                      title: _categoryLabel(g.key, isEn),
                      count: g.value.length,
                      // Short groups stay open; long ones fold.
                      initiallyExpanded: g.value.length <= 3,
                      children: [
                        for (final i in g.value)
                          _ItemCard(item: i, uid: uid, service: service),
                      ],
                    ),
                ],
                if (fu.isNotEmpty) ...[
                  _Header(isEn ? 'Things to ask about' : '記住要關心嘅事', null),
                  for (final i in fu)
                    _ItemCard(item: i, uid: uid, service: service),
                ],
                if (su.isNotEmpty) ...[
                  _Header(isEn ? 'Past chats' : '之前傾過', null),
                  for (var k = 0; k < dayGroups.length; k++)
                    _Group(
                      title: _dayLabel(dayGroups[k].key, isEn),
                      count: dayGroups[k].value.length,
                      // Only the most recent day open.
                      initiallyExpanded: k == 0,
                      children: [
                        for (final i in dayGroups[k].value)
                          _ItemCard(item: i, uid: uid, service: service),
                      ],
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// S7, word for word (the copy is final in Cantonese only).
class _LayersNotice extends StatelessWidget {
  const _LayersNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('memory_layers_notice'),
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(MemoryLayersCopy.s7, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

/// Server categories in display order (functions/memory.js CATEGORIES);
/// anything unknown goes last under 其他.
const _categoryOrder = <String>[
  'name', 'family', 'living', 'routine', 'hobby', 'preference', 'event',
  'health', 'feeling', 'story', 'grief',
];

/// S20 — the category names the page shows (the same words as the server's
/// category list, memory.js).
String _categoryLabel(String key, bool isEn) {
  const zh = {
    'name': '稱呼', 'family': '家人', 'living': '居住情況', 'routine': '日常',
    'hobby': '興趣', 'preference': '其他喜好', 'event': '重要事件',
    'health': '健康', 'feeling': '心事', 'story': '回憶', 'grief': '哀傷',
  };
  const en = {
    'name': 'Name', 'family': 'Family', 'living': 'Living', 'routine': 'Routine',
    'hobby': 'Hobbies', 'preference': 'Preferences', 'event': 'Events',
    'health': 'Health', 'feeling': 'Feelings', 'story': 'Stories',
    'grief': 'Grief',
  };
  return (isEn ? en : zh)[key] ?? (isEn ? 'Other' : '其他');
}

List<MapEntry<String, List<MemoryItem>>> _groupFacts(List<MemoryItem> facts) {
  final by = <String, List<MemoryItem>>{};
  for (final f in facts) {
    final k = _categoryOrder.contains(f.category) ? f.category! : 'other';
    (by[k] ??= []).add(f);
  }
  final keys = [..._categoryOrder, 'other'].where(by.containsKey);
  return [for (final k in keys) MapEntry(k, by[k]!)];
}

/// Summaries by their day (title is the server's day key, YYYY-MM-DD),
/// newest day first.
List<MapEntry<String, List<MemoryItem>>> _groupByDay(List<MemoryItem> su) {
  final by = <String, List<MemoryItem>>{};
  for (final i in su) {
    (by[i.title] ??= []).add(i);
  }
  final days = by.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) MapEntry(d, by[d]!)];
}

String _dayLabel(String dayKey, bool isEn) {
  final now = DateTime.now();
  String key(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
  if (dayKey == key(now)) return isEn ? 'Today' : '今日';
  if (dayKey == key(now.subtract(const Duration(days: 1)))) {
    return isEn ? 'Yesterday' : '昨日';
  }
  final parts = dayKey.split('-');
  if (parts.length == 3) {
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m != null && d != null) {
      return isEn ? dayKey : '$m月$d日';
    }
  }
  return dayKey;
}

/// A fold-out group: 「家人（3）」 or 「今日（2）」.
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.count,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final int count;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('mem_group_$title'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text('$title（$count）',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        children: children,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.uid,
    required this.service,
    this.confirmable = false,
  });

  final MemoryItem item;
  final String uid;
  final MemoryV1Service service;
  final bool confirmable;

  String _agentName(BuildContext context, bool isEn) {
    final agent = AgentRegistry.tryById(item.agentId);
    if (agent == null) return '';
    final variant = agent.resolveVariant(
        AppSettingsScope.read(context).profile?.ahJanAhBakVariant);
    return isEn ? variant.displayNameEn : variant.displayNameZh;
  }

  Future<void> _delete(BuildContext context, bool isEn) async {
    final ok = await showAppConfirm(
      context: context,
      title: isEn ? 'Forget this?' : '唔好再記住呢樣？',
      message: item.title,
      confirmLabel: isEn ? 'Forget' : '唔好記',
      destructive: true,
    );
    if (ok) await service.delete(uid, item);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final agent = AgentRegistry.tryById(item.agentId);
    final who = _agentName(context, isEn);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.body, style: theme.textTheme.bodyLarge),
                      ],
                      if (who.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          isEn ? 'Told to $who' : '同$who講嘅',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: agent?.accentColor ??
                                theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!confirmable)
                  IconButton(
                    iconSize: 28,
                    tooltip: isEn ? 'Forget' : '唔好記',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(context, isEn),
                  ),
              ],
            ),
            if (confirmable) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => service.confirm(uid, item),
                    child: Text(isEn ? 'Yes, remember' : '好，記住'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => _delete(context, isEn),
                    child: Text(isEn ? 'No, forget it' : '唔好記'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

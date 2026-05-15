import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/memory/memory_store.dart';
import '../../data/reminiscence_themes.dart';

/// Spec §M3 Arm B step 4: "Past entries are accessible as a list ('My
/// memories'), but the system does not refer back to them."
///
/// Reuses the same Firestore subcollections that the saved sessions
/// write to, so both arms see whatever they've stored. Each entry shows
/// week number → preview → tap to expand.
class ReminiscenceMemoriesPage extends StatefulWidget {
  const ReminiscenceMemoriesPage({super.key});

  @override
  State<ReminiscenceMemoriesPage> createState() =>
      _ReminiscenceMemoriesPageState();
}

class _ReminiscenceMemoriesPageState extends State<ReminiscenceMemoriesPage> {
  Map<int, List<MemoryEntry>>? _byWeek;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_byWeek == null) _load();
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    final core = CoreServicesScope.of(context);
    if (profile == null) {
      setState(() {
        _byWeek = {};
        _loading = false;
      });
      return;
    }
    final map = <int, List<MemoryEntry>>{};
    for (final t in ReminiscenceTheme.all) {
      final entries = await core.memory.recent(
        uid: profile.uid,
        moduleId: 'm3_reminiscence_w${t.weekIndex}',
        limit: 10,
      );
      if (entries.isNotEmpty) map[t.weekIndex] = entries;
    }
    if (!mounted) return;
    setState(() {
      _byWeek = map;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'My memories' : '我嘅回憶')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_byWeek == null || _byWeek!.isEmpty)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isEn
                            ? 'Nothing saved yet. After a life-story session, '
                                'what you wrote will live here.'
                            : '暫時冇儲低嘅回憶。完成一節「人生點滴」之後，'
                                '你寫過嘅內容會放呢度。',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      for (final week in (_byWeek!.keys.toList()..sort()))
                        _WeekSection(
                          theme: ReminiscenceTheme.byIndex(week),
                          entries: _byWeek![week]!,
                          isEn: isEn,
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  final ReminiscenceTheme theme;
  final List<MemoryEntry> entries;
  final bool isEn;
  const _WeekSection({
    required this.theme,
    required this.entries,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${theme.weekIndex}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEn ? theme.titleEn : theme.titleZh,
                  style: t.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(e.createdAt, isEn),
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.summary,
                      style: t.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d, bool isEn) {
    final local = d.toLocal();
    if (isEn) {
      return '${local.year}-${_two(local.month)}-${_two(local.day)}';
    }
    return '${local.year} 年 ${local.month} 月 ${local.day} 日';
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

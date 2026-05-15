import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/m3_session_store.dart';
import '../../data/reminiscence_themes.dart';
import 'm3_session_detail_page.dart';

/// Spec §M3 Arm B step 4: "Past entries are accessible as a list ('My
/// memories'), but the system does not refer back to them."
///
/// Reads the new single-doc-per-week schema. Each week with status
/// 'completed' (and a non-empty summary) renders as a card; tap to open
/// the detail page where the user can re-read or re-edit.
class ReminiscenceMemoriesPage extends StatefulWidget {
  const ReminiscenceMemoriesPage({super.key});

  @override
  State<ReminiscenceMemoriesPage> createState() =>
      _ReminiscenceMemoriesPageState();
}

class _ReminiscenceMemoriesPageState extends State<ReminiscenceMemoriesPage> {
  Map<int, M3SessionDoc>? _byWeek;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_byWeek == null) _load();
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      setState(() {
        _byWeek = {};
        _loading = false;
      });
      return;
    }
    final store = M3SessionStore(available: auth.available);
    final docs = await store.readAll(
      uid: profile.uid,
      weekIndexes: [for (final t in ReminiscenceTheme.all) t.weekIndex],
    );
    final completed = <int, M3SessionDoc>{};
    for (final entry in docs.entries) {
      final doc = entry.value;
      if (doc.isCompleted && (doc.callbackSummary?.trim().isNotEmpty ?? false)) {
        completed[entry.key] = doc;
      }
    }
    if (!mounted) return;
    setState(() {
      _byWeek = completed;
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
                        _WeekCard(
                          theme: ReminiscenceTheme.byIndex(week),
                          doc: _byWeek![week]!,
                          isEn: isEn,
                          onReload: _load,
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final ReminiscenceTheme theme;
  final M3SessionDoc doc;
  final bool isEn;
  final VoidCallback onReload;
  const _WeekCard({
    required this.theme,
    required this.doc,
    required this.isEn,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final summary = doc.callbackSummary ?? '';
    final preview = summary.length > 160 ? '${summary.substring(0, 160)}…' : summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => M3SessionDetailPage(theme: theme),
              ),
            );
            onReload();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn ? theme.titleEn : theme.titleZh,
                            style: t.textTheme.titleMedium,
                          ),
                          if (doc.completedAt != null)
                            Text(
                              _formatDate(doc.completedAt!, isEn),
                              style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (doc.endSummaryUserEdited)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: t.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isEn ? 'edited' : '已編輯',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  preview,
                  style: t.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d, bool isEn) {
    final local = d.toLocal();
    if (isEn) return '${local.year}-${_two(local.month)}-${_two(local.day)}';
    return '${local.year} 年 ${local.month} 月 ${local.day} 日';
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

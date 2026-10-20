/// T39 (registry C19 / C20) — operations dashboard, page 2 "per person"
/// (one line per person, tap → the daily grid) and page 1 item 7 (today's
/// follow-up list).  For the unblinded researcher only; the server refuses
/// every other role and the page shows 冇權限 when the claims say so.
///
/// Process data only: nothing here is an outcome value (DJG-ES, UCLA-3,
/// PHQ-9, GAD-7, PGIC, the social-contact probe, continuance, AIMHS) and
/// no conversation text.  Filters: study period, arm, "3 日冇用".
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../enrollment/data/enrollment_service.dart';
import '../data/ops_dashboard_service.dart';
import 'ops_person_page.dart';

class OpsDashboardPage extends StatefulWidget {
  final OpsBackend? backend;

  /// Injectable for tests; defaults to the current user's ID-token claims.
  final Future<Map<String, dynamic>?> Function()? loadClaims;

  const OpsDashboardPage({super.key, this.backend, this.loadClaims});

  @override
  State<OpsDashboardPage> createState() => _OpsDashboardPageState();
}

Future<Map<String, dynamic>?> _currentClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return (await user.getIdTokenResult()).claims;
}

class _OpsDashboardPageState extends State<OpsDashboardPage> {
  late final OpsBackend _backend = widget.backend ?? CloudFunctionsOpsBackend();
  late Future<bool> _allowed = _checkClaims();
  Future<OpsPeople>? _people;
  String? _period; // null = all
  String? _arm; // null = all
  bool _onlyUnused = false;

  Future<bool> _checkClaims() async {
    try {
      final claims = await (widget.loadClaims ?? _currentClaims)()
          .timeout(const Duration(seconds: 5));
      return isUnblindedClaims(claims);
    } catch (_) {
      return false;
    }
  }

  void _reload() {
    setState(() {
      _allowed = _checkClaims();
      _people = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('營運看板：每人'),
        actions: [
          IconButton(
            key: const Key('ops_reload'),
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: _allowed,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data != true) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('冇權限。營運看板只開放畀非盲研究員。',
                    key: Key('ops_denied'), textAlign: TextAlign.center),
              ),
            );
          }
          return _body();
        },
      ),
    );
  }

  Widget _body() {
    // Started only once the claims allow it, so a server refusal is always
    // caught by this builder.
    _people ??= _backend.people();
    return FutureBuilder<OpsPeople>(
      future: _people,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final e = snap.error;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                e is OpsError ? opsErrorText(e.code) : opsErrorText('load_failed'),
                key: const Key('ops_error'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final data = snap.data!;
        final rows = data.people.where((p) {
          if (_period != null && p.studyPeriod != _period) return false;
          if (_arm != null && p.arm != _arm) return false;
          if (_onlyUnused && !p.unusedThreeDays) return false;
          return true;
        }).toList();
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Text('今日 ${data.today}（香港時間）　共 ${data.people.length} 人',
                style: theme.textTheme.bodyMedium),
            Text('顯示 ${rows.length} 人：${rows.map((p) => p.researchId).join('、')}',
                key: const Key('ops_filtered'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            _DueListCard(dueList: data.dueList),
            const SizedBox(height: 12),
            _Filters(
              period: _period,
              arm: _arm,
              onlyUnused: _onlyUnused,
              onPeriod: (v) => setState(() => _period = v),
              onArm: (v) => setState(() => _arm = v),
              onOnlyUnused: (v) => setState(() => _onlyUnused = v),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('冇符合條件嘅參加者。', key: Key('ops_empty')),
              ),
            for (final p in rows)
              _PersonTile(
                person: p,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      OpsPersonPage(researchId: p.researchId, backend: _backend),
                )),
              ),
          ],
        );
      },
    );
  }
}

class _DueListCard extends StatelessWidget {
  final List<OpsDue> dueList;
  const _DueListCard({required this.dueList});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('ops_due_list'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日回訪到期', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('連續 3–5 日冇打開 → WhatsApp；6 日或以上 → 電話。只計研究第 1–28 日。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (dueList.isEmpty)
              const Text('今日冇人到期。', key: Key('ops_due_empty'))
            else
              for (final d in dueList)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${d.researchId}　${periodLabelShort(d.studyPeriod)}　'
                    '連續 ${d.consecutiveUnopenedDays} 日冇打開　${stageLabel(d.stage)}',
                    key: Key('ops_due_${d.researchId}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final String? period;
  final String? arm;
  final bool onlyUnused;
  final ValueChanged<String?> onPeriod;
  final ValueChanged<String?> onArm;
  final ValueChanged<bool> onOnlyUnused;
  const _Filters({
    required this.period,
    required this.arm,
    required this.onlyUnused,
    required this.onPeriod,
    required this.onArm,
    required this.onOnlyUnused,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String?>(
          key: const Key('ops_filter_period'),
          value: period,
          items: const [
            DropdownMenuItem(value: null, child: Text('全部研究期')),
            DropdownMenuItem(value: 'PILOT', child: Text('試跑')),
            DropdownMenuItem(value: 'B', child: Text('Phase B')),
          ],
          onChanged: onPeriod,
        ),
        DropdownButton<String?>(
          key: const Key('ops_filter_arm'),
          value: arm,
          items: const [
            DropdownMenuItem(value: null, child: Text('全部組別')),
            DropdownMenuItem(value: 'A', child: Text('A 組（Hybrid）')),
            DropdownMenuItem(value: 'B', child: Text('B 組（規則組）')),
          ],
          onChanged: onArm,
        ),
        FilterChip(
          key: const Key('ops_filter_unused'),
          label: const Text('只睇 3 日冇用'),
          selected: onlyUnused,
          onSelected: onOnlyUnused,
        ),
      ],
    );
  }
}

String _fmtLastUse(DateTime? t) {
  if (t == null) return '—';
  final hk = t.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${hk.year}-${two(hk.month)}-${two(hk.day)} ${two(hk.hour)}:${two(hk.minute)}';
}

class _PersonTile extends StatelessWidget {
  final OpsPerson person;
  final VoidCallback onTap;
  const _PersonTile({required this.person, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = person;
    final theme = Theme.of(context);
    final companions = opsCompanions
        .map((c) => '${companionLabel(c)} ${p.validByCompanion[c] ?? 0}')
        .join('　');
    final weekly = p.weekly.entries
        .map((e) => '${e.key} ${weeklyCellLabel(e.value)}')
        .join('　');
    final memory = p.memory == null
        ? '不適用'
        : '共享 ${p.memory!['shared'] ?? 0}／私有 ${p.memory!['private'] ?? 0}';
    return Card(
      key: Key('ops_person_${p.researchId}'),
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Text(p.researchId, style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('${periodLabelShort(p.studyPeriod)}　${armLabelShort(p.arm)}',
                style: theme.textTheme.bodySmall),
            if (p.legacyBasis) ...[
              const SizedBox(width: 8),
              Chip(
                key: Key('ops_legacy_${p.researchId}'),
                label: const Text('舊構建口徑'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('登記 ${p.w0Date}　研究第 ${p.studyDay} 日　最後使用 ${_fmtLastUse(p.lastUseAt)}'),
            Text(
              '今日${p.openedToday ? '已' : '未'}打開　連續 ${p.consecutiveUnopenedDays} 日冇打開　'
              '回訪階段：${stageLabel(p.stage)}',
              key: Key('ops_stage_${p.researchId}'),
            ),
            Text('有效會話 ${p.validTotal}：$companions'),
            Text('類型：自由傾偈 ${p.validByType['free_chat'] ?? 0}　'
                '簽到 ${p.validByType['check_in'] ?? 0}　'
                '回憶 ${p.validByType['reminiscence'] ?? 0}'),
            Text('Brief PR：邀請 ${p.briefPr['invited'] ?? 0}　完成 ${p.briefPr['completed'] ?? 0}　'
                '部分 ${p.briefPr['partially_completed'] ?? 0}　跳過 ${p.briefPr['skipped'] ?? 0}　'
                '過期 ${p.briefPr['expired'] ?? 0}'),
            Text('每週問卷：$weekly'),
            Text('每日心情 ${p.moodDays} 日　記憶 $memory　'
                '語音 ${p.voice['uses'] ?? 0} 次／失敗 ${p.voice['failures'] ?? 0}'),
            Text('安全事件：急性 ${p.safety['acute'] ?? 0}　中級 ${p.safety['moderate'] ?? 0}　'
                '低級 ${p.safety['low'] ?? 0}　待確認 ${p.safety['pendingAck'] ?? 0}　'
                // 1020e 二.9: events the researcher marked 誤觸.
                '誤觸 ${p.safety['falseAlarm'] ?? 0}　'
                'W8 ${weeklyCellLabel(p.w8Status)}　Debrief 未做（T42）'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

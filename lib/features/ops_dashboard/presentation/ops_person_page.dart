/// T39 — one person: the daily grid (1014d 第 2 页第 3 项), the recent
/// sessions (no text) and the CSV export of this person's days.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ops_dashboard_service.dart';

class OpsPersonPage extends StatefulWidget {
  final String researchId;
  final OpsBackend backend;
  const OpsPersonPage(
      {super.key, required this.researchId, required this.backend});

  @override
  State<OpsPersonPage> createState() => _OpsPersonPageState();
}

class _OpsPersonPageState extends State<OpsPersonPage> {
  late Future<OpsPersonDetail> _detail = widget.backend.person(widget.researchId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('每日：${widget.researchId}'),
        actions: [
          IconButton(
            key: const Key('ops_person_csv'),
            icon: const Icon(Icons.download),
            tooltip: '匯出 CSV（每人每日）',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OpsCsvPage(
                  backend: widget.backend, researchId: widget.researchId),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入',
            onPressed: () => setState(() {
              _detail = widget.backend.person(widget.researchId);
            }),
          ),
        ],
      ),
      body: FutureBuilder<OpsPersonDetail>(
        future: _detail,
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
                  e is OpsError
                      ? opsErrorText(e.code)
                      : opsErrorText('load_failed'),
                  key: const Key('ops_person_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final d = snap.data!;
          final p = d.person;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              Text(
                '${periodLabelShort(p.studyPeriod)}　${armLabelShort(p.arm)}　登記 ${p.w0Date}　'
                '今日研究第 ${p.studyDay} 日',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '連續 ${p.consecutiveUnopenedDays} 日冇打開　回訪階段：${stageLabel(p.stage)}',
                key: const Key('ops_person_stage'),
              ),
              if (p.legacyBasis)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '舊構建口徑：呢部手機嘅 App 未有使用事件（T40），「打開」按當日有冇會話開始計，前台時長不可用。',
                    key: Key('ops_person_legacy'),
                  ),
                ),
              const SizedBox(height: 12),
              Text('每日（第 1 日到今日）', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (d.days.isEmpty)
                const Text('未到第 1 日。', key: Key('ops_days_empty'))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _DayGrid(days: d.days),
                ),
              const SizedBox(height: 16),
              Text('最近會話（最多 20 次，冇對話原文）',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (d.recentSessions.isEmpty)
                const Text('暫時冇會話。', key: Key('ops_sessions_empty'))
              else
                for (final s in d.recentSessions) _SessionLine(session: s),
            ],
          );
        },
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  final List<OpsDay> days;
  const _DayGrid({required this.days});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13);
    DataColumn col(String t) => DataColumn(label: Text(t, style: style));
    DataCell cell(String t, {Key? key}) =>
        DataCell(Text(t, style: style, key: key));
    return DataTable(
      key: const Key('ops_day_grid'),
      columnSpacing: 14,
      headingRowHeight: 36,
      dataRowMinHeight: 32,
      dataRowMaxHeight: 36,
      columns: [
        col('第幾日'),
        col('日期'),
        col('打開'),
        col('第一次打開'),
        col('前台分鐘'),
        col('小欣'),
        col('阿珍／阿伯'),
        col('通通'),
        col('Brief PR 邀請'),
        col('Brief PR 完成'),
      ],
      rows: [
        for (final d in days)
          DataRow(cells: [
            cell('${d.studyDay}'),
            cell(d.dayKey),
            cell(d.opened ? '有' : '冇', key: Key('ops_day_opened_${d.dayKey}')),
            cell(d.firstOpenAt ?? '—'),
            cell(
                d.foregroundMinutes == null ? '不可用' : '${d.foregroundMinutes}',
                key: Key('ops_day_minutes_${d.dayKey}')),
            cell('${d.validSessions['siu_yan'] ?? 0}'),
            cell('${d.validSessions['ah_jan_ah_bak'] ?? 0}'),
            cell('${d.validSessions['tung_tung'] ?? 0}'),
            cell('${d.briefPrInvited}'),
            cell('${d.briefPrCompleted}'),
          ]),
      ],
    );
  }
}

String _fmt(DateTime? t) {
  if (t == null) return '—';
  final hk = t.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${hk.month}/${hk.day} ${two(hk.hour)}:${two(hk.minute)}';
}

String _endReasonLabel(String? r) => switch (r) {
      'close_button' => '收尾按鈕',
      'back' => '返回',
      'switch_agent' => '轉陪伴者',
      'timeout' => '超時',
      'recovered' => '補判',
      'crisis' => '危機',
      'submitted' => '提交',
      'user_left' => '離開頁面',
      'app_killed' => 'App 關閉',
      null => '進行中',
      _ => r,
    };

class _SessionLine extends StatelessWidget {
  final OpsSession session;
  const _SessionLine({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${_fmt(s.startedAt)}　${companionLabel(s.agentId ?? '')}　'
        '${sessionTypeLabel(s.sessionType)}　老人 ${s.userMessageCount ?? '—'} 句　'
        '${s.durationMinutes == null ? '—' : '${s.durationMinutes} 分鐘'}　'
        '${_endReasonLabel(s.endReason)}　${s.isValid ? '有效' : '無效'}　'
        'Brief PR ${s.briefPrStatus ?? '—'}',
      ),
    );
  }
}

/// The CSV as text with a copy button: the researcher pastes it into a
/// file or a sheet.  Process data only (the server builds it).
class OpsCsvPage extends StatefulWidget {
  final OpsBackend backend;
  final String? researchId;
  const OpsCsvPage({super.key, required this.backend, this.researchId});

  @override
  State<OpsCsvPage> createState() => _OpsCsvPageState();
}

class _OpsCsvPageState extends State<OpsCsvPage> {
  late final Future<OpsCsv> _csv =
      widget.backend.csv(researchId: widget.researchId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CSV（每人每日）')),
      body: FutureBuilder<OpsCsv>(
        future: _csv,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Text(e is OpsError
                  ? opsErrorText(e.code)
                  : opsErrorText('load_failed')),
            );
          }
          final c = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${c.filename}　${c.rows} 行'),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('ops_csv_copy'),
                icon: const Icon(Icons.copy),
                label: const Text('複製全部'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c.csv));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製')));
                },
              ),
              const SizedBox(height: 8),
              SelectableText(c.csv,
                  key: const Key('ops_csv_text'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          );
        },
      ),
    );
  }
}

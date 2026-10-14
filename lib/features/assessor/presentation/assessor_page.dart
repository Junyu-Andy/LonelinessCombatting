/// T30 — the W4 outcome assessor's page (`blinded` role).
///
/// Only two things: the W4 due list (research ID, window day 25–31 from
/// W0, today's study day, entered / not entered, out-of-window) and the
/// paper DJG-ES entry ([OutcomeEntryPage]).  Nothing else of the App or
/// the researcher dashboard is reachable from here.  The text is for the
/// research staff, not for participants, so it is not subject to the
/// final-copy rule; the questionnaire items themselves are the approved
/// package §3 wording (`DjgW2Items`).
library;

import 'package:flutter/material.dart';

import '../data/assessor_service.dart';
import 'outcome_entry_page.dart';

const assessorInstrument = 'DJG-ES';

class AssessorPage extends StatefulWidget {
  final AssessorBackend? backend;
  final VoidCallback? onSignOut;

  /// Test hook for the entry page's default date.
  final DateTime Function()? today;

  const AssessorPage({super.key, this.backend, this.onSignOut, this.today});

  @override
  State<AssessorPage> createState() => _AssessorPageState();
}

class _AssessorPageState extends State<AssessorPage> {
  late final AssessorBackend _backend =
      widget.backend ?? CloudFunctionsAssessorBackend();
  late Future<DueList> _list = _backend.dueList();

  void _reload() {
    // A block body: setState's callback must not return the Future.
    setState(() {
      _list = _backend.dueList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('評估員：W4 到期名單'),
        actions: [
          IconButton(
            key: const Key('assessor_reload'),
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入',
            onPressed: _reload,
          ),
          if (widget.onSignOut != null)
            IconButton(
              key: const Key('assessor_sign_out'),
              icon: const Icon(Icons.logout),
              tooltip: '登出',
              onPressed: widget.onSignOut,
            ),
        ],
      ),
      body: FutureBuilder<DueList>(
        future: _list,
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
                  e is AssessorError
                      ? assessorErrorText(e.code)
                      : assessorErrorText('load_failed'),
                  key: const Key('assessor_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final list = snap.data!;
          if (list.rows.isEmpty) {
            return const Center(
              child: Text('暫時冇 Phase B 參加者。',
                  key: Key('assessor_empty')),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              Text('今日 ${list.today}　W4 窗口：W0 後第 25–31 日',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final row in list.rows) _DueTile(
                row: row,
                onEnter: row.isEntered(assessorInstrument)
                    ? null
                    : () => _open(row),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(DueRow row) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OutcomeEntryPage(
        researchId: row.researchId,
        backend: _backend,
        today: widget.today,
      ),
    ));
    if (done == true) _reload();
  }
}

class _DueTile extends StatelessWidget {
  final DueRow row;
  final VoidCallback? onEnter;
  const _DueTile({required this.row, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final entry = row.entered[assessorInstrument];
    final String status;
    if (entry != null) {
      status = entry.outOfWindow
          ? '已錄入（超窗）${entry.assessmentDate ?? ''}'
          : '已錄入 ${entry.assessmentDate ?? ''}';
    } else {
      status = switch (row.windowState) {
        'open' => '未錄入（窗口開放中）',
        'before' => '未到期',
        _ => '未錄入（已超窗）',
      };
    }
    return Card(
      key: Key('due_${row.researchId}'),
      child: ListTile(
        title: Text(row.researchId,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            'W4 窗口 ${row.windowStartDate} 至 ${row.windowEndDate}'
            '（今日第 ${row.studyDay} 日）\n$status'),
        isThreeLine: true,
        trailing: onEnter == null
            ? const Icon(Icons.check_circle_outline)
            : FilledButton(
                key: Key('enter_${row.researchId}'),
                onPressed: onEnter,
                child: const Text('錄入'),
              ),
      ),
    );
  }
}

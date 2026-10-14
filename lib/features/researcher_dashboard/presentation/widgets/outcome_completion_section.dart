/// T30 (registry C20) — pooled completion rates of the outcome
/// instruments for the `unblinded` role, before the data lock.
///
/// One row per instrument × timepoint: how many Phase B participants have
/// reached the timepoint and how many completed it — all participants
/// together, never per person, never per arm, never a value.  Rows with
/// fewer than 5 participants show no number (`suppressed`).  The numbers
/// come from the `outcomeCompletionSummary` Cloud Function
/// (functions/assessor.js completionSummary); the App reads no outcome
/// record itself.  Shown only when
/// `app_config/feature_flags.outcomeCompletionSummaryEnabled` is on.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class CompletionRow {
  final String instrument;
  final String timepoint;
  final bool suppressed;
  final int? n;
  final int? completed;
  final double? rate;

  const CompletionRow({
    required this.instrument,
    required this.timepoint,
    required this.suppressed,
    this.n,
    this.completed,
    this.rate,
  });

  factory CompletionRow.fromMap(Map<String, dynamic> m) => CompletionRow(
        instrument: m['instrument'] as String? ?? '',
        timepoint: m['timepoint'] as String? ?? '',
        suppressed: m['suppressed'] == true,
        n: (m['n'] as num?)?.toInt(),
        completed: (m['completed'] as num?)?.toInt(),
        rate: (m['rate'] as num?)?.toDouble(),
      );

  /// Display text; the n < 5 rule is the server's, repeated here only
  /// so a stray number can never be shown.
  String display({required int minN}) {
    if (suppressed || n == null || n! < minN || completed == null) {
      return '少於 $minN 人，不顯示';
    }
    final pct = ((rate ?? completed! / n!) * 100).round();
    return '$completed / $n（$pct%）';
  }
}

class CompletionSummary {
  final int minN;
  final List<CompletionRow> rows;
  const CompletionSummary({required this.minN, required this.rows});

  factory CompletionSummary.fromMap(Map<String, dynamic> m) =>
      CompletionSummary(
        minN: (m['minN'] as num?)?.toInt() ?? 5,
        rows: ((m['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => CompletionRow.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

Future<CompletionSummary> loadCompletionSummary() async {
  final r = await FirebaseFunctions.instanceFor(region: 'asia-east2')
      .httpsCallable('outcomeCompletionSummary')
      .call();
  return CompletionSummary.fromMap(Map<String, dynamic>.from(r.data as Map));
}

class OutcomeCompletionSection extends StatefulWidget {
  final bool isEn;

  /// Test hook; defaults to the Cloud Function.
  final Future<CompletionSummary> Function()? load;

  const OutcomeCompletionSection({super.key, required this.isEn, this.load});

  @override
  State<OutcomeCompletionSection> createState() =>
      _OutcomeCompletionSectionState();
}

class _OutcomeCompletionSectionState extends State<OutcomeCompletionSection> {
  late final Future<CompletionSummary> _summary =
      (widget.load ?? loadCompletionSummary)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CompletionSummary>(
      future: _summary,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Text(
            widget.isEn
                ? 'Completion summary unavailable (switch off or no access).'
                : '完成率未可用（開關未開或冇權限）。',
            key: const Key('outcome_completion_error'),
          );
        }
        final s = snap.data!;
        return Card(
          child: Column(
            children: [
              for (final row in s.rows)
                ListTile(
                  key: Key('completion_${row.instrument}_${row.timepoint}'),
                  dense: true,
                  title: Text('${row.instrument} ${row.timepoint}'),
                  trailing: Text(row.display(minN: s.minN)),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.isEn
                      ? 'All Phase B participants pooled; no arm, no values; '
                          'hidden under ${s.minN} participants.'
                      : '全體 Phase B 參加者合併；不分組、不顯示分數；'
                          '少於 ${s.minN} 人不顯示。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

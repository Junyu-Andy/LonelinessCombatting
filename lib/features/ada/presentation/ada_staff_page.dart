/// T17b (SPEC:C22, decision 0030) — researcher page for the Phase A
/// day-7 questions (ada.md §6.6–6.7): every participant's day-7 status
/// (未開始 / 進行中 / 已完成 / 已超時) and phone completion
/// (`channel: "phone_by_staff"`).
///
/// Kept in its own file.  Access: the staff roles `blinded` and
/// `unblinded` (decision 0029, T19) — checked again by the server in
/// every callable (`functions/ada.js`).  Research IDs are shown to the
/// unblinded role only, as the rules do for `research_id_map`.  Never shown in
/// a Phase B build.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/agents/agent_registry.dart' show AgentGenderVariant;
import '../../../core/config/phase_a_schedule_config.dart';
import '../data/ada_gate.dart';
import '../data/ada_items.dart';
import '../data/survey_draft_store.dart';
import 'day7_flow_page.dart';

/// Server status codes (functions/ada.js `day7Status`).
class AdaDay7Status {
  static const notStarted = 'not_started';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const overdue = 'overdue';
}

class AdaDay7Row {
  const AdaDay7Row({
    required this.uid,
    required this.label,
    required this.status,
    this.researchId,
    this.enrolmentDay,
    this.partial = false,
    this.channel,
    this.pushSentAt,
    this.reminderSentAt,
    this.variant,
    this.isTester = false,
  });

  final String uid;
  final String label;
  final String status;
  final String? researchId;
  final int? enrolmentDay;

  /// Overdue with some parts answered.
  final bool partial;

  /// Channel of the completed flow (app / phone_by_staff).
  final String? channel;
  final String? pushSentAt;
  final String? reminderSentAt;
  final AgentGenderVariant? variant;
  final bool isTester;

  static AdaDay7Row fromMap(Map<dynamic, dynamic> m) => AdaDay7Row(
        uid: '${m['uid']}',
        label: m['label'] is String ? m['label'] as String : '${m['uid']}',
        status: m['status'] is String
            ? m['status'] as String
            : AdaDay7Status.notStarted,
        researchId: m['researchId'] as String?,
        enrolmentDay: m['enrolmentDay'] is num
            ? (m['enrolmentDay'] as num).toInt()
            : null,
        partial: m['partial'] == true,
        channel: m['channel'] as String?,
        pushSentAt: m['pushSentAt'] as String?,
        reminderSentAt: m['reminderSentAt'] as String?,
        variant: AgentGenderVariant.tryParse(m['ahJanAhBakVariant'] as String?),
        isTester: m['isTester'] == true,
      );
}

abstract class AdaStaffSource {
  Future<List<AdaDay7Row>> day7Status();
}

class CallableAdaStaffSource implements AdaStaffSource {
  CallableAdaStaffSource({FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-east2');
  final FirebaseFunctions _fn;

  @override
  Future<List<AdaDay7Row>> day7Status() async {
    final res = await _fn.httpsCallable('adaStaffDay7Status').call<dynamic>();
    final rows = (res.data is Map ? res.data['rows'] : null) as List? ?? [];
    return [for (final r in rows) if (r is Map) AdaDay7Row.fromMap(r)];
  }
}

class AdaStaffPage extends StatefulWidget {
  const AdaStaffPage({super.key, this.source, this.storeFactory, this.parts});

  /// Test / screenshot hooks.
  final AdaStaffSource? source;
  final SurveyDraftStore Function()? storeFactory;
  final List<Day7Part>? parts;

  @override
  State<AdaStaffPage> createState() => _AdaStaffPageState();
}

class _AdaStaffPageState extends State<AdaStaffPage> {
  late final AdaStaffSource _source =
      widget.source ?? CallableAdaStaffSource();
  Future<List<AdaDay7Row>>? _rows;

  @override
  void initState() {
    super.initState();
    _rows = _source.day7Status();
  }

  void _refresh() => setState(() => _rows = _source.day7Status());

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';

  (String, Color) _chip(AdaDay7Row r, ColorScheme cs) {
    switch (r.status) {
      case AdaDay7Status.completed:
        return (_isEn ? 'Completed' : '已完成', Colors.green.shade700);
      case AdaDay7Status.inProgress:
        return (_isEn ? 'In progress' : '進行中', Colors.orange.shade800);
      case AdaDay7Status.overdue:
        return (
          r.partial
              ? (_isEn ? 'Overdue (partly done)' : '已超時（做咗一部分）')
              : (_isEn ? 'Overdue' : '已超時'),
          cs.error
        );
      default:
        return (_isEn ? 'Not started' : '未開始', cs.outline);
    }
  }

  Future<void> _phone(AdaDay7Row r) async {
    final parts = widget.parts ?? AdaGate.day7Parts();
    if (parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEn
              ? 'The day-7 questions are switched off.'
              : '第 7 日問卷未開（app_config/phaseA_schedule）。')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Day7FlowPage(
        parts: parts,
        adaTimepoint:
            PhaseAScheduleConfig.current.timepointById(kDay7TimepointId) ??
                PhaseAScheduleConfig.defaultAdaTimepoints.last,
        enrolmentDay: r.enrolmentDay,
        uid: r.uid,
        variant: r.variant,
        store: widget.storeFactory?.call() ?? CallableStaffSurveyDraftStore(),
        channel: AdaChannel.phoneByStaff,
        voiceEnabled: false,
      ),
    ));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _isEn;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Day-7 questions: status' : '第 7 日問卷完成情況'),
        actions: [
          IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: isEn ? 'Refresh' : '重新整理'),
        ],
      ),
      body: FutureBuilder<List<AdaDay7Row>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(isEn
                    ? 'Could not load (researcher role needed).'
                    : '讀取唔到（要研究員角色）。'),
              ),
            );
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return Center(
                child: Text(isEn ? 'No Phase A participants.' : '未有 Phase A 參與者。'));
          }
          final counts = <String, int>{};
          for (final r in rows) {
            counts[r.status] = (counts[r.status] ?? 0) + 1;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                isEn
                    ? 'Not started ${counts[AdaDay7Status.notStarted] ?? 0} · '
                        'In progress ${counts[AdaDay7Status.inProgress] ?? 0} · '
                        'Completed ${counts[AdaDay7Status.completed] ?? 0} · '
                        'Overdue ${counts[AdaDay7Status.overdue] ?? 0}'
                    : '未開始 ${counts[AdaDay7Status.notStarted] ?? 0} · '
                        '進行中 ${counts[AdaDay7Status.inProgress] ?? 0} · '
                        '已完成 ${counts[AdaDay7Status.completed] ?? 0} · '
                        '已超時 ${counts[AdaDay7Status.overdue] ?? 0}',
                key: const ValueKey('ada_staff_counts'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final r in rows)
                Card(
                  key: ValueKey('ada_staff_row_${r.uid}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            if (r.researchId != null) r.researchId!,
                            r.label,
                            if (r.isTester) (isEn ? '(tester)' : '（測試）'),
                          ].join('  '),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Builder(builder: (_) {
                          final (text, color) = _chip(r, cs);
                          return Container(
                            key: ValueKey('ada_staff_status_${r.uid}'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(text,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          );
                        }),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (r.enrolmentDay != null)
                              isEn
                                  ? 'Day ${r.enrolmentDay}'
                                  : '入組第 ${r.enrolmentDay} 天',
                            if (r.pushSentAt != null)
                              (isEn ? 'push ' : '推送 ') + r.pushSentAt!,
                            if (r.reminderSentAt != null)
                              (isEn ? 'reminder ' : '再提醒 ') +
                                  r.reminderSentAt!,
                            if (r.channel != null)
                              r.channel == AdaChannel.phoneByStaff
                                  ? (isEn ? 'by phone (staff)' : '電話代填')
                                  : 'App',
                          ].join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        if (r.status != AdaDay7Status.completed)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: ValueKey('ada_staff_phone_${r.uid}'),
                              onPressed: () => _phone(r),
                              icon: const Icon(Icons.phone),
                              label: Text(isEn
                                  ? 'Fill in by phone'
                                  : '電話代填'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

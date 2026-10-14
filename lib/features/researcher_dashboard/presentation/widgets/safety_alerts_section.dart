/// T34 (registry C12 / C19) — the safety-alert list of the researcher
/// dashboard and its 確認處理 (acknowledge) button.
///
/// Shown to the `unblinded` role only ([DashboardAccess.showsSafetyAlerts]);
/// `firestore.rules` lets only that role read `pi_alerts`.  The row shows
/// what the alert e-mail shows (research ID, time, level, source, companion,
/// acknowledgement / escalation state) and never the participant's wording,
/// the matched term or the arm.  Acknowledging goes through the
/// `acknowledgeAlert` Cloud Function (asia-east2), which checks the role
/// again and records who and when on the alert and in `alert_audit_log`;
/// the App never writes `pi_alerts`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// One `pi_alerts` row as the dashboard shows it.  Pure (no Firebase) so
/// the mapping is unit-testable.
class SafetyAlertView {
  const SafetyAlertView({
    required this.alertId,
    required this.researchId,
    required this.createdAt,
    required this.level,
    required this.sourceGroup,
    required this.agentId,
    required this.acknowledgedAt,
    required this.acknowledgedByEmail,
    required this.escalatedAt,
    required this.isTester,
    required this.alertVersion,
  });

  final String alertId;
  final String? researchId;
  final DateTime? createdAt;
  final String? level;
  final String? sourceGroup;
  final String? agentId;
  final DateTime? acknowledgedAt;
  final String? acknowledgedByEmail;
  final DateTime? escalatedAt;
  final bool isTester;
  final int alertVersion;

  bool get acknowledged => acknowledgedAt != null;
  bool get escalated => escalatedAt != null;

  /// From a `pi_alerts` document.  Works for the T19 (v2) row, which has
  /// no source / companion, and the T34 (v3) row.
  factory SafetyAlertView.fromData(String id, Map<String, dynamic> d) {
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return SafetyAlertView(
      alertId: id,
      researchId: d['researchId'] as String?,
      createdAt: ts(d['createdAt']),
      level: (d['tier'] as String?) ?? (d['level'] as String?),
      sourceGroup: d['sourceGroup'] as String?,
      agentId: d['agentId'] as String?,
      acknowledgedAt: ts(d['acknowledgedAt']),
      acknowledgedByEmail: d['acknowledgedByEmail'] as String?,
      escalatedAt: ts(d['escalatedAt']),
      isTester: d['isTester'] == true,
      alertVersion: (d['alertVersion'] as num?)?.toInt() ?? 2,
    );
  }

  /// Display text of the source bucket (same mapping as the e-mail,
  /// `functions/pi_alert.js` SOURCE_DISPLAY).  Researcher-facing copy.
  static String sourceLabel(String? group, {required bool isEn}) {
    switch (group) {
      case 'participant_input':
        return isEn ? 'Participant input' : '老人輸入';
      case 'ai_reply_scan':
        return isEn ? 'AI reply scan' : 'AI 回覆掃描';
      case 'questionnaire':
        return isEn ? 'Questionnaire' : '問卷';
      case 'assessor_entry':
        return isEn ? 'Assessor entry' : '評估員錄入';
      default:
        return isEn ? 'Unknown' : '未知';
    }
  }

  /// Acknowledgement / escalation state, one short phrase.
  static String stateLabel(SafetyAlertView a, {required bool isEn}) {
    if (a.acknowledged) {
      final by = a.acknowledgedByEmail;
      final who = by == null || by.isEmpty ? '' : ' · $by';
      return (isEn ? 'Acknowledged' : '已確認處理') + who;
    }
    if (a.escalated) return isEn ? 'Escalated to backup' : '已轉後備';
    return isEn ? 'Not acknowledged' : '未確認';
  }

  static String hkTime(DateTime? d) {
    if (d == null) return '—';
    final hk = d.toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${hk.year}-${two(hk.month)}-${two(hk.day)} '
        '${two(hk.hour)}:${two(hk.minute)}';
  }
}

/// Calls the `acknowledgeAlert` callable.  Separated so the widget can be
/// given a fake in tests.
typedef AcknowledgeAlert = Future<void> Function(String alertId);

Future<void> acknowledgeAlertViaFunction(String alertId) async {
  await FirebaseFunctions.instanceFor(region: 'asia-east2')
      .httpsCallable('acknowledgeAlert')
      .call<Map<String, dynamic>>({'alertId': alertId});
}

class SafetyAlertsSection extends StatelessWidget {
  const SafetyAlertsSection({
    super.key,
    required this.isEn,
    this.acknowledge = acknowledgeAlertViaFunction,
    this.limit = 30,
  });

  final bool isEn;
  final AcknowledgeAlert acknowledge;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('pi_alerts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint(context,
              isEn ? 'Could not load alerts.' : '告警列表讀取失敗。');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = snap.data!.docs
            .map((d) => SafetyAlertView.fromData(d.id, d.data()))
            .toList();
        if (rows.isEmpty) {
          return _hint(context, isEn ? 'No alerts.' : '暫時沒有告警。');
        }
        return Column(
          children: [
            for (final a in rows)
              SafetyAlertRow(
                  key: ValueKey('alert_${a.alertId}'),
                  alert: a,
                  isEn: isEn,
                  acknowledge: acknowledge),
          ],
        );
      },
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class SafetyAlertRow extends StatefulWidget {
  const SafetyAlertRow({
    super.key,
    required this.alert,
    required this.isEn,
    required this.acknowledge,
  });

  final SafetyAlertView alert;
  final bool isEn;
  final AcknowledgeAlert acknowledge;

  @override
  State<SafetyAlertRow> createState() => _SafetyAlertRowState();
}

class _SafetyAlertRowState extends State<SafetyAlertRow> {
  bool _busy = false;
  String? _error;

  Future<void> _ack() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.acknowledge(widget.alert.alertId);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            widget.isEn ? 'Failed: $e' : '確認失敗：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final isEn = widget.isEn;
    final theme = Theme.of(context);
    final acute = a.level == 'acute';
    final color = a.acknowledged
        ? theme.colorScheme.surfaceContainerHighest
        : acute
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.tertiaryContainer;
    final rid = a.researchId ??
        (isEn ? 'not registered' : '未登記');
    final head = [
      rid,
      SafetyAlertView.hkTime(a.createdAt),
      a.level ?? '—',
      if (a.isTester) (isEn ? 'tester' : '測試帳號'),
    ].join(' · ');
    final detail = a.alertVersion >= 3
        ? '${isEn ? 'Source' : '來源'}: '
            '${SafetyAlertView.sourceLabel(a.sourceGroup, isEn: isEn)}'
            ' · ${isEn ? 'Companion' : '陪伴者'}: ${a.agentId ?? '—'}'
        : (isEn
            ? 'Older alert (no source / companion recorded)'
            : '舊格式告警（沒有來源、陪伴者）');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(head, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('${isEn ? 'Alert' : '告警'}: pi_alerts/${a.alertId}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(SafetyAlertView.stateLabel(a, isEn: isEn),
                      style: theme.textTheme.bodySmall),
                ),
                if (!a.acknowledged)
                  FilledButton(
                    key: ValueKey('ack_${a.alertId}'),
                    onPressed: _busy ? null : _ack,
                    child: Text(isEn ? 'Acknowledge' : '確認處理'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

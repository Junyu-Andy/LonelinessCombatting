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
///
/// 1020e 二.9 — 「標記誤觸」 (false alarm), behind the remote switch
/// `safetyFalseAlarmMarkEnabled`: the `markSafetyFalseAlarm` function checks
/// the role and the switch again and stamps `falseAlarm` / `markedBy` /
/// `markedAt` on the alert, its safety event and that day's stopped chat
/// check-in row.  The App never reads `safety_events`; the row shows the
/// mark from the alert.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../core/feature_flags/remote_feature_flags.dart';

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
    this.primaryFailedAt,
    this.primaryFailedReason,
    this.emailSentAt,
    this.falseAlarm = false,
    this.falseAlarmMarkedAt,
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

  /// 10/14 fix + 1014e §2.4: the first e-mail did not go out (SMTP error
  /// or no recipient after the role check).  With no backup recipient
  /// configured nobody else is told, so the list must say so.
  final DateTime? primaryFailedAt;
  final String? primaryFailedReason;
  final DateTime? emailSentAt;

  /// 1020e 二.9 — the researcher marked this alert 誤觸 (false alarm).
  final bool falseAlarm;
  final DateTime? falseAlarmMarkedAt;

  bool get acknowledged => acknowledgedAt != null;
  bool get escalated => escalatedAt != null;
  bool get primaryFailed => primaryFailedAt != null;

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
      primaryFailedAt: ts(d['primaryFailedAt']),
      primaryFailedReason: d['primaryFailedReason'] as String?,
      emailSentAt: ts(d['emailSentAt']),
      falseAlarm: d['falseAlarm'] == true,
      falseAlarmMarkedAt: ts(d['markedAt']),
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
    if (a.primaryFailed) {
      final why = a.primaryFailedReason == 'no_recipients'
          ? (isEn ? 'no recipient' : '冇收件人')
          : (isEn ? 'send error' : '發送出錯');
      return isEn
          ? 'E-MAIL NOT SENT ($why) — nobody was told; handle now'
          : '郵件未發出（$why）— 冇人收到通知，請即處理';
    }
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

/// 1020e 二.9 — calls `markSafetyFalseAlarm`.  A fake in tests.
typedef MarkFalseAlarm = Future<void> Function(String alertId);

Future<void> markFalseAlarmViaFunction(String alertId) async {
  await FirebaseFunctions.instanceFor(region: 'asia-east2')
      .httpsCallable('markSafetyFalseAlarm')
      .call<Map<String, dynamic>>({'alertId': alertId});
}

class SafetyAlertsSection extends StatelessWidget {
  const SafetyAlertsSection({
    super.key,
    required this.isEn,
    this.acknowledge = acknowledgeAlertViaFunction,
    this.limit = 30,
    this.markFalseAlarm = markFalseAlarmViaFunction,
  });

  final bool isEn;
  final AcknowledgeAlert acknowledge;
  final int limit;

  /// Offered only while `safetyFalseAlarmMarkEnabled` is on.
  final MarkFalseAlarm markFalseAlarm;

  /// 1020e 二.9 — [mark] while the switch is on, else null (no button).
  static MarkFalseAlarm? offeredMark(MarkFalseAlarm mark) =>
      RemoteFeatureFlags.current.safetyFalseAlarmMarkEnabled ? mark : null;

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
                  acknowledge: acknowledge,
                  markFalseAlarm: offeredMark(markFalseAlarm)),
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
    this.markFalseAlarm,
  });

  final SafetyAlertView alert;
  final bool isEn;
  final AcknowledgeAlert acknowledge;

  /// 1020e 二.9 — non-null (switch on): the row offers 「標記誤觸」.
  final MarkFalseAlarm? markFalseAlarm;

  @override
  State<SafetyAlertRow> createState() => _SafetyAlertRowState();
}

class _SafetyAlertRowState extends State<SafetyAlertRow> {
  bool _busy = false;
  String? _error;

  /// Marked in this session (the list stream brings the stored mark).
  bool _markedHere = false;

  Future<void> _markFalseAlarm() async {
    final mark = widget.markFalseAlarm;
    if (mark == null) return;
    final isEn = widget.isEn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Mark as a false alarm?' : '標記為誤觸？'),
        content: Text(isEn
            ? 'Only when the participant confirmed it was a slip. If today\'s '
                'check-in stopped here, they can carry on from that question '
                'today.'
            : '只喺確認係老人誤觸先標記。如果今日嘅 check-in 喺呢度停咗，'
                '老人今日再入小欣頁會由停低嗰題繼續。'),
        actions: [
          TextButton(
            key: const ValueKey('false_alarm_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isEn ? 'Cancel' : '取消'),
          ),
          FilledButton(
            key: const ValueKey('false_alarm_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isEn ? 'Mark' : '確定標記'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mark(widget.alert.alertId);
      if (mounted) setState(() => _markedHere = true);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = isEn ? 'Failed: $e' : '標記失敗：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
            // 1020e 二.9 — 誤觸 mark (switch on), or the stored mark.
            if (a.falseAlarm || _markedHere) ...[
              const SizedBox(height: 4),
              Text(
                (isEn ? 'Marked false alarm' : '已標記誤觸') +
                    (a.falseAlarmMarkedAt == null
                        ? ''
                        : ' · ${SafetyAlertView.hkTime(a.falseAlarmMarkedAt)}'),
                key: ValueKey('false_alarm_marked_${a.alertId}'),
                style: theme.textTheme.bodySmall,
              ),
            ] else if (widget.markFalseAlarm != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: ValueKey('false_alarm_${a.alertId}'),
                  onPressed: _busy ? null : _markFalseAlarm,
                  child: Text(isEn ? 'Mark false alarm' : '標記誤觸'),
                ),
              ),
            ],
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

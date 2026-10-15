import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/safety_event_writer.dart';
import 'package:app_demo/features/researcher_dashboard/data/dashboard_access.dart';
import 'package:app_demo/features/researcher_dashboard/presentation/widgets/safety_alerts_section.dart';

/// T34 — safety alert e-mail, App side:
///   * `safety_events.crisisPageShown` is decided by the single writer from
///     the level, so both arms set it identically (dev-tasks-1010b T34 §1.4);
///   * the dashboard alert list is for the unblinded role only (§3.1);
///   * the alert row shows research ID / time / level / source / state and a
///     確認處理 button that calls the callable; an acknowledged row has none.
void main() {
  group('crisisPageShown (single writer, both arms)', () {
    test('true only for acute, whatever the match came from', () {
      expect(
          SafetyEventWriter.crisisPageShownFor(
              const DistressMatch(DistressLevel.acute, '想死')),
          isTrue);
      for (final level in [
        DistressLevel.none,
        DistressLevel.low,
        DistressLevel.moderateReview,
        DistressLevel.moderateInterrupt,
      ]) {
        expect(SafetyEventWriter.crisisPageShownFor(DistressMatch(level)),
            isFalse,
            reason: '$level never opens the crisis page');
      }
    });

    test('the lexicon result of one acute phrase gives the same answer in '
        'both arms (the writer has no arm input)', () {
      const detector = DistressDetector();
      final m = detector.analyze('我好想死');
      expect(m.level, DistressLevel.acute);
      // Arm A and Arm B share this writer; the field depends on the match
      // only, so calling it "for each arm" is the same call.
      final armA = SafetyEventWriter.crisisPageShownFor(m);
      final armB = SafetyEventWriter.crisisPageShownFor(m);
      expect(armA, isTrue);
      expect(armA, armB);
    });
  });

  group('DashboardAccess.showsSafetyAlerts', () {
    test('unblinded only', () {
      expect(DashboardAccess.unblinded.showsSafetyAlerts, isTrue);
      expect(DashboardAccess.blinded.showsSafetyAlerts, isFalse);
      expect(DashboardAccess.denied.showsSafetyAlerts, isFalse);
    });
  });

  group('SafetyAlertView', () {
    final created = DateTime.utc(2026, 10, 20, 2, 30); // 10:30 HKT
    final v3 = SafetyAlertView.fromData('AL1', {
      'researchId': 'PB-A01',
      'createdAt': Timestamp.fromDate(created),
      'level': 'acute',
      'tier': 'acute',
      'sourceGroup': 'ai_reply_scan',
      'agentId': 'siu_yan',
      'acknowledgedAt': null,
      'escalatedAt': null,
      'isTester': false,
      'alertVersion': 3,
    });

    test('maps the v3 row and the display labels', () {
      expect(v3.researchId, 'PB-A01');
      expect(v3.level, 'acute');
      expect(v3.acknowledged, isFalse);
      expect(v3.escalated, isFalse);
      expect(SafetyAlertView.hkTime(v3.createdAt), '2026-10-20 10:30');
      expect(SafetyAlertView.sourceLabel('ai_reply_scan', isEn: false),
          'AI 回覆掃描');
      expect(SafetyAlertView.sourceLabel('participant_input', isEn: true),
          'Participant input');
      expect(SafetyAlertView.sourceLabel('questionnaire', isEn: false), '問卷');
      expect(SafetyAlertView.sourceLabel('assessor_entry', isEn: true),
          'Assessor entry');
      expect(SafetyAlertView.sourceLabel(null, isEn: false), '未知');
      expect(SafetyAlertView.stateLabel(v3, isEn: false), '未確認');
    });

    test('1014e §2.4: a failed first e-mail is flagged in the list (no '
        'backup recipient → nobody else is told)', () {
      final failed = SafetyAlertView.fromData('f', {
        'alertVersion': 3,
        'escalationPending': true,
        'primaryFailedAt': Timestamp.fromDate(created),
        'primaryFailedReason': 'email_failed',
      });
      expect(failed.primaryFailed, isTrue);
      expect(SafetyAlertView.stateLabel(failed, isEn: false),
          '郵件未發出（發送出錯）— 冇人收到通知，請即處理');
      final noRcpt = SafetyAlertView.fromData('n', {
        'primaryFailedAt': Timestamp.fromDate(created),
        'primaryFailedReason': 'no_recipients',
      });
      expect(SafetyAlertView.stateLabel(noRcpt, isEn: true),
          'E-MAIL NOT SENT (no recipient) — nobody was told; handle now');
      // Acknowledged wins over the flag; a sent e-mail has no flag.
      final ackedFailed = SafetyAlertView.fromData('a', {
        'primaryFailedAt': Timestamp.fromDate(created),
        'acknowledgedAt': Timestamp.fromDate(created),
      });
      expect(SafetyAlertView.stateLabel(ackedFailed, isEn: false),
          startsWith('已確認處理'));
      final sent = SafetyAlertView.fromData('s', {
        'emailSentAt': Timestamp.fromDate(created),
      });
      expect(sent.primaryFailed, isFalse);
      expect(SafetyAlertView.stateLabel(sent, isEn: false), '未確認');
    });

    test('v2 (T19) rows still load, acknowledged / escalated states', () {
      final v2 = SafetyAlertView.fromData('old', {
        'uid': 'u',
        'researchId': null,
        'level': 'acute',
        'alertVersion': 2,
      });
      expect(v2.alertVersion, 2);
      expect(v2.sourceGroup, isNull);
      expect(SafetyAlertView.hkTime(v2.createdAt), '—');
      final acked = SafetyAlertView.fromData('a', {
        'acknowledgedAt': Timestamp.fromDate(created),
        'acknowledgedByEmail': 'junyu@x.hk',
      });
      expect(SafetyAlertView.stateLabel(acked, isEn: false),
          '已確認處理 · junyu@x.hk');
      final esc = SafetyAlertView.fromData('e', {
        'escalatedAt': Timestamp.fromDate(created),
      });
      expect(SafetyAlertView.stateLabel(esc, isEn: true),
          'Escalated to backup');
    });

    testWidgets('row shows the fields, 確認處理 calls the callable once',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafetyAlertRow(
            alert: v3,
            isEn: false,
            acknowledge: (id) async => calls.add(id),
          ),
        ),
      ));
      expect(find.textContaining('PB-A01'), findsOneWidget);
      expect(find.textContaining('2026-10-20 10:30'), findsOneWidget);
      expect(find.textContaining('AI 回覆掃描'), findsOneWidget);
      expect(find.textContaining('siu_yan'), findsOneWidget);
      expect(find.text('未確認'), findsOneWidget);
      expect(find.textContaining('pi_alerts/AL1'), findsOneWidget);
      await tester.tap(find.text('確認處理'));
      await tester.pumpAndSettle();
      expect(calls, ['AL1']);
    });

    testWidgets('an acknowledged row has no button; a failure is shown',
        (tester) async {
      final acked = SafetyAlertView.fromData('AL2', {
        'researchId': 'PB-B02',
        'level': 'acute',
        'alertVersion': 3,
        'sourceGroup': 'participant_input',
        'acknowledgedAt': Timestamp.fromDate(created),
        'acknowledgedByEmail': 'junyu@x.hk',
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            SafetyAlertRow(
                alert: acked, isEn: true, acknowledge: (_) async {}),
            SafetyAlertRow(
                alert: v3,
                isEn: true,
                acknowledge: (_) async => throw Exception('denied')),
          ]),
        ),
      ));
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.textContaining('Acknowledged · junyu@x.hk'), findsOneWidget);
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed:'), findsOneWidget);
    });
  });
}

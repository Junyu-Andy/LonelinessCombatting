// T25 (C16) — session validity rules, config mapping and the
// switch-off (legacy) behaviour.  Pure Dart, no Firestore.
import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/session/session_rules.dart';
import 'package:flutter_test/flutter_test.dart';

SessionTally chat(int replies, {int? sent, String? endReason}) => SessionTally(
      sessionType: SessionType.freeChat,
      userMessageCount: sent ?? replies,
      replyCount: replies,
      endReason: endReason,
    );

void main() {
  const v2 = SessionRules(v2: true, idleTimeoutMin: 30);

  group('PhaseBConfig T25 keys', () {
    test('defaults match the brief', () {
      const c = PhaseBConfig();
      expect(c.sessionBriefPrV2Enabled, isFalse);
      expect(c.sessionIdleTimeoutMinV2, 30);
      expect(c.briefPrDailyCapPerAgent, 1);
      expect(c.briefPrCatchUpExpiryHours, 2);
      expect(c.freeChatValidMinUserMessages, 3);
      expect(c.hybridCheckInValidRequiresMood, isTrue);
      expect(c.hybridCheckInValidMinUserMessages, 1);
      expect(c.hybridReminiscenceValidRequiresSave, isTrue);
    });

    test('switch is on only when literally true; numbers clamp', () {
      expect(PhaseBConfig.fromMap({'sessionBriefPrV2Enabled': 'true'})
          .sessionBriefPrV2Enabled, isFalse);
      expect(PhaseBConfig.fromMap({'sessionBriefPrV2Enabled': 1})
          .sessionBriefPrV2Enabled, isFalse);
      final c = PhaseBConfig.fromMap({
        'sessionBriefPrV2Enabled': true,
        'sessionIdleTimeoutMinV2': 0, // below min → default
        'briefPrDailyCapPerAgent': 2,
        'briefPrCatchUpExpiryHours': 3.9, // floors
        'freeChatValidMinUserMessages': 'x', // bad → default
        'hybridCheckInValidRequiresMood': false,
        'hybridCheckInValidMinUserMessages': 0,
        'hybridReminiscenceValidRequiresSave': 'no', // bad → default
      });
      expect(c.sessionBriefPrV2Enabled, isTrue);
      expect(c.sessionIdleTimeoutMinV2, 30);
      expect(c.briefPrDailyCapPerAgent, 2);
      expect(c.briefPrCatchUpExpiryHours, 3);
      expect(c.freeChatValidMinUserMessages, 3);
      expect(c.hybridCheckInValidRequiresMood, isFalse);
      expect(c.hybridCheckInValidMinUserMessages, 0);
      expect(c.hybridReminiscenceValidRequiresSave, isTrue);
    });
  });

  group('SessionRules.fromConfig', () {
    test('switch off = legacy: 10-minute idle from PhaseAConfig, v1 rows', () {
      final r = SessionRules.fromConfig(const PhaseBConfig(),
          a: const PhaseAConfig(sessionIdleTimeoutMin: 10));
      expect(r.v2, isFalse);
      expect(r.idleTimeout, const Duration(minutes: 10));
      expect(r.scheduleVersion, 1);
    });

    test('switch on = 30-minute idle, v2 rows, config carried over', () {
      final r = SessionRules.fromConfig(const PhaseBConfig(
        sessionBriefPrV2Enabled: true,
        briefPrDailyCapPerAgent: 2,
        freeChatValidMinUserMessages: 4,
      ));
      expect(r.v2, isTrue);
      expect(r.idleTimeout, const Duration(minutes: 30));
      expect(r.scheduleVersion, 2);
      expect(r.briefPrDailyCapPerAgent, 2);
      expect(r.freeChatValidMinUserMessages, 4);
      expect(r.catchUpExpiry, const Duration(hours: 2));
    });
  });

  group('SessionType', () {
    test('derives from the existing moduleId values', () {
      expect(SessionType.forModule('m2_check_in'), SessionType.checkIn);
      expect(SessionType.forModule('m3_reminiscence_w3'),
          SessionType.reminiscence);
      expect(SessionType.forModule('tung_tung_chat'), SessionType.freeChat);
      expect(SessionType.forModule('reflective_dialogue'),
          SessionType.freeChat);
      expect(SessionType.tryParse('check_in'), SessionType.checkIn);
      expect(SessionType.tryParse('bogus'), isNull);
    });
  });

  group('valid session — free chat (Tung Tung, reflective, both arms)', () {
    test('≥3 user messages each with a reply', () {
      expect(v2.isValid(chat(3)), isTrue);
      expect(v2.isValid(chat(2)), isFalse);
      expect(v2.isValid(chat(0)), isFalse);
    });

    test('messages without a reply (fallback / short-circuit) do not count',
        () {
      // 5 sent, only 2 answered.
      expect(v2.isValid(chat(2, sent: 5)), isFalse);
      expect(v2.isValid(chat(3, sent: 5)), isTrue);
    });

    test('a crisis end does not by itself make a chat invalid '
        '(the scheduler records due_not_invited)', () {
      expect(v2.isValid(chat(3, endReason: SessionEndReason.crisis)), isTrue);
    });
  });

  group('valid session — Hybrid check-in', () {
    SessionTally t({required bool mood, required int replies}) => SessionTally(
          sessionType: SessionType.checkIn,
          userMessageCount: replies,
          replyCount: replies,
          moodRecorded: mood,
        );

    test('mood recorded + ≥1 replied message', () {
      expect(v2.isValid(t(mood: true, replies: 1)), isTrue);
      expect(v2.isValid(t(mood: true, replies: 0)), isFalse);
      expect(v2.isValid(t(mood: false, replies: 3)), isFalse);
    });

    test('config: mood not required / more messages', () {
      const r = SessionRules(
          v2: true,
          idleTimeoutMin: 30,
          checkInValidRequiresMood: false,
          checkInValidMinUserMessages: 2);
      expect(r.isValid(t(mood: false, replies: 2)), isTrue);
      expect(r.isValid(t(mood: false, replies: 1)), isFalse);
    });
  });

  group('valid session — Hybrid reminiscence', () {
    SessionTally t({required bool saved, int replies = 0}) => SessionTally(
          sessionType: SessionType.reminiscence,
          userMessageCount: replies,
          replyCount: replies,
          summarySaved: saved,
        );

    test('valid only once the weekly summary is saved via 儲存', () {
      expect(v2.isValid(t(saved: true)), isTrue);
      expect(v2.isValid(t(saved: false, replies: 10)), isFalse);
    });

    test('config: save not required → free-chat rule applies', () {
      const r = SessionRules(
          v2: true, idleTimeoutMin: 30, reminiscenceValidRequiresSave: false);
      expect(r.isValid(t(saved: false, replies: 3)), isTrue);
      expect(r.isValid(t(saved: false, replies: 2)), isFalse);
    });
  });

  group('valid session — rule arm forms (decision 0015)', () {
    SessionTally t({required bool completed, String? endReason}) =>
        SessionTally(
          sessionType: SessionType.checkIn,
          userMessageCount: 1,
          replyCount: completed ? 1 : 0,
          isRuleSubmission: true,
          ruleSubmissionCompleted: completed,
          endReason: endReason,
        );

    test('one completed submission = one valid session', () {
      expect(v2.isValid(t(completed: true)), isTrue);
      expect(v2.isValid(t(completed: false)), isFalse);
    });

    test('an acute submission (crisis page, no response page) is not valid',
        () {
      expect(
          v2.isValid(t(completed: false, endReason: SessionEndReason.crisis)),
          isFalse);
    });

    test('same rule object serves both arms (no arm parameter exists)', () {
      // The rule arm's check-in and the Hybrid check-in are judged by the
      // same SessionRules instance; only the tally differs.
      expect(v2.isValid(t(completed: true)), isTrue);
      expect(
          v2.isValid(SessionTally(
              sessionType: SessionType.checkIn,
              userMessageCount: 1,
              replyCount: 1,
              moodRecorded: true)),
          isTrue);
    });
  });

  group('SessionTally round trip (app-start sweep)', () {
    test('fromMap reads what toMap wrote; missing fields read as not valid',
        () {
      const t = SessionTally(
          sessionType: SessionType.checkIn,
          userMessageCount: 2,
          replyCount: 2,
          moodRecorded: true);
      final back = SessionTally.fromMap(t.toMap(), endReason: 'recovered');
      expect(back.sessionType, SessionType.checkIn);
      expect(back.replyCount, 2);
      expect(back.moodRecorded, isTrue);
      expect(back.endReason, 'recovered');
      expect(v2.isValid(back), isTrue);

      final old = SessionTally.fromMap({'moduleId': 'tung_tung_chat'});
      expect(old.sessionType, SessionType.freeChat);
      expect(v2.isValid(old), isFalse);
    });
  });

  group('SessionEndReason', () {
    test('timeout and recovered go to the catch-up card', () {
      expect(SessionEndReason.isCatchUp(SessionEndReason.timeout), isTrue);
      expect(SessionEndReason.isCatchUp(SessionEndReason.recovered), isTrue);
      for (final r in [
        SessionEndReason.closeButton,
        SessionEndReason.back,
        SessionEndReason.switchAgent,
        SessionEndReason.submitted,
        SessionEndReason.crisis,
      ]) {
        expect(SessionEndReason.isCatchUp(r), isFalse, reason: r);
      }
    });
  });
}

// T25 (C14) — Brief PR v2 invitation rules: only after a valid session,
// daily cap per companion, crisis → due_not_invited, list-page vs catch-up
// channel, 2-hour expiry boundary, idempotent record, duplicate submission
// blocked, status model, S10b time phrase, switch off = legacy.
// Pure Dart with an in-memory store and a fake clock; both arms run this
// exact code.
import 'package:app_demo/core/session/session_rules.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_record.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_scheduler.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeClock {
  FakeClock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

SessionEndSummary ended({
  String sessionId = 's1',
  String agentId = 'tung_tung',
  String endReason = SessionEndReason.closeButton,
  int replies = 3,
  SessionType type = SessionType.freeChat,
  required DateTime at,
  bool? valid,
  bool moodRecorded = false,
  bool summarySaved = false,
  bool rule = false,
  bool ruleCompleted = false,
}) {
  final tally = SessionTally(
    sessionType: type,
    userMessageCount: replies,
    replyCount: replies,
    moodRecorded: moodRecorded,
    summarySaved: summarySaved,
    isRuleSubmission: rule,
    ruleSubmissionCompleted: ruleCompleted,
    endReason: endReason,
  );
  const rules = SessionRules(v2: true, idleTimeoutMin: 30);
  return SessionEndSummary(
    uid: 'u1',
    sessionId: sessionId,
    agentId: agentId,
    tally: tally,
    isValid: valid ?? rules.isValid(tally),
    endReason: endReason,
    startedAt: at.subtract(const Duration(minutes: 12)),
    endedAt: at,
    lastReplyAt: replies > 0 ? at.subtract(const Duration(seconds: 30)) : null,
  );
}

void main() {
  late FakeClock clock;
  late InMemoryBriefPrStore store;
  late BriefPrScheduler s;
  const rules = SessionRules(v2: true, idleTimeoutMin: 30);
  // A weekday afternoon: Wednesday 2026-10-14 15:20 local.
  final t0 = DateTime(2026, 10, 14, 15, 20);

  setUp(() {
    clock = FakeClock(t0);
    store = InMemoryBriefPrStore();
    s = BriefPrScheduler(
        store: store,
        rules: rules,
        clock: () => clock.now,
        processStartedAt: t0.subtract(const Duration(hours: 1)));
  });

  BriefPrRecord rec(String id) => store.records['u1/$id']!;

  group('switch off', () {
    test('legacy decision, no record, no card', () async {
      final legacy = BriefPrScheduler(
          store: store,
          rules: SessionRules.legacy(idleTimeoutMin: 10),
          clock: () => clock.now);
      expect(await legacy.onSessionEnded(ended(at: t0), agentDisplayName: '通通'),
          BriefPrDecision.legacy);
      expect(store.records, isEmpty);
      expect(await legacy.nextCard('u1'), isNull);
    });
  });

  group('invite only after a valid session', () {
    test('valid free chat → pending invitation keyed by session id', () async {
      final d = await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      expect(d, BriefPrDecision.invited);
      final r = rec('s1');
      expect(r.isPending, isTrue);
      expect(r.invitedAt, t0);
      expect(r.invitedDayKey, '2026-10-14');
      expect(r.inviteChannel, BriefPrInviteChannel.listPage);
      expect(r.everShown, isFalse);
      expect(r.agentDisplayName, '通通');
      expect(r.toMap()['schemaVersion'], 3);
      expect(r.toMap()['scheduleVersion'], 2);
      expect(store.sessionPatches['u1/s1'],
          containsPair('briefPrInvitedTodayAlready', false));
    });

    test('invalid session (2 replies) → nothing recorded', () async {
      expect(await s.onSessionEnded(ended(at: t0, replies: 2), agentDisplayName: '通通'),
          BriefPrDecision.notValid);
      expect(store.records, isEmpty);
      expect(store.sessionPatches, isEmpty);
    });

    test('same session reported twice → second call is a no-op', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      expect(await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通'),
          BriefPrDecision.alreadyRecorded);
      expect(store.records.length, 1);
    });

    test('rule arm submission and Hybrid check-in go through the same path',
        () async {
      final b = await s.onSessionEnded(
          ended(
              sessionId: 'b1',
              agentId: 'siu_yan',
              type: SessionType.checkIn,
              endReason: SessionEndReason.submitted,
              replies: 1,
              rule: true,
              ruleCompleted: true,
              at: t0),
          agentDisplayName: '小欣',
          arm: 'B');
      clock.advance(const Duration(days: 1)); // cap is per local day
      final a = await s.onSessionEnded(
          ended(
              sessionId: 'a1',
              agentId: 'siu_yan',
              type: SessionType.checkIn,
              replies: 1,
              moodRecorded: true,
              at: clock.now),
          agentDisplayName: '小欣',
          arm: 'A');
      expect(b, BriefPrDecision.invited);
      expect(a, BriefPrDecision.invited);
      expect(rec('b1').arm, 'B');
      expect(rec('a1').arm, 'A');
      expect(rec('b1').toMap().keys, rec('a1').toMap().keys);
    });
  });

  group('daily cap per companion', () {
    test('second valid session with the same companion on the same day: '
        'no record, session row marked', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      clock.advance(const Duration(hours: 3));
      final d = await s.onSessionEnded(ended(sessionId: 's2', at: clock.now),
          agentDisplayName: '通通');
      expect(d, BriefPrDecision.skippedByCap);
      expect(store.records.containsKey('u1/s2'), isFalse);
      expect(store.sessionPatches['u1/s2'], {
        'briefPrInvitedTodayAlready': true,
        'briefPrSkippedByCap': true,
      });
    });

    test('a different companion the same day is still invited', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      final d = await s.onSessionEnded(
          ended(sessionId: 's2', agentId: 'siu_yan', type: SessionType.checkIn,
              replies: 1, moodRecorded: true, at: t0),
          agentDisplayName: '小欣');
      expect(d, BriefPrDecision.invited);
    });

    test('the next local day resets the cap', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      clock.advance(const Duration(hours: 9)); // 00:20 next day
      final d = await s.onSessionEnded(ended(sessionId: 's2', at: clock.now),
          agentDisplayName: '通通');
      expect(d, BriefPrDecision.invited);
    });

    test('a skipped / expired invitation still counts towards the cap',
        () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      await s.skip(rec('s1'));
      final d = await s.onSessionEnded(ended(sessionId: 's2', at: clock.now),
          agentDisplayName: '通通');
      expect(d, BriefPrDecision.skippedByCap);
    });

    test('cap from config (2 per day; 0 = never)', () async {
      final two = BriefPrScheduler(
          store: store,
          rules: const SessionRules(
              v2: true, idleTimeoutMin: 30, briefPrDailyCapPerAgent: 2),
          clock: () => clock.now);
      expect(await two.onSessionEnded(ended(at: t0), agentDisplayName: '通通'),
          BriefPrDecision.invited);
      expect(await two.onSessionEnded(ended(sessionId: 's2', at: t0), agentDisplayName: '通通'),
          BriefPrDecision.invited);
      expect(await two.onSessionEnded(ended(sessionId: 's3', at: t0), agentDisplayName: '通通'),
          BriefPrDecision.skippedByCap);
      final zero = BriefPrScheduler(
          store: InMemoryBriefPrStore(),
          rules: const SessionRules(
              v2: true, idleTimeoutMin: 30, briefPrDailyCapPerAgent: 0),
          clock: () => clock.now);
      expect(await zero.onSessionEnded(ended(at: t0), agentDisplayName: '通通'),
          BriefPrDecision.skippedByCap);
    });
  });

  group('crisis', () {
    test('valid session ended by crisis → due_not_invited (reason crisis), '
        'no card, and it does not use up the cap', () async {
      final d = await s.onSessionEnded(
          ended(at: t0, endReason: SessionEndReason.crisis),
          agentDisplayName: '通通');
      expect(d, BriefPrDecision.dueNotInvited);
      final r = rec('s1');
      expect(r.finalStatus, BriefPrStatus.dueNotInvited);
      expect(r.dueNotInvitedReason, BriefPrDueNotInvitedReason.crisis);
      expect(r.invitedAt, isNull);
      expect(r.everShown, isFalse);
      expect(await s.nextCard('u1'), isNull);
      expect(await s.onSessionEnded(ended(sessionId: 's2', at: t0), agentDisplayName: '通通'),
          BriefPrDecision.invited);
    });

    test('crisis handling in progress blocks the invitation too', () async {
      final d = await s.onSessionEnded(ended(at: t0),
          agentDisplayName: '通通', crisisInProgress: true);
      expect(d, BriefPrDecision.dueNotInvited);
    });
  });

  group('channel: list page vs catch-up', () {
    for (final reason in [
      SessionEndReason.closeButton,
      SessionEndReason.back,
      SessionEndReason.switchAgent,
      SessionEndReason.submitted,
    ]) {
      test('$reason → S10a list-page card', () async {
        await s.onSessionEnded(ended(at: t0, endReason: reason), agentDisplayName: '通通');
        final card = await s.nextCard('u1');
        expect(card, isNotNull);
        expect(s.channelFor(card!), BriefPrInviteChannel.listPage);
      });
    }

    for (final reason in [SessionEndReason.timeout, SessionEndReason.recovered]) {
      test('$reason → S10b catch-up card', () async {
        await s.onSessionEnded(ended(at: t0, endReason: reason), agentDisplayName: '通通');
        final card = await s.nextCard('u1');
        expect(s.channelFor(card!), BriefPrInviteChannel.catchUp);
      });
    }

    test('a list-page invitation not seen before the App was killed is shown '
        'as catch-up on the next open', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      final nextProcess = BriefPrScheduler(
          store: store,
          rules: rules,
          clock: () => clock.now,
          processStartedAt: t0.add(const Duration(minutes: 30)));
      clock.advance(const Duration(minutes: 40));
      final card = await nextProcess.nextCard('u1');
      expect(nextProcess.channelFor(card!), BriefPrInviteChannel.catchUp);
      final shown = await nextProcess.markShown(card);
      expect(shown.inviteChannel, BriefPrInviteChannel.catchUp);
      expect(shown.everShown, isTrue);
      expect(shown.shownAt, clock.now);
    });
  });

  group('expiry: > 2 h after the last complete reply', () {
    // lastReplyAt = t0 - 30 s (see `ended`).
    test('1:59 after the last reply the card still shows', () async {
      await s.onSessionEnded(ended(at: t0, endReason: SessionEndReason.timeout),
          agentDisplayName: '通通');
      clock.now = t0.subtract(const Duration(seconds: 30)).add(const Duration(hours: 1, minutes: 59));
      expect(await s.nextCard('u1'), isNotNull);
      expect(rec('s1').isPending, isTrue);
    });

    test('2:01 after the last reply it is expired, everShown kept', () async {
      await s.onSessionEnded(ended(at: t0, endReason: SessionEndReason.timeout),
          agentDisplayName: '通通');
      clock.now = t0.subtract(const Duration(seconds: 30)).add(const Duration(hours: 2, minutes: 1));
      expect(await s.nextCard('u1'), isNull);
      final r = rec('s1');
      expect(r.finalStatus, BriefPrStatus.expired);
      expect(r.everShown, isFalse);
      expect(r.ratedAt, isNull);
    });

    test('shown but unanswered → expired with everShown true', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      final card = await s.nextCard('u1');
      await s.markShown(card!);
      clock.advance(const Duration(hours: 2, minutes: 1));
      expect(await s.nextCard('u1'), isNull);
      expect(rec('s1').finalStatus, BriefPrStatus.expired);
      expect(rec('s1').everShown, isTrue);
    });

    test('expiry hours from config', () async {
      final one = BriefPrScheduler(
          store: store,
          rules: const SessionRules(
              v2: true, idleTimeoutMin: 30, briefPrCatchUpExpiryHours: 1),
          clock: () => clock.now);
      await one.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      clock.advance(const Duration(hours: 1, minutes: 1));
      expect(await one.nextCard('u1'), isNull);
    });

    test('with several pending cards the newest session shows first', () async {
      await s.onSessionEnded(ended(at: t0, endReason: SessionEndReason.timeout),
          agentDisplayName: '通通');
      clock.advance(const Duration(minutes: 10));
      await s.onSessionEnded(
          ended(sessionId: 's2', agentId: 'siu_yan', type: SessionType.checkIn,
              replies: 1, moodRecorded: true, at: clock.now),
          agentDisplayName: '小欣');
      final card = await s.nextCard('u1');
      expect(card!.sessionId, 's2');
    });
  });

  group('answering', () {
    test('「今次唔評」 → skipped, ratedAt set, no scores', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      clock.advance(const Duration(minutes: 1));
      expect(await s.skip(rec('s1')), isTrue);
      final r = rec('s1');
      expect(r.finalStatus, BriefPrStatus.skipped);
      expect(r.ratedAt, clock.now);
      expect(r.items, isEmpty);
      expect(r.everShown, isTrue);
    });

    test('all four items → completed with RAW scores (no reversal)', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      expect(
          await s.submit(rec('s1'), {
            'understanding': 7,
            'validation': 6,
            'caring': 5,
            'insensitivity': 2,
          }),
          isTrue);
      final r = rec('s1');
      expect(r.finalStatus, BriefPrStatus.completed);
      expect(r.items['insensitivity'], 2); // raw; analysis applies 8 − x
      expect(r.toMap()['insensitivity'], 2);
      expect(r.toMap()['understanding'], 7);
    });

    test('some items then abandoned → partially_completed', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      await s.submit(rec('s1'), {'understanding': 4, 'validation': null});
      expect(rec('s1').finalStatus, BriefPrStatus.partiallyCompleted);
      expect(rec('s1').items, {'understanding': 4});
    });

    test('abandoned with no answer → skipped', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      await s.submit(rec('s1'), {});
      expect(rec('s1').finalStatus, BriefPrStatus.skipped);
    });

    test('duplicate submission (background / offline / crash retry) is '
        'blocked: one record, first answer wins', () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      final card = rec('s1');
      final all = {'understanding': 7, 'validation': 7, 'caring': 7, 'insensitivity': 1};
      expect(await s.submit(card, all), isTrue);
      final before = store.putCount;
      // Same stale card object submitted again (e.g. a retried tap).
      expect(await s.submit(card, {...all, 'understanding': 1}), isFalse);
      expect(await s.skip(card), isFalse);
      expect(store.putCount, before);
      expect(store.records.length, 1);
      expect(rec('s1').items['understanding'], 7);
    });

    test('a failed write does not lose the pending record (retry later)',
        () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通');
      store.failWrites = true;
      await expectLater(s.submit(rec('s1'), {'understanding': 5}), throwsStateError);
      store.failWrites = false;
      expect(rec('s1').isPending, isTrue);
      expect(await s.submit(rec('s1'), {'understanding': 5}), isTrue);
    });
  });

  group('record round trip', () {
    test('toMap / fromMap keep every field; old v2 popup records read as null',
        () async {
      await s.onSessionEnded(ended(at: t0), agentDisplayName: '通通', arm: 'A');
      final r = rec('s1');
      final m = r.toMap();
      // Firestore sentinel replaced for the pure round trip.
      m['updatedAt'] = null;
      final back = BriefPrRecord.fromMap(m)!;
      expect(back.sessionId, 's1');
      expect(back.invitedAt, r.invitedAt);
      expect(back.lastReplyAt, r.lastReplyAt);
      expect(back.inviteChannel, r.inviteChannel);
      expect(back.arm, 'A');
      expect(back.sessionType, 'free_chat');
      expect(back.endReason, SessionEndReason.closeButton);
      expect(BriefPrRecord.fromMap({'schemaVersion': 2, 'agentId': 'siu_yan'}), isNull);
    });
  });

  group('S10b time phrase (only the three approved forms)', () {
    final noon = DateTime(2026, 10, 14, 12, 0);
    test('same day before noon → 今朝', () {
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 14, 9, 30), noon), '今朝');
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 14, 11, 59), DateTime(2026, 10, 14, 13, 0)), '今朝');
    });
    test('previous day 18:00 or later → 尋晚', () {
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 13, 23, 30), DateTime(2026, 10, 14, 0, 40)), '尋晚');
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 13, 18, 0), DateTime(2026, 10, 14, 8, 0)), '尋晚');
    });
    test('12:00–17:59 → 星期X 下晝 with the session\'s weekday', () {
      // 2026-10-14 is a Wednesday.
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 14, 15, 20), DateTime(2026, 10, 14, 16, 0)), '星期三 下晝');
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 13, 14, 0), DateTime(2026, 10, 14, 9, 0)), '星期二 下晝');
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 18, 17, 59), DateTime(2026, 10, 18, 18, 30)), '星期日 下晝');
    });
    test('uncovered cases → 【占位】 (same-day evening, two days ago, '
        'previous-day morning)', () {
      const ph = BriefPrScheduler.timePhrasePlaceholder;
      expect(ph, startsWith('【占位】'));
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 14, 20, 0), DateTime(2026, 10, 14, 21, 0)), ph);
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 12, 15, 0), DateTime(2026, 10, 14, 9, 0)), ph);
      expect(BriefPrScheduler.timePhrase(DateTime(2026, 10, 13, 9, 0), DateTime(2026, 10, 14, 9, 0)), ph);
    });
  });
}

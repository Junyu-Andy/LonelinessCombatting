// T25 (C16) — ChatSessionRecorder under the v2 rules: end paths (close
// button, back, switch companion, idle 30 min, crisis), the tally that
// feeds the validity rule, app-switch within the timeout does not end the
// session, crash recovery classification, and switch off = old behaviour.
// No Firestore (available: false), fake timer / fake clock.
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/llm/turn_metadata.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/session/idle_session_timer.dart';
import 'package:app_demo/core/session/session_rules.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/brief_pr/data/rule_submission_flow.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const v2 = SessionRules(v2: true, idleTimeoutMin: 30);

/// A timer the test fires by hand.
class FakeIdleTimer extends IdleSessionTimer {
  FakeIdleTimer(Duration d, void Function() onIdle)
      : super(idleDuration: d, onIdle: onIdle);
  int bumps = 0;
  bool started = false;
  bool disposed = false;
  @override
  void start() => started = true;
  @override
  void bumpActivity() => bumps++;
  @override
  void dispose() => disposed = true;
  void fire() => onIdle();
}

LlmResponse resp({LlmStatus status = LlmStatus.ok, bool shortCircuited = false}) =>
    LlmResponse(
      text: status == LlmStatus.ok ? '聽到。' : '',
      inputFlag: const DistressMatch(DistressLevel.none),
      outputFlag: const DistressMatch(DistressLevel.none),
      shortCircuited: shortCircuited,
      metadata: const TurnMetadata(systemPromptHash: 'abc'),
      status: status,
      error: status == LlmStatus.fallback ? 'timeout' : null,
    );

TurnRecord turn(String moduleId, DateTime at,
        {LlmStatus status = LlmStatus.ok, bool shortCircuited = false}) =>
    TurnRecord(
      agentId: 'x',
      moduleId: moduleId,
      userSent: at,
      replyShown: at.add(const Duration(seconds: 2)),
      modality: InputModality.text,
      charCount: 3,
      detector: const DistressMatch(DistressLevel.none),
      shortCircuited: shortCircuited,
      ackShown: false,
      response: resp(status: status, shortCircuited: shortCircuited),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final analytics = AnalyticsService(firebaseReady: false);
  final t0 = DateTime(2026, 10, 14, 15, 0);
  late DateTime now;
  FakeIdleTimer? lastTimer;

  ChatSessionRecorder make({
    String agentId = 'tung_tung',
    String moduleId = 'tung_tung_chat',
    SessionRules rules = v2,
    void Function()? onIdleTimeout,
    void Function()? onSwitchedAway,
  }) =>
      ChatSessionRecorder(
        uid: 'u1',
        agentId: agentId,
        moduleId: moduleId,
        analytics: analytics,
        available: false, // no Firestore in tests
        rules: rules,
        clock: () => now,
        onIdleTimeout: onIdleTimeout,
        onSwitchedAway: onSwitchedAway,
        timerFactory: (d, fire) => lastTimer = FakeIdleTimer(d, fire),
      );

  setUp(() {
    now = t0;
    lastTimer = null;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  Future<void> chat(ChatSessionRecorder rec, int n,
      {LlmStatus status = LlmStatus.ok}) async {
    for (var i = 0; i < n; i++) {
      now = now.add(const Duration(minutes: 1));
      await rec.logTurn(turn(rec.moduleId, now, status: status));
    }
  }

  group('tally and validity', () {
    test('3 replied messages → valid free chat; counts and lastReplyAt', () async {
      final rec = make();
      await chat(rec, 3);
      expect(rec.userMessageCount, 3);
      expect(rec.replyCount, 3);
      expect(rec.lastReplyAt, now.add(const Duration(seconds: 2)));
      expect(rec.isValid, isTrue);
      expect(rec.sessionType, SessionType.freeChat);
    });

    test('fallback and crisis short-circuit turns count as sent, not replied',
        () async {
      final rec = make();
      await chat(rec, 2);
      await chat(rec, 2, status: LlmStatus.fallback);
      now = now.add(const Duration(minutes: 1));
      await rec.logTurn(turn(rec.moduleId, now,
          status: LlmStatus.shortCircuited, shortCircuited: true));
      expect(rec.userMessageCount, 5);
      expect(rec.replyCount, 2);
      expect(rec.isValid, isFalse);
      // The fallback counter the old M-7 rows had is untouched.
      expect(rec.fallbackCount, 2);
      expect(rec.userTurnCount, 3);
    });

    test('Hybrid check-in: mood mark + 1 reply; reminiscence: save mark',
        () async {
      final ci = make(agentId: 'siu_yan', moduleId: 'm2_check_in');
      await chat(ci, 1);
      expect(ci.sessionType, SessionType.checkIn);
      expect(ci.isValid, isFalse);
      ci.markMoodRecorded();
      expect(ci.isValid, isTrue);

      // 1014e §2.7: Hybrid reminiscence counts by replied messages (≥ 3),
      // like free chat; 儲存 is recorded but no longer required.
      final rem = make(agentId: 'ah_jan_ah_bak', moduleId: 'm3_reminiscence_w2');
      await chat(rem, 2);
      expect(rem.sessionType, SessionType.reminiscence);
      expect(rem.isValid, isFalse);
      rem.markSummarySaved();
      expect(rem.isValid, isFalse, reason: 'saving alone is not enough');
      await chat(rem, 1);
      expect(rem.isValid, isTrue);
    });

    test('endSummary carries what the scheduler needs', () async {
      final rec = make();
      await chat(rec, 3);
      expect(rec.endSummary, isNull); // still open
      now = now.add(const Duration(minutes: 2));
      await rec.end(SessionEndReason.closeButton);
      final s = rec.endSummary!;
      expect(s.uid, 'u1');
      expect(s.sessionId, rec.sessionId);
      expect(s.agentId, 'tung_tung');
      expect(s.endReason, SessionEndReason.closeButton);
      expect(s.isValid, isTrue);
      expect(s.endedAt, now);
      expect(s.startedAt, t0.add(const Duration(minutes: 1)));
      expect(s.lastReplyAt, rec.lastReplyAt);
      expect(s.tally.replyCount, 3);
    });
  });

  group('end paths', () {
    test('close button / back: first reason wins, idle timer disposed', () async {
      final rec = make();
      await chat(rec, 1);
      await rec.end(SessionEndReason.closeButton);
      await rec.end(SessionEndReason.back);
      expect(rec.endReason, SessionEndReason.closeButton);
      expect(rec.hasEnded, isTrue);
      expect(lastTimer!.disposed, isTrue);

      final rec2 = make();
      await chat(rec2, 1);
      await rec2.end(SessionEndReason.back);
      expect(rec2.endReason, SessionEndReason.back);
    });

    test('idle 30 min: timer created with the v2 timeout; firing closes the '
        'session as timeout and calls onIdleTimeout', () async {
      var idleCalls = 0;
      final rec = make(onIdleTimeout: () => idleCalls++);
      await chat(rec, 3);
      expect(lastTimer!.idleDuration, const Duration(minutes: 30));
      expect(lastTimer!.started, isTrue);
      expect(lastTimer!.bumps, 3); // every turn resets the idle clock
      lastTimer!.fire();
      expect(rec.endReason, SessionEndReason.timeout);
      expect(idleCalls, 1);
      // Typing again opens a fresh session.
      await chat(rec, 1);
      expect(rec.isOpen, isTrue);
      expect(rec.replyCount, 1);
    });

    test('switch companion: starting another companion ends the open one as '
        'switch_agent and tells its page', () async {
      var switched = 0;
      final tung = make(onSwitchedAway: () => switched++);
      await chat(tung, 3);
      final siu = make(agentId: 'siu_yan', moduleId: 'm2_check_in');
      await chat(siu, 1);
      expect(tung.hasEnded, isTrue);
      expect(tung.endReason, SessionEndReason.switchAgent);
      expect(switched, 1);
      expect(siu.isOpen, isTrue);
      // Same companion again (e.g. the page re-opened) does not count as a
      // switch for a different recorder of the same agent.
      final siu2 = make(agentId: 'siu_yan', moduleId: 'm2_check_in');
      await chat(siu2, 1);
      expect(siu.isOpen, isTrue);
    });

    test('crisis end keeps the reason and the tally', () async {
      final rec = make();
      await chat(rec, 3);
      await rec.end(SessionEndReason.crisis);
      expect(rec.endReason, SessionEndReason.crisis);
      expect(rec.endSummary!.isValid, isTrue); // scheduler → due_not_invited
    });
  });

  group('app switch / lock screen = pause only (IdleSessionTimer)', () {
    test('backgrounded 20 min then resumed: session is not ended, countdown '
        'restarts', () async {
      var fired = 0;
      var clock = const Duration(hours: 10);
      final timer = IdleSessionTimer(
        idleDuration: const Duration(minutes: 30),
        onIdle: () => fired++,
        now: () => clock,
      );
      timer.start();
      timer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(timer.hasArmedTimerForTest, isFalse); // paused, not running
      clock += const Duration(minutes: 20);
      timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(fired, 0);
      expect(timer.hasArmedTimerForTest, isTrue);
      timer.dispose();
    });

    test('backgrounded 31 min then resumed: counts as 30 min without a '
        'message → ends', () async {
      var fired = 0;
      var clock = const Duration(hours: 10);
      final timer = IdleSessionTimer(
        idleDuration: const Duration(minutes: 30),
        onIdle: () => fired++,
        now: () => clock,
      );
      timer.start();
      timer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      clock += const Duration(minutes: 31);
      timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(fired, 1);
      timer.dispose();
    });
  });

  group('crash recovery (app-start sweep)', () {
    Map<String, dynamic> row({
      int? scheduleVersion = 2,
      int replies = 3,
      String moduleId = 'tung_tung_chat',
      bool mood = false,
    }) =>
        {
          'sessionId': 's9',
          'agentId': 'tung_tung',
          'moduleId': moduleId,
          'sessionType': SessionType.forModule(moduleId).code,
          if (scheduleVersion != null) 'scheduleVersion': scheduleVersion,
          'startedAt': Timestamp.fromDate(t0),
          'lastActivityAt': Timestamp.fromDate(t0.add(const Duration(minutes: 5))),
          'lastReplyAt': Timestamp.fromDate(t0.add(const Duration(minutes: 5))),
          'userMessageCount': replies,
          'replyCount': replies,
          'moodRecorded': mood,
        };

    test('v2 row → recovered, isValid from the stored counts', () {
      final patch = ChatSessionRecorder.classifyRecovered(row(), v2, now: now);
      expect(patch['endReason'], SessionEndReason.recovered);
      expect(patch['isValid'], isTrue);
      expect((patch['endedAt'] as Timestamp).toDate(),
          t0.add(const Duration(minutes: 5)));
      expect(
          ChatSessionRecorder.classifyRecovered(row(replies: 2), v2, now: now)['isValid'],
          isFalse);
      expect(
          ChatSessionRecorder.classifyRecovered(
              row(moduleId: 'm2_check_in', replies: 1, mood: true), v2, now: now)['isValid'],
          isTrue);
    });

    test('recoveredSummary feeds the scheduler (catch-up card)', () {
      final s = ChatSessionRecorder.recoveredSummary('u1', 'doc', row(), v2, now: now)!;
      expect(s.endReason, SessionEndReason.recovered);
      expect(s.isValid, isTrue);
      expect(s.sessionId, 's9');
      expect(s.lastReplyAt, t0.add(const Duration(minutes: 5)));
      expect(s.endedAt, t0.add(const Duration(minutes: 5)));
    });

    test('pre-v2 row (no scheduleVersion) → app_killed, never a card', () {
      final patch = ChatSessionRecorder.classifyRecovered(
          row(scheduleVersion: null), v2, now: now);
      expect(patch['endReason'], SessionEndReason.appKilled);
      expect(patch.containsKey('isValid'), isFalse);
      expect(ChatSessionRecorder.recoveredSummary(
          'u1', 'doc', row(scheduleVersion: null), v2, now: now), isNull);
    });

    test('switch off → app_killed for every row (old behaviour)', () {
      final legacy = SessionRules.legacy(idleTimeoutMin: 10);
      expect(ChatSessionRecorder.classifyRecovered(row(), legacy, now: now)['endReason'],
          SessionEndReason.appKilled);
      expect(ChatSessionRecorder.recoveredSummary('u1', 'doc', row(), legacy, now: now),
          isNull);
    });
  });

  group('switch off = pre-T25 behaviour', () {
    test('10-minute idle timer, no switch_agent end, scheduleVersion 1', () async {
      final legacy = SessionRules.legacy(idleTimeoutMin: 10);
      final tung = make(rules: legacy);
      await chat(tung, 3);
      expect(lastTimer!.idleDuration, const Duration(minutes: 10));
      expect(tung.rules.scheduleVersion, 1);
      final siu = make(agentId: 'siu_yan', moduleId: 'm2_check_in', rules: legacy);
      await chat(siu, 1);
      expect(tung.isOpen, isTrue); // not ended by the other companion
      await tung.end(SessionEndReason.userLeft);
      expect(tung.endReason, SessionEndReason.userLeft);
    });
  });

  group('rule arm submission (decision 0015)', () {
    const detector = DistressDetector();
    Future<ChatSessionRecorder> submit(String text, SessionRules rules) =>
        RuleSubmissionFlow.record(
          uid: 'u1',
          agentId: 'siu_yan',
          moduleId: 'm2_check_in',
          analytics: analytics,
          available: false,
          text: text,
          detector: detector.analyze(text),
          userSent: now,
          replyText: '收到喇。',
          rules: rules,
        );

    test('v2: one submission = one valid session ended as submitted', () async {
      final rec = await submit('今日去咗飲茶', v2);
      expect(rec.endReason, SessionEndReason.submitted);
      expect(rec.isValid, isTrue);
      expect(rec.tally.isRuleSubmission, isTrue);
      expect(rec.endSummary!.isValid, isTrue);
    });

    test('v2: acute submission → crisis, not valid', () async {
      final rec = await submit('我想自殺', v2);
      expect(rec.endReason, SessionEndReason.crisis);
      expect(rec.isValid, isFalse);
    });

    test('switch off: user_left as before', () async {
      final rec = await submit('今日去咗飲茶', SessionRules.legacy(idleTimeoutMin: 10));
      expect(rec.endReason, SessionEndReason.userLeft);
    });
  });
}

// Decision 0015: check-in B and reminiscence B record one agent session per
// submission and qualify for Brief PR unless the session ended in crisis.
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_gate.dart';
import 'package:app_demo/features/brief_pr/data/rule_submission_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const detector = DistressDetector();

  Future<ChatSessionRecorder> submit(String text) =>
      RuleSubmissionFlow.record(
        uid: null,
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        analytics: AnalyticsService(firebaseReady: false),
        available: false,
        text: text,
        detector: detector.analyze(text),
        userSent: DateTime.now(),
      );

  test('a submission is one closed, rule-based agent session', () async {
    final rec = await submit('今日去咗飲茶');
    expect(rec.sessionId, isNotNull);
    expect(rec.hasEnded, isTrue);
    expect(rec.endReason, SessionEndReason.userLeft);
    expect(rec.userTurnCount, 1);
    expect(
        BriefPrGate.shouldSurfaceAfterSubmission(endReason: rec.endReason),
        isTrue);
  });

  test('an empty note still counts as a check-in session', () async {
    final rec = await submit('');
    expect(rec.userTurnCount, 1);
    expect(
        BriefPrGate.shouldSurfaceAfterSubmission(endReason: rec.endReason),
        isTrue);
  });

  test('an acute submission ends in crisis and gets no Brief PR', () async {
    final rec = await submit('我想自殺');
    expect(rec.endReason, SessionEndReason.crisis);
    expect(
        BriefPrGate.shouldSurfaceAfterSubmission(endReason: rec.endReason),
        isFalse);
  });

  test('rule-based turns are never fallback turns', () {
    expect(LlmStatus.ruleBased == LlmStatus.fallback, isFalse);
  });
}

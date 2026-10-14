/// Session logging + Brief PR for the rule-arm surfaces that are a single
/// submission rather than a chat: check-in B and reminiscence B.
///
/// Decision 0015: one completed submission is one agent session (written to
/// `sessions` / `turns` like every other chat surface) and qualifies for
/// Brief PR unless it ended in crisis.  The chat surfaces keep their own
/// ≥ briefPRMinTurns rule in [BriefPrGate.shouldSurfaceBriefPr].
library;

import 'package:flutter/material.dart';

import '../../../core/llm/llm_gateway.dart';
import '../../../core/safety/distress_detector.dart';
import '../../../core/session/chat_session_recorder.dart';
import '../../analytics/data/analytics_service.dart';
import '../presentation/pages/brief_pr_page.dart';
import 'brief_pr_gate.dart';
import 'brief_pr_v2.dart';

class RuleSubmissionFlow {
  RuleSubmissionFlow._();

  /// Record [text] as a one-turn rule-based session and close it
  /// (`crisis` when [detector] is acute, otherwise `user_left`).
  /// [safetyTurnId] is the id the safety check used (T26, decision 0033).
  static Future<ChatSessionRecorder> record({
    required String? uid,
    required String agentId,
    required String moduleId,
    String? theme,
    required AnalyticsService analytics,
    required bool available,
    required String text,
    required DistressMatch detector,
    required DateTime userSent,
    String replyText = '',
    InputModality modality = InputModality.text,
    int? voiceDurationMs,
    String? safetyTurnId,
    SessionRules? rules,
  }) async {
    final rec = ChatSessionRecorder(
      uid: uid,
      agentId: agentId,
      moduleId: moduleId,
      theme: theme,
      analytics: analytics,
      available: available,
      rules: rules,
    );
    await rec.ensureStarted();
    final acute = detector.level == DistressLevel.acute;
    // T25 (C16, decision 0015) — one submission is one session; it is valid
    // when the required fields were filled, submitted and the response
    // shown, i.e. whenever the safety check did not short-circuit it.
    rec.markRuleSubmission(completed: !acute);
    await rec.logTurn(TurnRecord(
      agentId: agentId,
      moduleId: moduleId,
      theme: theme,
      userSent: userSent,
      replyShown: DateTime.now(),
      modality: modality,
      voiceDurationMs: voiceDurationMs,
      charCount: text.length,
      detector: detector,
      shortCircuited: acute,
      ackShown: false,
      response: LlmResponse(
        text: acute ? '' : replyText,
        inputFlag: detector,
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: acute,
        metadata: TurnMetadata(agentId: agentId, sessionId: rec.sessionId),
        status: acute ? LlmStatus.shortCircuited : LlmStatus.ruleBased,
        turnId: safetyTurnId,
      ),
    ));
    await rec.end(acute
        ? SessionEndReason.crisis
        : rec.rules.v2
            ? SessionEndReason.submitted
            : SessionEndReason.userLeft);
    return rec;
  }

  /// Push Brief PR for the session [rec] recorded, if it qualifies.
  /// Uses a captured [nav] so it still works after the page has popped.
  static Future<void> surfaceBriefPr(
    NavigatorState nav, {
    required ChatSessionRecorder rec,
    required String uid,
    required String agentId,
    required String agentDisplayName,
  }) async {
    final sessionId = rec.sessionId;
    if (sessionId == null) return;
    // T25 v2 — same scheduler and card as the chat pages (both arms
    // identical); no popup.  Nothing here calls an LLM.
    if (await BriefPrV2.endSession(rec,
        endReason: rec.endReason ?? SessionEndReason.submitted, arm: 'B')) {
      return;
    }
    if (!BriefPrGate.shouldSurfaceAfterSubmission(endReason: rec.endReason)) {
      return;
    }
    final anchor =
        await BriefPrGate().isAnchorPromptFor(uid: uid, agentId: agentId);
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: agentId,
          agentDisplayName: agentDisplayName,
          isAnchorPrompt: anchor,
          sessionId: sessionId,
        ),
      ),
    );
  }
}

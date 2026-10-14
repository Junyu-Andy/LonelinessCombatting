/// T25 — App-side glue for session v2 + Brief PR v2.
///
/// One place the chat pages, the rule arm's submission flow, the app-start
/// sweep and the companion list card talk to.  Everything is a no-op while
/// `app_config/phase_b.sessionBriefPrV2Enabled` is off ([enabled] false):
/// the pages then run their pre-T25 popup path unchanged.
///
/// Both arms share this code; nothing here calls an LLM.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/agents/agent_registry.dart';
import '../../../core/session/chat_session_recorder.dart';
import 'brief_pr_record.dart';
import 'brief_pr_scheduler.dart';
import 'brief_pr_store.dart';

class BriefPrV2 {
  BriefPrV2._();

  /// Overridable for tests / the screenshot harness.
  static BriefPrStore store = FirestoreBriefPrStore();

  /// Fixed at first use so the whole process sees one start time.
  static final DateTime processStartedAt = DateTime.now();

  /// Bumped after every scheduler write so the list-page card refreshes.
  static final ChangeNotifier changes = _Notifier();

  /// Set by the App shell when the profile is known (阿珍 vs 阿伯).
  static AgentGenderVariant? ahJanAhBakVariant;

  static bool get enabled => SessionRules.current().v2;

  static BriefPrScheduler scheduler({SessionRules? rules}) => BriefPrScheduler(
        store: store,
        rules: rules ?? SessionRules.current(),
        processStartedAt: processStartedAt,
      );

  static String displayNameFor(String agentId) {
    if (agentId == AgentRegistry.ahJanAhBakId) {
      return AgentRegistry.ahJanAhBakName(ahJanAhBakVariant);
    }
    return AgentRegistry.byId(agentId).resolveVariant(null).displayNameZh;
  }

  /// End-of-session entry point for the chat pages.  Returns false when the
  /// switch is off (caller runs its legacy popup path); true when v2 took
  /// over: the session is closed with [endReason] (unless it already ended,
  /// e.g. by the idle clock or a crisis) and the scheduler decided about
  /// the invitation.  Never pushes a page: the card appears on the
  /// companion list page.
  static Future<bool> endSession(
    ChatSessionRecorder? rec, {
    required String endReason,
    String? arm,
    bool crisisInProgress = false,
  }) async {
    if (!enabled) return false;
    if (rec == null) return true;
    if (rec.isOpen) await rec.end(endReason);
    final summary = rec.endSummary;
    if (summary == null) return true; // never started / guest mode
    await _schedule(summary, arm: arm, crisisInProgress: crisisInProgress);
    return true;
  }

  /// App-start sweep hook: a session recovered from a process kill.
  static Future<void> onRecovered(SessionEndSummary summary) =>
      _schedule(summary);

  static Future<BriefPrDecision> _schedule(
    SessionEndSummary summary, {
    String? arm,
    bool crisisInProgress = false,
  }) async {
    try {
      final d = await scheduler().onSessionEnded(
        summary,
        agentDisplayName: displayNameFor(summary.agentId),
        arm: arm,
        crisisInProgress: crisisInProgress,
      );
      if (kDebugMode) debugPrint('[BriefPrV2] ${summary.sessionId}: $d');
      (changes as _Notifier).bump();
      return d;
    } catch (e) {
      if (kDebugMode) debugPrint('[BriefPrV2] schedule failed: $e');
      return BriefPrDecision.notValid;
    }
  }

  /// The card to show on the companion list page now, or null.
  static Future<BriefPrRecord?> nextCard(String uid) async {
    if (!enabled) return null;
    try {
      return await scheduler().nextCard(uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[BriefPrV2] nextCard failed: $e');
      return null;
    }
  }

  static void notifyChanged() => (changes as _Notifier).bump();
}

class _Notifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

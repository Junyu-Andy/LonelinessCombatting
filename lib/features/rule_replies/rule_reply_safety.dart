/// Decision 0023 — the one place the Arm B template replies talk to the
/// safety layer.  Since T7 (decision 0018) both helpers delegate to the
/// shared [SafetyService] (lib/core/safety/safety_check.dart), so Arm B
/// template replies use exactly the detection, `safety_events` write and
/// safety surface every other input uses.
///
/// Check-in B and reminiscence B call `SafetyService.checkUserText`
/// directly before saving (one event per submission) and only use
/// [allowsTemplateReply] from here; these wrappers stay for callers that
/// want the old names.
library;

import 'package:flutter/widgets.dart';

import '../../core/safety/distress_detector.dart';
import '../../core/safety/safety_check.dart';

/// Detect only — no write, no screen.  Used to decide whether a template
/// reply may be shown before anything is recorded.
DistressMatch ruleReplyDetect(BuildContext context, String text) =>
    SafetyService.of(context).detect(text);

/// Detect, write `safety_events` for moderate+ (PI is notified server-
/// side), then show the safety surface: acute → crisis page,
/// moderate_interrupt → support sheet.  [inputPoint] is the
/// [SafetyInputPoint] code (`check_in_note` / `reminiscence_note`);
/// [available] is kept for older callers and no longer used.
Future<DistressMatch> ruleReplyCheckAndRoute(
  BuildContext context,
  String text, {
  required String inputPoint,
  required bool available,
  String? uid,
  String? agentId,
  String? sessionId,
}) async {
  final point = SafetyInputPoint.values.firstWhere(
    (p) => p.code == inputPoint,
    orElse: () => SafetyInputPoint.checkInNote,
  );
  final result = await SafetyService.of(context).checkAndRoute(
    context,
    text,
    point: point,
    uid: uid,
    agentId: agentId,
    sessionId: sessionId,
  );
  return result.match;
}

/// T33 — which template, if any, a submission gets.
enum RuleReplyRoute {
  /// By the picked mood (or G-1 when none was picked).
  byMood,

  /// Reminiscence `moderate_review` (grief / past hardship): the Z5 group,
  /// whatever mood was picked.
  grief,

  /// No template: the safety flow runs on its own.
  none,
}

/// T33 (rule-templates.md rule 3–4).  [griefTemplates] is true on the
/// reminiscence page only: there a `moderate_review` hit gets a Z5
/// template.  `moderate_interrupt` and `acute` never get a template, on
/// either page; neither does `moderate_review` on the check-in page.
RuleReplyRoute ruleReplyRoute(
  DistressMatch match, {
  required bool griefTemplates,
}) {
  if (!match.isEscalation) return RuleReplyRoute.byMood;
  if (griefTemplates && match.level == DistressLevel.moderateReview) {
    return RuleReplyRoute.grief;
  }
  return RuleReplyRoute.none;
}

/// A template reply is shown only when the text raised no safety flag
/// that is written to `safety_events` (moderate review / interrupt,
/// acute).  On a hit the page gives no template and runs the safety flow.
/// `low` is not a safety event and keeps the reply.  Check-in rule; the
/// reminiscence page uses [ruleReplyRoute].
bool allowsTemplateReply(DistressMatch match) => !match.isEscalation;

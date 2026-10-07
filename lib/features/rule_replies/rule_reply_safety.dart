/// Decision 0023 — the one place the Arm B template replies talk to the
/// safety layer.  Shaped like T7's `SafetyService` (lib/core/safety/
/// safety_check.dart, PR #34) so that, once T7 is merged, each body below
/// becomes one call and the pages stay as they are:
///
///   ruleReplyDetect         → SafetyService.of(context).detect(text).match
///   ruleReplyCheckAndRoute  → SafetyService.of(context).checkAndRoute(
///                               context, text, point: …, uid: …,
///                               agentId: …, sessionId: …)
///
/// Until then they use the path check-in B / reminiscence B already use:
/// [DistressDetector] v5, [SafetyEventWriter] (`source: rule_turn`) and
/// [DistressRouter].
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/core_services_scope.dart';
import '../../core/safety/distress_detector.dart';
import '../../core/safety/safety_event_writer.dart';

/// Detect only — no write, no screen.  Used to decide whether a template
/// reply may be shown before anything is recorded.
DistressMatch ruleReplyDetect(BuildContext context, String text) =>
    CoreServicesScope.of(context).distress.analyze(text);

/// Detect, write `safety_events` for moderate+ (PI is notified server-
/// side), then show the safety surface: acute → crisis page,
/// moderate_interrupt → support sheet.  Same inputs as T7
/// `checkAndRoute`; [inputPoint] is the T7 `SafetyInputPoint` code
/// (`check_in_note` / `reminiscence_note`), kept for the swap.
Future<DistressMatch> ruleReplyCheckAndRoute(
  BuildContext context,
  String text, {
  required String inputPoint,
  required bool available,
  String? uid,
  String? agentId,
  String? sessionId,
}) async {
  final core = CoreServicesScope.of(context);
  final match = core.distress.analyze(text);
  if (match.isEscalation && uid != null) {
    unawaited(
      SafetyEventWriter(available: available).maybeWrite(
        uid: uid,
        source: SafetySource.ruleTurn,
        match: match,
        inputText: text,
        agentId: agentId,
        sessionId: sessionId,
      ),
    );
  }
  if (match.level != DistressLevel.none && context.mounted) {
    await core.distressRouter.route(match, context: context);
  }
  return match;
}

/// A template reply is shown only when the text raised no safety flag
/// that is written to `safety_events` (moderate review / interrupt,
/// acute).  On a hit the page gives no template and runs the safety flow.
/// `low` is not a safety event and keeps the reply.
bool allowsTemplateReply(DistressMatch match) => !match.isEscalation;

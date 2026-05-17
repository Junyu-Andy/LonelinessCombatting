/// Cross-referral handoff (Dev Req §5.4).
///
/// On user-accept, navigate to the target agent's surface. The target
/// agent reads `shared_context.pendingReferrals` on entry (via the
/// `ReferralWelcomeBanner` widget below) and surfaces an acknowledging
/// open line ("Siu Yan said you were thinking about…").
library;

import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';
import '../../features/context/presentation/pages/check_in_page.dart';
import '../../features/curious_companion/presentation/pages/tung_tung_page.dart';
import '../../features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import '../agent_context/shared_context_service.dart';
import '../agents/agent_registry.dart';
import 'triggers_config.dart';

class HandoffExecutor {
  HandoffExecutor({required this.sharedContext});

  final SharedContextService sharedContext;

  /// Navigate to [match.trigger.targetAgentId]. Returns once navigation
  /// is pushed; the target page is responsible for draining the
  /// pending-referral entry via [drainOnArrival].
  Future<void> handoff({
    required BuildContext context,
    required ReferralMatch match,
  }) async {
    final targetId = match.trigger.targetAgentId;
    Widget destination;
    switch (targetId) {
      case AgentRegistry.siuYanId:
        destination = const CheckInPage();
        break;
      case AgentRegistry.ahJanAhBakId:
        destination = const ReflectiveDialoguePage();
        break;
      case AgentRegistry.tungTungId:
        destination = const TungTungPage();
        break;
      default:
        return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  /// Called from the target agent's surface on first mount. Returns
  /// the first matching pending referral and clears all referrals
  /// targeted at [agentId]. Returns null when nothing is pending.
  Future<PendingReferral?> drainOnArrival({
    required BuildContext context,
    required String agentId,
  }) async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return null;
    final consumed = await sharedContext.drainReferralsTo(
      uid: profile.uid,
      agentId: agentId,
    );
    if (consumed.isEmpty) return null;
    return consumed.first;
  }
}

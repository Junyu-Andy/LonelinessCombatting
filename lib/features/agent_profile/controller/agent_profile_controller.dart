/// Pulls the right [ProfileHeaderData] / [ProfileIntroContent] /
/// destination route for a given (agent, profile) pair (Spec §1, §6).
///
/// Keeps the screen widget free of registry / variant juggling so the
/// UI layer can be replaced (e.g. with golden-test scaffolds) without
/// re-implementing the lookup.
library;

import 'package:flutter/material.dart';

import '../../../core/agents/agent_registry.dart';
import '../../auth/data/user_profile.dart';
import '../../context/presentation/pages/check_in_page.dart';
import '../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../reminiscence/presentation/pages/reminiscence_landing.dart';
import '../data/agent_profile_content.dart';

class AgentProfileResolution {
  final AgentDefinition agent;
  final AgentGenderVariant? variant;
  final ProfileHeaderData header;
  final ProfileIntroContent intro;

  const AgentProfileResolution({
    required this.agent,
    required this.variant,
    required this.header,
    required this.intro,
  });

  /// Resolves `{name}` tokens in the opening / closing for the
  /// gendered Ah Jan / Ah Bak content. Other agents pass through.
  String resolveOpening() =>
      intro.opening.replaceAll('{name}', header.displayName);

  String resolveClosing() =>
      intro.closing.replaceAll('{name}', header.displayName);

  Color get accent => _hexToColor(header.accentColorHex);
}

class AgentProfileController {
  const AgentProfileController();

  AgentProfileResolution? resolve({
    required String agentId,
    required UserProfile? userProfile,
  }) {
    final agent = AgentRegistry.tryById(agentId);
    if (agent == null) return null;
    final variant = agent.id == AgentRegistry.ahJanAhBakId
        ? (userProfile?.ahJanAhBakVariant ?? AgentGenderVariant.feminine)
        : null;
    final key = profileHeaderKey(agent, variant);
    if (key == null) return null;
    final header = profileHeaders[key];
    final intro = profileIntros[key];
    if (header == null || intro == null) return null;
    return AgentProfileResolution(
      agent: agent,
      variant: variant,
      header: header,
      intro: intro,
    );
  }

  /// Push the agent's conversation surface (Spec §6 CTA behaviour).
  /// First-intro is handled by [FirstIntroOverlay] on the destination
  /// surface, so we don't need to dispatch it here.
  Future<void> openConversation({
    required BuildContext context,
    required AgentDefinition agent,
  }) {
    Widget destination;
    switch (agent.id) {
      case AgentRegistry.siuYanId:
        destination = const CheckInPage();
        break;
      case AgentRegistry.ahJanAhBakId:
        destination = const ReminiscenceLandingPage();
        break;
      case AgentRegistry.tungTungId:
        destination = const TungTungPage();
        break;
      default:
        return Future.value();
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }
}

Color _hexToColor(String hex) {
  final clean = hex.replaceFirst('#', '').padLeft(6, '0');
  return Color(int.parse('FF$clean', radix: 16));
}

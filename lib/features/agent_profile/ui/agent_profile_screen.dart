/// Agent profile page (Spec §1–§9).
///
/// Reachable by tapping an agent's avatar from anywhere — see
/// `AgentAvatar.onTap`. The page is identical across Hybrid and
/// Rule-based arms (Spec §9).
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/agents/agent_registry.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_profile.dart';
import '../../auth/presentation/auth_service_scope.dart';
import '../controller/agent_profile_controller.dart';
import 'profile_action_button.dart';
import 'profile_header.dart';
import 'profile_intro_card.dart';

class AgentProfileScreen extends StatefulWidget {
  /// One of `AgentRegistry.siuYanId / ahJanAhBakId / tungTungId`.
  final String agentId;

  const AgentProfileScreen({super.key, required this.agentId});

  static Route<void> route(String agentId) => MaterialPageRoute<void>(
        builder: (_) => AgentProfileScreen(agentId: agentId),
      );

  @override
  State<AgentProfileScreen> createState() => _AgentProfileScreenState();
}

class _AgentProfileScreenState extends State<AgentProfileScreen> {
  static const _controller = AgentProfileController();

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    final resolution = _controller.resolve(
      agentId: widget.agentId,
      userProfile: profile,
    );
    if (resolution == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Unknown agent.')),
      );
    }
    final isAhJanAhBak =
        resolution.agent.id == AgentRegistry.ahJanAhBakId && profile != null;

    return Scaffold(
      appBar: AppBar(elevation: 0),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ProfileHeader(
              resolution: resolution,
              onChangeVariant:
                  isAhJanAhBak ? () => _changeVariant(profile, resolution) : null,
            ),
            ProfileIntroCard(resolution: resolution),
            const SizedBox(height: 24),
            ProfileActionButton(
              label: resolution.header.ctaLabel,
              accent: resolution.accent,
              onPressed: () =>
                  _controller.openConversation(
                context: context,
                agent: resolution.agent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Spec §11 recommendation: allow the user to switch Ah Jan / Ah Bak
  /// variant after onboarding. Persists to the profile so every other
  /// surface picks it up the next time it reads.
  Future<void> _changeVariant(
    UserProfile profile,
    AgentProfileResolution resolution,
  ) async {
    final next = resolution.variant == AgentGenderVariant.masculine
        ? AgentGenderVariant.feminine
        : AgentGenderVariant.masculine;
    final settings = AppSettingsScope.read(context);
    final auth = AuthServiceScope.of(context);
    final updated = profile.copyWith(ahJanAhBakVariant: next);
    settings.profile = updated;
    try {
      await auth.updateProfile(updated);
    } on AuthUnavailableException {
      // Guest mode — keep state in memory only.
    }
  }
}

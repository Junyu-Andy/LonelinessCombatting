import 'package:flutter/widgets.dart';

import '../../../app/app_settings_scope.dart';
import '../../onboarding/presentation/pages/agent_onboarding_page.dart';
import 'pages/consent_page.dart';

/// First-run sequencing under the AuthGate:
///   1. Functional-data consent (legacy)
///   2. Agent onboarding (Sprint 1 — three agent intros, Ah Jan/Ah Bak
///      variant selection, interests, per-agent transcript flags)
///   3. Main shell
///
/// Once both steps are recorded in the profile the gate is transparent.
/// Guest mode (no profile) sees neither — the demo shell renders directly.
class ConsentGate extends StatelessWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    if (profile == null) return child;
    if (!profile.consent.functionalData) {
      return const ConsentPage();
    }
    if (profile.ahJanAhBakVariant == null) {
      return const AgentOnboardingPage();
    }
    return child;
  }
}

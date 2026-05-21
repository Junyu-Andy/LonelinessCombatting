import 'package:flutter/widgets.dart';

import '../../../app/app_settings_scope.dart';
import '../../../features/auth/presentation/auth_service_scope.dart';
import '../../onboarding/presentation/pages/agent_onboarding_page.dart';
import '../../onboarding/presentation/pages/intake_flow_page.dart';
import 'pages/consent_page.dart';

/// First-run sequencing under the AuthGate:
///   1. Functional-data consent
///   2. Intake questionnaire (6-part onboarding intake)
///   3. Agent onboarding (Ah Jan/Ah Bak variant selection, interests)
///   4. Main shell
///
/// Once all steps are recorded in the profile the gate is transparent.
/// Guest mode (no profile) sees neither — the demo shell renders directly.
class ConsentGate extends StatelessWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final profile = settings.profile;
    if (profile == null) return child;
    if (!profile.consent.functionalData) {
      return const ConsentPage();
    }
    if (!profile.hasCompletedIntake) {
      return IntakeFlowPage(
        onComplete: () async {
          // Profile already updated inside IntakeFlowPage._complete();
          // rebuild will be triggered by settings.profile setter.
        },
      );
    }
    if (profile.ahJanAhBakVariant == null) {
      return const AgentOnboardingPage();
    }
    return child;
  }
}

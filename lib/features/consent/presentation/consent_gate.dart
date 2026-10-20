import 'package:flutter/widgets.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/feature_flags/remote_feature_flags.dart';
import '../../auth/data/user_profile.dart';
import '../../onboarding/presentation/pages/agent_onboarding_page.dart';
import '../../onboarding/presentation/pages/intake_people_page.dart';
import '../../onboarding/presentation/pages/intake_short_page.dart';
import '../../onboarding/presentation/researcher_intake_gate.dart';
import 'pages/consent_page.dart';

/// First-run sequencing under the AuthGate (after T21's EnrollmentWaitGate):
///   1. Functional-data consent
///   2. Intake questionnaire — T47: skipped when the researcher records it
///      (`researcherIntakeEnabled`); otherwise the short five-question page
///   3. Agent onboarding 「介紹三個夥伴」 (Ah Jan / Ah Bak pairing, interests,
///      S5 when that switch is on)
///   4. Main shell
///
/// 1020e §2.14: with `app_config/feature_flags.researcherIntakeGateEnabled`
/// on, step 2 sits behind [ResearcherIntakeGate] — a waiting page the
/// researcher unlocks with three taps in the centre.  Off (the default),
/// the gate is just the intake page.  The gate rebuilds this widget's
/// decision when its own re-read of the switches lands
/// ([RemoteFeatureFlags.reads]).
///
/// Once all steps are recorded in the profile the gate is transparent.
/// Guest mode (no profile) sees neither — the demo shell renders directly.
///
/// T37: step 3 used to run only while `ahJanAhBakVariant` was empty.  The
/// researcher's registration (functions/randomization.js) writes that
/// field too, so in the register-first order (enrolment gate on) the
/// slides were skipped.  With
/// `app_config/feature_flags.onboardingAfterEnrollmentFix` on, the
/// decision uses the onboarding-completed marker instead — see
/// [needsAgentOnboarding].  Off (the default), behaviour is exactly as
/// before.
class ConsentGate extends StatelessWidget {
  final Widget child;

  /// Test hook; defaults to [RemoteFeatureFlags.current].
  final bool? onboardingFixOn;

  /// T47 test hook; defaults to [RemoteFeatureFlags.current].  On, the
  /// researcher records the intake and the elder sees no questionnaire.
  final bool? researcherIntakeOn;

  /// 1020e §2.14 test hook; defaults to [RemoteFeatureFlags.lastKnown].
  final bool? researcherIntakeGateOn;

  /// 1020e §2.14 test hook; defaults to Firestore.
  final IntakeGateUnlockStore? intakeGateStore;

  const ConsentGate(
      {super.key,
      required this.child,
      this.onboardingFixOn,
      this.researcherIntakeOn,
      this.researcherIntakeGateOn,
      this.intakeGateStore});

  /// Registered by the researcher (T19 / T21): the server wrote the
  /// pairing together with the arm.  `cohort` exists since T21; the two
  /// assignment modes cover accounts registered before T21 (dev project).
  static bool registeredByResearcher(UserProfile p) =>
      p.isEnrolled ||
      p.armAssignmentMode == 'randomise' ||
      p.armAssignmentMode == 'pilot_designated';

  /// The App's own trace of a finished onboarding from before T37: the
  /// 「完成」 handler has always written the per-companion transcript-
  /// retention map (three keys) and the server never writes it.  (The
  /// Settings 「保留對話紀錄」 switch rewrites that map too, so a registered
  /// account that skipped the slides *and* used that switch counts as
  /// finished — rare, and only for accounts from before the fix.)
  static bool _finishedBeforeMarker(UserProfile p) =>
      p.consent.transcriptRetentionByAgent.isNotEmpty;

  /// Whether 「介紹三個夥伴」 still has to run for [profile].
  ///
  /// [fixOn] false: today's rule — run while no pairing is stored.
  /// [fixOn] true:
  ///   1. marker (`onboardingCompletedAt`) set ⇒ done;
  ///   2. no marker, no pairing ⇒ run (nothing has happened yet);
  ///   3. no marker, pairing, not registered ⇒ done — only the App's
  ///      onboarding could have written the pairing (before T37);
  ///   4. no marker, pairing, registered ⇒ done only when the App left
  ///      its own trace ([_finishedBeforeMarker], the onboarding-first
  ///      order before T37); otherwise the pairing came from the
  ///      registration and the slides never ran — the bug T37 fixes.
  static bool needsAgentOnboarding(UserProfile profile,
      {required bool fixOn}) {
    if (!fixOn) return profile.ahJanAhBakVariant == null;
    if (profile.onboardingCompletedAt != null) return false;
    if (profile.ahJanAhBakVariant == null) return true;
    if (!registeredByResearcher(profile)) return false;
    return !_finishedBeforeMarker(profile);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: RemoteFeatureFlags.reads,
        builder: (context, reads, child) => _decide(context),
      );

  /// 1020e §2.14: the intake page behind the researcher's gate.
  Widget _gated(UserProfile profile, Widget intakePage) =>
      ResearcherIntakeGate(
        profile: profile,
        gateOn: researcherIntakeGateOn,
        store: intakeGateStore,
        child: intakePage,
      );

  Widget _decide(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final profile = settings.profile;
    if (profile == null) return child;
    if (!profile.consent.functionalData) {
      return const ConsentPage();
    }
    // T47 rev. 10/16: with the researcher recording part A, the elder only
    // types part B — 重要嘅人 / 想重新聯絡嘅人 — once (intakePeopleDone).
    // Off: the short five-question page (which also covers the people).
    final researcherIntake = researcherIntakeOn ??
        RemoteFeatureFlags.current.researcherIntakeEnabled;
    if (researcherIntake && !profile.intakePeopleDone) {
      return _gated(
        profile,
        IntakePeoplePage(
          onComplete: () async {
            // Profile already updated inside the page; the rebuild is
            // triggered by the settings.profile setter.
          },
        ),
      );
    }
    if (!researcherIntake && !profile.hasCompletedIntake) {
      return _gated(
        profile,
        IntakeShortPage(
          onComplete: () async {
            // Profile already updated inside IntakeShortPage; the rebuild
            // is triggered by the settings.profile setter.
          },
        ),
      );
    }
    final fixOn = onboardingFixOn ??
        RemoteFeatureFlags.current.onboardingAfterEnrollmentFix;
    if (needsAgentOnboarding(profile, fixOn: fixOn)) {
      return AgentOnboardingPage(researcherIntakeOn: researcherIntake);
    }
    return child;
  }
}

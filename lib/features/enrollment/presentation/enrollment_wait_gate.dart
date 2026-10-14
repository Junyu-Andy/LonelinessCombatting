/// T21 (registry v8 C01; dev-tasks-1010 §3 T21 item 2) — the waiting page
/// before registration.
///
/// With `app_config/feature_flags.enrollmentGateEnabled` on, an account
/// that the researcher has not registered yet (no `cohort` on the profile)
/// and that is not a tester sees only the waiting page: the final copy S8
/// (`docs/spec/copy/short-texts.md`), word for word, and nothing else — no
/// consent, intake, home, chat or questionnaire, and no arm-specific
/// screen.  The server refuses the same account's LLM calls and research
/// data writes (functions/study_period.js, firestore.rules).
///
/// The profile is read when the App opens, so after registration the
/// participant closes and reopens the App (as for the arm since T19).
/// Off — the default — this widget is just [child].
library;

import 'package:flutter/material.dart';

import '../../../core/feature_flags/remote_feature_flags.dart';
import '../../auth/data/user_profile.dart';

/// S8, word for word (Cantonese only; there is no English final copy).
const String enrollmentWaitingS8 =
    '你好！研究人員會幫你完成登記，登記好之後就可以開始用。如果未登記或者有問題，可以搵研究人員幫手。';

class EnrollmentWaitGate extends StatelessWidget {
  final UserProfile? profile;
  final Widget child;

  /// Test hook; defaults to [RemoteFeatureFlags.current].
  final bool? gateOn;

  const EnrollmentWaitGate({
    super.key,
    required this.profile,
    required this.child,
    this.gateOn,
  });

  /// Wait when the gate is on and a signed-in account is neither
  /// registered nor a tester.
  static bool shouldWait({
    required bool gateOn,
    required UserProfile? profile,
  }) =>
      gateOn &&
      profile != null &&
      !profile.isEnrolled &&
      !profile.isTester;

  @override
  Widget build(BuildContext context) {
    final on = gateOn ?? RemoteFeatureFlags.current.enrollmentGateEnabled;
    if (!shouldWait(gateOn: on, profile: profile)) return child;
    return const EnrollmentWaitingPage();
  }
}

/// Only S8.  No buttons, no study-period or arm words, no phone number.
class EnrollmentWaitingPage extends StatelessWidget {
  const EnrollmentWaitingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              enrollmentWaitingS8,
              key: const Key('enrollment_waiting_s8'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }
}

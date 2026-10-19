/// 10/19 (dev-tasks-1020b §1) — the ONE place the App decides by cohort.
///
/// `users/{uid}.cohort` is written by the server at registration from the
/// research-ID prefix (functions/study_period.js):
///   - [runIn] `phase_b`  PB-01…04, the run-in (still followed up)
///   - [rct]   `rct`      RCT-…, the randomised analysis set (from 10/21)
///   - [pilot] `pilot`    PILOT-…, the pilot run
///
/// Every check reads [enrolled] or [phaseB]; the same lists are
/// ENROLLED_COHORTS / PHASE_B_COHORTS on the server and enrolledCohort() in
/// firestore.rules.  functions/test/cohort_list_guard_test.js fails on a
/// direct comparison with a cohort string anywhere else.
library;

class Cohorts {
  Cohorts._();

  static const String runIn = 'phase_b';
  static const String rct = 'rct';
  static const String pilot = 'pilot';

  /// Registered: consent and waiting pages, usage events, weekly schedule.
  static const Set<String> enrolled = {runIn, rct, pilot};

  /// Phase B follow-up (run-in and RCT).
  static const Set<String> phaseB = {runIn, rct};

  static bool isEnrolled(String? cohort) => enrolled.contains(cohort);
}

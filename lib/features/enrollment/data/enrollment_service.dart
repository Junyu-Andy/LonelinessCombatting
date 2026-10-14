/// T19 (decision 0029) — the unblinded researcher's registration entry.
///
/// Talks to the `enrollParticipant` Cloud Function
/// (functions/randomization.js).  The server checks the caller's role,
/// finds the participant account by its login email, takes the stratum's
/// next sequence position in a transaction and writes the arm.  The App
/// never reads or writes the sequence, the pointer or the allocation log.
library;

import 'package:cloud_functions/cloud_functions.dart';

/// The Auth custom claim that may use the registration page
/// (tool/provision_researcher.js).
const unblindedRole = 'unblinded';

bool isUnblindedClaims(Map<String, dynamic>? claims) =>
    claims?['role'] == unblindedRole;

/// T21 (registry v8 C01): the study period from the research-ID prefix,
/// the same rule as the server (functions/study_period.js): `PB-…` →
/// `'B'` (Phase B), `PILOT-…` → `'PILOT'` (pilot run).  Null for `PA-…`
/// (Phase A is paused, decision 0034), no prefix, or nothing after it.
/// The server checks again; this only picks the fields to show.
String? enrollmentPeriodOf(String researchId) {
  final id = researchId.trim().toUpperCase();
  final rest = RegExp(r'^[A-Z0-9][A-Z0-9-]*$');
  if (id.length > 12) return null;
  if (id.startsWith('PB-') && rest.hasMatch(id.substring(3))) return 'B';
  if (id.startsWith('PILOT-') && rest.hasMatch(id.substring(6))) {
    return 'PILOT';
  }
  return null;
}

/// What the researcher types in.  T21: a `PB-` ID needs the W0 score
/// and W0 date (Phase B, sequence allocation); a `PILOT-` ID needs the
/// version the researcher chose instead ([pilotArm], `'A'` Hybrid or
/// `'B'` rule-based) and starts on the registration date.
class EnrollmentInput {
  final String email;
  final String researchId;
  final int? w0DjgEmotional;
  final String companionVariant; // 'feminine' (阿珍) | 'masculine' (阿伯)
  final String? w0Date; // YYYY-MM-DD
  final String? pilotArm; // 'A' | 'B', PILOT- only

  const EnrollmentInput({
    required this.email,
    required this.researchId,
    this.w0DjgEmotional,
    required this.companionVariant,
    this.w0Date,
    this.pilotArm,
  });

  /// `'B'` | `'PILOT'` | null (see [enrollmentPeriodOf]).
  String? get studyPeriod => enrollmentPeriodOf(researchId);

  bool get isPilot => studyPeriod == 'PILOT';

  /// Low = 0–1, high = 2–3 (same rule as the server's stratumFor); empty
  /// for a pilot account (no score, no stratum).
  String get stratum => w0DjgEmotional == null
      ? ''
      : (w0DjgEmotional! <= 1 ? 'low' : 'high');

  Map<String, dynamic> toPayload({required bool dryRun}) => {
        'email': email.trim(),
        'researchId': researchId.trim().toUpperCase(),
        if (isPilot) 'pilotArm': pilotArm,
        if (!isPilot) 'w0DjgEmotional': w0DjgEmotional,
        'companionVariant': companionVariant,
        if (!isPilot) 'w0Date': w0Date,
        'dryRun': dryRun,
        'confirmed': !dryRun,
      };
}

/// What the server answered.  [arm] is null on a dry run.
class EnrollmentResult {
  final bool alreadyEnrolled;
  final bool sameInput;
  final String? arm;
  final String researchId;

  /// T21: `'B'` or `'PILOT'`.
  final String? studyPeriod;

  /// `'low'` | `'high'`; empty for a pilot account.
  final String stratum;
  final int? w0DjgEmotional;
  final String? companionVariant;
  final String? w0Date;
  final String? displayName;
  final String? accountCreatedAt;

  const EnrollmentResult({
    required this.alreadyEnrolled,
    required this.sameInput,
    required this.arm,
    required this.researchId,
    this.studyPeriod,
    required this.stratum,
    this.w0DjgEmotional,
    this.companionVariant,
    this.w0Date,
    this.displayName,
    this.accountCreatedAt,
  });

  factory EnrollmentResult.fromMap(Map<String, dynamic> m) {
    final account = m['account'] is Map
        ? Map<String, dynamic>.from(m['account'] as Map)
        : const <String, dynamic>{};
    return EnrollmentResult(
      alreadyEnrolled: m['alreadyEnrolled'] == true,
      sameInput: m['sameInput'] != false,
      arm: m['arm'] as String?,
      researchId: (m['researchId'] as String?) ?? '',
      studyPeriod: m['studyPeriod'] as String?,
      stratum: (m['stratum'] as String?) ?? '',
      w0DjgEmotional: (m['w0DjgEmotional'] as num?)?.toInt(),
      companionVariant: m['companionVariant'] as String?,
      w0Date: m['w0Date'] as String?,
      displayName: account['displayName'] as String?,
      accountCreatedAt: account['createdAt'] as String?,
    );
  }
}

/// A refusal from the server; [code] is the function's error message
/// (e.g. `research_id_taken`).
class EnrollmentError implements Exception {
  final String code;
  const EnrollmentError(this.code);
  @override
  String toString() => 'EnrollmentError($code)';
}

/// Injectable so the page can be tested without Firebase.
abstract class EnrollmentBackend {
  Future<EnrollmentResult> submit(EnrollmentInput input, {required bool dryRun});
}

class CloudEnrollmentBackend implements EnrollmentBackend {
  const CloudEnrollmentBackend();

  @override
  Future<EnrollmentResult> submit(EnrollmentInput input,
      {required bool dryRun}) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('enrollParticipant')
          .call<Map<String, dynamic>>(input.toPayload(dryRun: dryRun))
          .timeout(const Duration(seconds: 30));
      return EnrollmentResult.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      throw EnrollmentError(e.message ?? e.code);
    }
  }
}

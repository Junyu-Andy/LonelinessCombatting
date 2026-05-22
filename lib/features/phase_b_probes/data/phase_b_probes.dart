/// Phase B-specific probes (Phase B Proposal §4.5, §7.5, §7.6).
///
/// Three single-item / short-form probes that fire only during Phase B
/// at specific timepoints.  All three write to dedicated Firestore
/// subcollections so they don't pollute the main analytics events stream.
///
/// 1. **Unblinding probe** at W4 and W8
///    "Do you believe your version of the app uses an AI that generates
///    personalised responses, or pre-written responses?"
///    → `users/{uid}/unblinding_probes/{week}`
///    Used for the sensitivity check on whether blinding integrity
///    affected outcome.
///
/// 2. **Perceived dependency probe** at W8
///    Quantitative single-item plus structured open-ended.  Captures
///    whether the participant felt the agents displaced human contact.
///    → `users/{uid}/dependency_probes/exit`
///
/// 3. **Agent distinguishability probe** at W2 and W4
///    "If you wanted to talk about how you're feeling next time, how
///    likely is it that you'd choose [Siu Yan / Ah Jan-Ah Bak /
///    Tung Tung]?"  3-item Likert (1–7) per agent; entropy of the
///    triple is the distinguishability measure.  Conditions H6's
///    per-agent mediation decomposition.
///    → `users/{uid}/distinguishability_probes/{week}`
///
/// All three are feature-flagged off in Phase A (FeatureFlags.phaseB).
library;

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

enum UnblindingGuess {
  aiGenerates('ai_generates'),
  preWritten('pre_written'),
  unsure('unsure');

  const UnblindingGuess(this.code);
  final String code;
}

class UnblindingProbeResponse {
  final UnblindingGuess guess;
  final int confidence; // 1–7
  final DateTime answeredAt;
  final int weekNumber; // 4 or 8

  const UnblindingProbeResponse({
    required this.guess,
    required this.confidence,
    required this.answeredAt,
    required this.weekNumber,
  });

  Map<String, dynamic> toMap() => {
        'guess': guess.code,
        'confidence': confidence,
        'answeredAt': answeredAt.toIso8601String(),
        'weekNumber': weekNumber,
      };
}

class DependencyProbeResponse {
  /// "Did the app replace any of the human contact you would have
  /// otherwise had?" 1–7 Likert (1 = not at all, 7 = a great deal)
  final int displacementRating;

  /// Open-ended response to follow-up.  Free text; participant may
  /// leave blank.
  final String openResponse;

  final DateTime answeredAt;

  const DependencyProbeResponse({
    required this.displacementRating,
    required this.openResponse,
    required this.answeredAt,
  });

  Map<String, dynamic> toMap() => {
        'displacementRating': displacementRating,
        'openResponse': openResponse,
        'answeredAt': answeredAt.toIso8601String(),
      };
}

class DistinguishabilityProbeResponse {
  /// 1–7 Likert per agent.  Keys: 'siu_yan', 'ah_jan_ah_bak', 'tung_tung'.
  final Map<String, int> agentRatings;
  final DateTime answeredAt;
  final int weekNumber; // 2 or 4

  const DistinguishabilityProbeResponse({
    required this.agentRatings,
    required this.answeredAt,
    required this.weekNumber,
  });

  /// Shannon entropy of the normalised rating triple, used by H6's
  /// conditional decomposition: if entropy is at floor across the cohort,
  /// per-agent mediation analyses are reported as descriptive only.
  ///
  /// Entropy in bits, range [0, log2(3)] ≈ [0, 1.585].
  double get entropy {
    final values = agentRatings.values.map((v) => v.toDouble()).toList();
    final sum = values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return 0;
    double h = 0;
    for (final v in values) {
      if (v <= 0) continue;
      final p = v / sum;
      h -= p * (math.log(p) / math.ln2);
    }
    return h;
  }

  Map<String, dynamic> toMap() => {
        'agentRatings': agentRatings,
        'answeredAt': answeredAt.toIso8601String(),
        'weekNumber': weekNumber,
        'entropy': entropy,
      };
}

class PhaseBProbesRepository {
  PhaseBProbesRepository({required this.available});
  final bool available;

  Future<String?> submitUnblinding(
    String uid,
    UnblindingProbeResponse response,
  ) async {
    if (!available) return null;
    final ref = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('unblinding_probes')
        .doc('w${response.weekNumber}')
        .set(response.toMap()..['answeredAt'] = FieldValue.serverTimestamp(),
            SetOptions(merge: true));
    return 'w${response.weekNumber}';
  }

  Future<String?> submitDependency(
    String uid,
    DependencyProbeResponse response,
  ) async {
    if (!available) return null;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dependency_probes')
        .doc('exit')
        .set(response.toMap()..['answeredAt'] = FieldValue.serverTimestamp(),
            SetOptions(merge: true));
    return 'exit';
  }

  Future<String?> submitDistinguishability(
    String uid,
    DistinguishabilityProbeResponse response,
  ) async {
    if (!available) return null;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('distinguishability_probes')
        .doc('w${response.weekNumber}')
        .set(response.toMap()..['answeredAt'] = FieldValue.serverTimestamp(),
            SetOptions(merge: true));
    return 'w${response.weekNumber}';
  }
}

/// T24 — the weekly questionnaire bundle (SPEC:C15, C17): gate, part
/// status store, and the social-contact probe items (S12).
///
/// Phase B and the pilot; both arms see exactly the same flow; no arm
/// check anywhere in this feature.  Schedule arithmetic lives in
/// lib/core/scheduling/weekly_schedule.dart; the server mirror is
/// functions/weekly_schedule.js.
///
/// Records (one document per part, id = bundle id `W1`…`W7`):
///   users/{uid}/djg_responses/{W1|W2|W3}   T18 schema (6 items)
///   users/{uid}/weekly_pr/{Wn}             WeeklyPrResponse + `bundle`
///   users/{uid}/pgic/{Wn}                  PgicResponse + `bundle`
///   users/{uid}/social_contact_probes/{Wn} answers q1/q2 0–3 + `bundle`
/// The App writes answers, `bundle`, status and times.  The server stamps
/// studyWeek / studyDay / window / missed (firestore.rules refuses them
/// from a client).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/phase_b_config.dart';
import '../../../core/feature_flags/feature_flags.dart';
import '../../../core/scheduling/weekly_schedule.dart';
import '../../auth/data/user_profile.dart';

/// Is the study-week schedule on for this participant?  Switch on, Phase B
/// build, and a registered cohort (`phase_b` / `pilot`, T21).
class WeeklyBundleGate {
  WeeklyBundleGate._();

  static bool activeFor(PhaseBConfig cfg, UserProfile? profile,
          {required bool phaseB}) =>
      phaseB &&
      cfg.weeklyScheduleV2Enabled &&
      WeeklySchedule.modeForCohort(profile?.cohort) != null;

  static bool active(UserProfile? profile) =>
      activeFor(PhaseBConfig.current, profile, phaseB: FeatureFlags.phaseB);
}

/// Where one part stands: null = not started, `in_progress`, or a final
/// status (`submitted`, `completed`, `skipped`, `no_referent`, `missed`).
class WeeklyPartStatus {
  static const inProgress = 'in_progress';
  static const submitted = 'submitted';
  static const missed = 'missed';

  WeeklyPartStatus._();

  /// Nothing more to do for this part (same rule as the server's
  /// partSubmitted, plus `missed`).
  static bool isFinal(WeeklyPart part, Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['status'] == missed) return true;
    switch (part) {
      case WeeklyPart.djg:
      case WeeklyPart.socialContact:
        return data['status'] == submitted;
      case WeeklyPart.weeklyPr:
        return const ['completed', 'skipped', 'no_referent']
            .contains(data['status']);
      case WeeklyPart.pgic:
        return data['value'] is num;
    }
  }

  static String? label(WeeklyPart part, Map<String, dynamic>? data) {
    if (data == null) return null;
    if (isFinal(part, data)) return data['status'] as String? ?? submitted;
    return inProgress;
  }
}

/// A bundle that is open now, with where each part stands.
class WeeklyBundleDue {
  final WeeklyBundle bundle;
  final WeeklyWindow window;
  final Map<WeeklyPart, String?> status;

  const WeeklyBundleDue({
    required this.bundle,
    required this.window,
    required this.status,
  });

  bool get allDone => bundle.parts.every(
      (p) => status[p] != null && status[p] != WeeklyPartStatus.inProgress);

  WeeklyPart? get nextPart {
    for (final p in bundle.parts) {
      if (status[p] == null || status[p] == WeeklyPartStatus.inProgress) {
        return p;
      }
    }
    return null;
  }
}

/// Storage seam for the flow page (testable without Firebase).
abstract class WeeklyBundleStore {
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle);
}

/// 10/19 — tester preview: nothing started, nothing read or written.
class PreviewWeeklyBundleStore implements WeeklyBundleStore {
  const PreviewWeeklyBundleStore();

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async =>
      {for (final p in bundle.parts) p: null};
}

class FirestoreWeeklyBundleStore implements WeeklyBundleStore {
  FirestoreWeeklyBundleStore(this.uid, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async {
    final out = <WeeklyPart, String?>{};
    for (final p in bundle.parts) {
      try {
        final snap = await _db
            .collection('users')
            .doc(uid)
            .collection(p.collection)
            .doc(bundle.id)
            .get()
            .timeout(const Duration(seconds: 4));
        out[p] = WeeklyPartStatus.label(p, snap.data());
      } catch (_) {
        // Fail closed: a part we cannot read counts as done, so a read
        // error never re-asks a participant (same as PendingPromptsService).
        out[p] = WeeklyPartStatus.submitted;
      }
    }
    return out;
  }
}

/// S12 — weekly social-contact probe, copied verbatim from
/// docs/spec/copy/short-texts.md (do not reword).  Raw values 0–3.
class SocialContactItems {
  SocialContactItems._();

  static const version = 's12_v1';

  static const items = <({String id, String text})>[
    (id: 'q1', text: '過去 7 日，你有幾多日同屋企人、朋友或者鄰居見面傾偈？'),
    (id: 'q2', text: '過去 7 日，你有幾多日用電話、視像或者訊息同屋企人或者朋友聯絡？'),
  ];

  /// Stored value → label.
  static const options = <(int, String)>[
    (0, '冇'),
    (1, '1 至 2 日'),
    (2, '3 至 4 日'),
    (3, '5 日或以上'),
  ];

  static const footnote = '唔計同呢個 app 傾偈，亦唔計同研究人員聯絡。';
}

class SocialContactSaved {
  final String? status;
  final Map<String, int> answers;
  final bool hasStarted;

  const SocialContactSaved(
      {this.status, this.answers = const {}, this.hasStarted = false});

  bool get isClosed =>
      status == WeeklyPartStatus.submitted || status == WeeklyPartStatus.missed;

  static SocialContactSaved fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SocialContactSaved();
    final raw = data['answers'];
    final answers = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) answers[k] = v.toInt();
      });
    }
    return SocialContactSaved(
      status: data['status'] as String?,
      answers: answers,
      hasStarted: data['startedAt'] != null,
    );
  }
}

abstract class SocialContactStore {
  Future<SocialContactSaved> load();
  Future<void> save(Map<String, int> answers,
      {required bool submit, required bool first});
}

class FirestoreSocialContactStore implements SocialContactStore {
  FirestoreSocialContactStore(this.uid, this.bundleId, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final String bundleId;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _ref => _db
      .collection('users')
      .doc(uid)
      .collection(WeeklyPart.socialContact.collection)
      .doc(bundleId);

  @override
  Future<SocialContactSaved> load() async {
    try {
      final snap = await _ref.get().timeout(const Duration(seconds: 4));
      return SocialContactSaved.fromMap(snap.data());
    } catch (_) {
      return const SocialContactSaved();
    }
  }

  @override
  Future<void> save(Map<String, int> answers,
      {required bool submit, required bool first}) async {
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'bundle': bundleId,
      'itemsVersion': SocialContactItems.version,
      'answers': Map<String, int>.from(answers),
      'status': submit ? WeeklyPartStatus.submitted : WeeklyPartStatus.inProgress,
      'updatedAt': FieldValue.serverTimestamp(),
      if (first) 'startedAt': FieldValue.serverTimestamp(),
      if (first) 'startedAtLocal': now,
      if (submit) 'submittedAt': FieldValue.serverTimestamp(),
      if (submit) 'submittedAtLocal': now,
    };
    // Fire-and-forget (offline queue) — never block the participant.
    unawaited(() async {
      try {
        await _ref.set(data, SetOptions(merge: true));
      } catch (_) {}
    }());
  }
}

/// Preview / tests: starts empty, saves nothing.
class PreviewSocialContactStore implements SocialContactStore {
  @override
  Future<SocialContactSaved> load() async => const SocialContactSaved();

  @override
  Future<void> save(Map<String, int> answers,
      {required bool submit, required bool first}) async {}
}

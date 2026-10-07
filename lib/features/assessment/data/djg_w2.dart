/// T18 — Week 2 DJG in the App, all 6 items (SPEC:C15, decision 0027).
/// Phase B only; both arms see exactly the same page.
///
/// Items and the three answers are copied verbatim from the approved
/// questionnaire package §3 — do not reword.  Stored at
/// `users/{uid}/djg_responses/W2`: the App writes the raw answers
/// (q1–q6 → yes / mostly / no / skipped), the status and the start /
/// submit times.  Scores are computed by the server after submission
/// (functions/djg_w2.js) — the App never writes them (firestore.rules).
///
/// Replaces the Phase A `djg_es` Week 2 battery when [DjgW2Gate.active];
/// the old collection and page are kept untouched.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/phase_b_config.dart';
import '../../../core/feature_flags/feature_flags.dart';
import '../../../core/scheduling/enrolment_day.dart';

class DjgW2Item {
  final String id;

  /// `emotional` | `social` (social items are reverse-scored).
  final String subscale;
  final String text;

  const DjgW2Item({required this.id, required this.subscale, required this.text});
}

class DjgW2Items {
  DjgW2Items._();

  static const timepoint = 'W2';
  static const version = 'djg6_pkg3_v1';

  /// Questionnaire package §3, verbatim.
  static const items = <DjgW2Item>[
    DjgW2Item(id: 'q1', subscale: 'emotional', text: '我有一種空虛的感覺。'),
    DjgW2Item(id: 'q2', subscale: 'emotional', text: '我想念身邊有人陪伴。'),
    DjgW2Item(id: 'q3', subscale: 'emotional', text: '我經常覺得自己被人排斥。'),
    DjgW2Item(id: 'q4', subscale: 'social', text: '當我遇到問題時，有許多人可以倚靠。'),
    DjgW2Item(id: 'q5', subscale: 'social', text: '我有許多可以完全信任的人。'),
    DjgW2Item(id: 'q6', subscale: 'social', text: '有足夠多我感到親近的人。'),
  ];

  /// Stored value → label (questionnaire package §3, verbatim).
  static const options = <(String, String)>[
    ('yes', '是'),
    ('mostly', '大致是'),
    ('no', '不是'),
  ];

  static const skipped = 'skipped';
}

/// Is the in-app W2 DJG on?  Phase B build AND `app_config/phase_b`
/// switch.  T21 replaces the build test with the participant's phase.
class DjgW2Gate {
  DjgW2Gate._();

  static bool get active => activeFor(PhaseBConfig.current, phaseB: FeatureFlags.phaseB);

  static bool activeFor(PhaseBConfig cfg, {required bool phaseB}) =>
      phaseB && cfg.djgW2InAppEnabled;
}

/// W2 window arithmetic.  W0 date = day 1 (same as [enrolmentDay]).
class DjgW2Window {
  DjgW2Window._();

  static int day(DateTime w0, DateTime now) => enrolmentDay(w0, now);

  /// Open on days [djgW2DayOffset, djgW2DayOffset + djgW2WindowDays - 1].
  static bool isOpen(DateTime w0, DateTime now, PhaseBConfig cfg) {
    final d = day(w0, now);
    return d >= cfg.djgW2DayOffset &&
        d <= cfg.djgW2DayOffset + cfg.djgW2WindowDays - 1;
  }
}

/// What the page needs from a stored W2 doc.
class DjgW2Saved {
  final String? status;
  final Map<String, String> answers;
  final bool hasStarted;

  const DjgW2Saved({this.status, this.answers = const {}, this.hasStarted = false});

  /// `submitted` and `missed` are final.
  bool get isClosed => status == 'submitted' || status == 'missed';

  static DjgW2Saved fromMap(Map<String, dynamic>? data) {
    if (data == null) return const DjgW2Saved();
    final raw = data['answers'];
    final answers = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is String) answers[k] = v;
      });
    }
    return DjgW2Saved(
      status: data['status'] as String?,
      answers: answers,
      hasStarted: data['startedAt'] != null,
    );
  }
}

/// Storage seam so the page is testable without Firebase.
abstract class DjgW2Store {
  Future<DjgW2Saved> load();

  /// Save progress ([submit] false) or submit.  [first] adds the start time.
  Future<void> save(Map<String, String> answers, {required bool submit, required bool first});
}

class FirestoreDjgW2Store implements DjgW2Store {
  FirestoreDjgW2Store(this.uid, {FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('users').doc(uid).collection('djg_responses').doc(DjgW2Items.timepoint);

  @override
  Future<DjgW2Saved> load() async {
    try {
      final snap = await _ref.get().timeout(const Duration(seconds: 4));
      return DjgW2Saved.fromMap(snap.data());
    } catch (_) {
      return const DjgW2Saved();
    }
  }

  @override
  Future<void> save(Map<String, String> answers, {required bool submit, required bool first}) async {
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'timepoint': DjgW2Items.timepoint,
      'itemsVersion': DjgW2Items.version,
      'answers': Map<String, String>.from(answers),
      'status': submit ? 'submitted' : 'in_progress',
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

/// Tester-tools preview: starts empty, saves nothing.
class PreviewDjgW2Store implements DjgW2Store {
  @override
  Future<DjgW2Saved> load() async => const DjgW2Saved();

  @override
  Future<void> save(Map<String, String> answers, {required bool submit, required bool first}) async {}
}

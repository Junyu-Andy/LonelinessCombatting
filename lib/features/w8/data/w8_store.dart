/// T35 — where the W8 answers go (handover 1021-W8 四; decision 0036).
///
/// One document per part, id `W8`, the weekly questionnaire's layout:
///   users/{uid}/djg_responses/W8     DJG-ES (T18 schema, `answers` q1–q6)
///   users/{uid}/ucla3_responses/W8   UCLA-3 (`answers` q1–q3, 1–3)
///   users/{uid}/pgic/W8              PGIC (existing format: `value` 1–7)
///   users/{uid}/ci_responses/W8      CI1–CI3 (`answers`, 1–5)
///   users/{uid}/lsns6_responses/W8   LSNS-6 (`answers` q1–q6, 0–5)
///   users/{uid}/aimhs_responses/W8   AIMHS (`answers` q1–q5, 1–5), or
///                                    `status: declined` (not filled)
/// A skipped question is stored as `skipped`.  Every answer is saved the
/// moment it is given, with its own time (`answeredAt.{q}`; PGIC:
/// `answeredAt`), so leaving half-way loses nothing and the part reopens
/// at the first unanswered question.  The App writes `bundle`,
/// `itemsVersion`, answers, answer times, `status` (in_progress →
/// submitted, AIMHS also declined) and the start / submit times; the
/// server (functions/w8_questionnaire.js) writes studyWeek, studyDay,
/// outOfWindow, the window and the scores — firestore.rules refuses them
/// from the App.  Writes never block the elder (offline queue).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'w8_items.dart';

/// A part's status: null (nothing yet), or one of these.
class W8Status {
  W8Status._();

  static const inProgress = 'in_progress';
  static const submitted = 'submitted';
  static const declined = 'declined';
  static const missed = 'missed';

  /// Nothing more to do in this part.
  static bool isFinal(String? s) =>
      s == submitted || s == declined || s == missed;
}

/// The five parts are all done (AIMHS is optional and never counts:
/// handover 二 (3)).
bool w8PartsDone(Map<W8Part, String?> status) =>
    W8Items.parts.every((p) => W8Status.isFinal(status[p.part]));

/// The home card can go: the five parts done and AIMHS not left half-way
/// (a started AIMHS keeps the card so it can be finished or declined).
bool w8CardDone(Map<W8Part, String?> status) =>
    w8PartsDone(status) && status[W8Part.aimhs] != W8Status.inProgress;

/// What a part page needs back.
class W8Saved {
  final String? status;
  final Map<String, Object> answers;
  final bool hasStarted;

  const W8Saved({this.status, this.answers = const {}, this.hasStarted = false});

  bool get isClosed => W8Status.isFinal(status);
}

/// Storage seam (testable without Firebase).
abstract class W8Store {
  /// The status of every part (null = no record).
  Future<Map<W8Part, String?>> statuses();

  Future<W8Saved> load(W8Part part);

  /// One answer given (or skipped): every answer so far, the one that
  /// changed, still in progress.  [first] adds the start time.
  Future<void> saveAnswer(W8Part part, Map<String, Object> answers,
      String itemId, {required bool first});

  /// The part done.  [newlySkipped]: questions never reached, skipped now.
  Future<void> submit(W8Part part, Map<String, Object> answers,
      {required bool first, List<String> newlySkipped = const []});

  /// AIMHS 「唔填喇」.
  Future<void> decline(W8Part part, Map<String, Object> answers);
}

/// Tester preview and tests: kept in memory only, nothing goes anywhere.
class MemoryW8Store implements W8Store {
  MemoryW8Store([Map<W8Part, W8Saved>? initial])
      : _saved = {...?initial};

  final Map<W8Part, W8Saved> _saved;

  /// Every write, in order: (part, status, answers) — for tests.
  final writes = <(W8Part, String, Map<String, Object>)>[];

  @override
  Future<Map<W8Part, String?>> statuses() async =>
      {for (final p in W8Part.values) p: _saved[p]?.status};

  @override
  Future<W8Saved> load(W8Part part) async => _saved[part] ?? const W8Saved();

  void _put(W8Part part, String status, Map<String, Object> answers) {
    _saved[part] =
        W8Saved(status: status, answers: Map.of(answers), hasStarted: true);
    writes.add((part, status, Map.of(answers)));
  }

  @override
  Future<void> saveAnswer(W8Part part, Map<String, Object> answers,
          String itemId, {required bool first}) async =>
      _put(part, W8Status.inProgress, answers);

  @override
  Future<void> submit(W8Part part, Map<String, Object> answers,
          {required bool first, List<String> newlySkipped = const []}) async =>
      _put(part, W8Status.submitted, answers);

  @override
  Future<void> decline(W8Part part, Map<String, Object> answers) async =>
      _put(part, W8Status.declined, answers);
}

class FirestoreW8Store implements W8Store {
  FirestoreW8Store(this.uid, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(W8Part part) => _db
      .collection('users')
      .doc(uid)
      .collection(W8Items.specOf(part).collection)
      .doc(W8Items.bundleId);

  static String? _statusOf(Map<String, dynamic>? data) {
    if (data == null) return null;
    final s = data['status'];
    return s is String ? s : W8Status.inProgress;
  }

  @override
  Future<Map<W8Part, String?>> statuses() async {
    final out = <W8Part, String?>{};
    for (final p in W8Part.values) {
      try {
        final snap = await _ref(p).get().timeout(const Duration(seconds: 4));
        out[p] = _statusOf(snap.data());
      } catch (_) {
        // Fail closed, as the weekly questionnaire: a part we cannot read
        // counts as done, so a read error never asks twice.
        out[p] = W8Status.submitted;
      }
    }
    return out;
  }

  /// Stored record → the answers the page shows (PGIC keeps `value`).
  static Map<String, Object> answersOf(W8Part part, Map<String, dynamic>? d) {
    final out = <String, Object>{};
    if (d == null) return out;
    if (part == W8Part.pgic) {
      final v = d['value'];
      if (v is num) out['q1'] = v.toInt();
      if (v == W8Items.skipped) out['q1'] = W8Items.skipped;
      return out;
    }
    final raw = d['answers'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is! String) return;
        if (v is num) out[k] = v.toInt();
        if (v is String) out[k] = v;
      });
    }
    return out;
  }

  @override
  Future<W8Saved> load(W8Part part) async {
    try {
      final snap = await _ref(part).get().timeout(const Duration(seconds: 4));
      final d = snap.data();
      return W8Saved(
        status: _statusOf(d),
        answers: answersOf(part, d),
        hasStarted: d?['startedAt'] != null,
      );
    } catch (_) {
      return const W8Saved();
    }
  }

  /// The record for [answers] with these answer times and [status].
  /// Pure (tests): server times are [FieldValue.serverTimestamp].
  static Map<String, dynamic> payload(
    W8Part part,
    Map<String, Object> answers, {
    required String status,
    required List<String> timed,
    required bool first,
    DateTime? local,
  }) {
    final spec = W8Items.specOf(part);
    final now = (local ?? DateTime.now()).toIso8601String();
    final data = <String, dynamic>{
      'bundle': W8Items.bundleId,
      'itemsVersion': spec.itemsVersion,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (first) 'startedAt': FieldValue.serverTimestamp(),
      if (first) 'startedAtLocal': now,
      if (status == W8Status.submitted)
        'submittedAt': FieldValue.serverTimestamp(),
      if (status == W8Status.submitted) 'submittedAtLocal': now,
      if (status == W8Status.declined)
        'declinedAt': FieldValue.serverTimestamp(),
      if (status == W8Status.declined) 'declinedAtLocal': now,
    };
    if (part == W8Part.pgic) {
      // The existing PGIC format (W1–W7): `value` and `answeredAt`.
      final v = answers['q1'];
      if (v != null) data['value'] = v;
      if (timed.isNotEmpty) data['answeredAt'] = FieldValue.serverTimestamp();
      return data;
    }
    data['timepoint'] = W8Items.bundleId;
    data['answers'] = Map<String, Object>.from(answers);
    // Only the questions answered by this write; a merge keeps the others'
    // times.  (Never an empty map: a merge would write it over them.)
    if (timed.isNotEmpty) {
      data['answeredAt'] = <String, Object>{
        for (final id in timed) id: FieldValue.serverTimestamp(),
      };
    }
    return data;
  }

  void _write(W8Part part, Map<String, dynamic> data) {
    // Fire-and-forget (offline queue) — never block the elder.
    unawaited(() async {
      try {
        await _ref(part).set(data, SetOptions(merge: true));
      } catch (_) {}
    }());
  }

  @override
  Future<void> saveAnswer(W8Part part, Map<String, Object> answers,
      String itemId, {required bool first}) async {
    _write(
        part,
        payload(part, answers,
            status: W8Status.inProgress, timed: [itemId], first: first));
  }

  @override
  Future<void> submit(W8Part part, Map<String, Object> answers,
      {required bool first, List<String> newlySkipped = const []}) async {
    _write(
        part,
        payload(part, answers,
            status: W8Status.submitted, timed: newlySkipped, first: first));
  }

  @override
  Future<void> decline(W8Part part, Map<String, Object> answers) async {
    _write(
        part,
        payload(part, answers,
            status: W8Status.declined, timed: const [], first: false));
  }
}

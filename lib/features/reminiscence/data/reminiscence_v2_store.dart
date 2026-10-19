/// 1020d (回憶 v2) — storage for the weekly page, the chapter and the
/// chapter ratings.  The pages talk to the small interfaces here; the App
/// uses the Firestore classes, tests use the in-memory ones (set through
/// [ReminiscenceV2Stores]).
///
///   - week:     `users/{uid}/reminiscence_v2/week_{N}`
///   - chapter:  `users/{uid}/reminiscence_chapters/week_{N}`
///   - ratings:  `users/{uid}/reminiscence_chapter_ratings/{autoId}`
///
/// All three sit under the existing owner rule
/// `users/{uid}/{collection}/{document=**}` (firestore.rules); the server
/// agent narrows the chapter doc so the server-only fields stay
/// server-only.  The App never writes `finalText`, `rounds`, `flags`,
/// `generatedAt`, nor (Hybrid) `version`.
///
/// Transcript consent (`consent.transcriptRetentionFor('ah_jan_ah_bak')`,
/// the gate the M3 week doc uses for its `turns`): off → the week doc on
/// the server keeps the state but an empty `messages` list, and the words
/// stay in memory and in a device cache ([ReminiscenceDeviceCache],
/// shared_preferences) so the elder can still come back to the week.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm3_session_store.dart';
import 'reminiscence_v2_models.dart';

// -------------------------------------------------------------------------
// Week doc
// -------------------------------------------------------------------------

abstract class ReminiscenceWeekStore {
  /// The stored week, or null when never started.
  Future<ReminiscenceWeekState?> load(String uid, int weekIndex,
      {required String arm});

  /// Write the whole state.  [retainTranscript] false: `messages` go to the
  /// device cache only; the server doc gets `messages: []`.
  Future<void> save(String uid, ReminiscenceWeekState state,
      {required bool retainTranscript});
}

/// Where the words live when transcript consent is off.
abstract class ReminiscenceDeviceCache {
  Future<List<ReminiscenceMessage>?> read(String uid, int weekIndex);
  Future<void> write(
      String uid, int weekIndex, List<ReminiscenceMessage> messages);
  Future<void> clear(String uid, int weekIndex);
}

class PrefsReminiscenceDeviceCache implements ReminiscenceDeviceCache {
  static String key(String uid, int weekIndex) =>
      'reminiscence_v2.$uid.week_$weekIndex';

  @override
  Future<List<ReminiscenceMessage>?> read(String uid, int weekIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key(uid, weekIndex));
      if (raw == null) return null;
      final list = jsonDecode(raw) as List;
      return [
        for (final x in list)
          if (x is Map)
            ?ReminiscenceMessage.fromMap(Map<String, dynamic>.from(x)),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceDeviceCache] read: $e');
      return null;
    }
  }

  @override
  Future<void> write(
      String uid, int weekIndex, List<ReminiscenceMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key(uid, weekIndex),
          jsonEncode([for (final m in messages) m.toMap(isoTime: true)]));
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceDeviceCache] write: $e');
    }
  }

  @override
  Future<void> clear(String uid, int weekIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key(uid, weekIndex));
    } catch (_) {}
  }
}

class FirestoreReminiscenceWeekStore implements ReminiscenceWeekStore {
  FirestoreReminiscenceWeekStore({FirebaseFirestore? db, this.cache})
      : _db = db;

  final FirebaseFirestore? _db;
  final ReminiscenceDeviceCache? cache;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;
  ReminiscenceDeviceCache get _cache => cache ?? PrefsReminiscenceDeviceCache();

  DocumentReference<Map<String, dynamic>> _ref(String uid, int weekIndex) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('reminiscence_v2')
          .doc('week_$weekIndex');

  @override
  Future<ReminiscenceWeekState?> load(String uid, int weekIndex,
      {required String arm}) async {
    ReminiscenceWeekState? state;
    try {
      final snap = await _ref(uid, weekIndex)
          .get()
          .timeout(const Duration(seconds: 6));
      final data = snap.data();
      if (data != null) {
        state = ReminiscenceWeekState.fromMap(data,
            weekIndex: weekIndex, arm: arm);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceWeekStore] load: $e');
    }
    // Consent off (or the server copy has no words): the device copy.
    if (state == null || state.messages.isEmpty) {
      final local = await _cache.read(uid, weekIndex);
      if (local != null && local.isNotEmpty) {
        state ??= ReminiscenceWeekState(weekIndex: weekIndex, arm: arm);
        state.messages
          ..clear()
          ..addAll(local);
      }
    }
    return state;
  }

  @override
  Future<void> save(String uid, ReminiscenceWeekState state,
      {required bool retainTranscript}) async {
    final data = state.toMap(includeMessages: retainTranscript)
      ..['updatedAt'] = FieldValue.serverTimestamp();
    if (!state.exists) data['createdAt'] = FieldValue.serverTimestamp();
    state.exists = true;
    if (retainTranscript) {
      unawaited(_cache.clear(uid, state.weekIndex));
    } else {
      await _cache.write(uid, state.weekIndex, state.messages);
    }
    try {
      await _ref(uid, state.weekIndex).set(data, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceWeekStore] save: $e');
    }
  }
}

/// Tests, the screenshot harness and guest mode.  [serverDocs] is what
/// Firestore would hold (no words when consent is off), [deviceMessages]
/// what the device cache would hold.
class InMemoryReminiscenceWeekStore implements ReminiscenceWeekStore {
  final serverDocs = <String, Map<String, dynamic>>{};
  final deviceMessages = <String, List<ReminiscenceMessage>>{};
  int saves = 0;

  static String _k(String uid, int w) => '$uid/week_$w';

  @override
  Future<ReminiscenceWeekState?> load(String uid, int weekIndex,
      {required String arm}) async {
    final data = serverDocs[_k(uid, weekIndex)];
    ReminiscenceWeekState? state = data == null
        ? null
        : ReminiscenceWeekState.fromMap(data, weekIndex: weekIndex, arm: arm);
    final local = deviceMessages[_k(uid, weekIndex)];
    if ((state == null || state.messages.isEmpty) &&
        local != null &&
        local.isNotEmpty) {
      state ??= ReminiscenceWeekState(weekIndex: weekIndex, arm: arm);
      state.messages
        ..clear()
        ..addAll(local);
    }
    return state;
  }

  @override
  Future<void> save(String uid, ReminiscenceWeekState state,
      {required bool retainTranscript}) async {
    saves++;
    final k = _k(uid, state.weekIndex);
    final prev = serverDocs[k];
    final data = state.toMap(includeMessages: retainTranscript)
      ..['updatedAt'] = DateTime.now();
    data['createdAt'] = prev?['createdAt'] ?? DateTime.now();
    state.exists = true;
    serverDocs[k] = data;
    if (retainTranscript) {
      deviceMessages.remove(k);
    } else {
      deviceMessages[k] = List.of(state.messages);
    }
  }

  Map<String, dynamic>? doc(String uid, int weekIndex) =>
      serverDocs[_k(uid, weekIndex)];
}

// -------------------------------------------------------------------------
// Chapter doc (contract with the server agent)
// -------------------------------------------------------------------------

abstract class ReminiscenceChapterStore {
  Future<ReminiscenceChapterDoc?> get(String uid, int weekIndex);
  Stream<ReminiscenceChapterDoc?> watch(String uid, int weekIndex);

  /// Every chapter doc of this elder (any status), by week.
  Future<List<ReminiscenceChapterDoc>> list(String uid);

  /// Hybrid: 「完成今個禮拜」 / 「重新整理」.  Writes `weekIndex`, `source:
  /// 'hybrid'`, `status: 'requested'`, a new `requestId`, `requestedAt`
  /// (server time) and `input`; clears the elder's previous edit.
  Future<void> requestHybrid(String uid, int weekIndex,
      {required String requestId, required Map<String, dynamic> input});

  /// Rule arm: the finished chapter (`status: 'ready'`, `ruleText`,
  /// `version`), same request fields.
  Future<void> writeRule(String uid, int weekIndex,
      {required String requestId,
      required Map<String, dynamic> input,
      required String ruleText,
      required int version});

  /// 「儲存」: `editedText`, `editRatio`, `savedAt` (server time).
  Future<void> saveEdit(String uid, int weekIndex,
      {required String editedText, required double editRatio});

  static String newRequestId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

class FirestoreReminiscenceChapterStore implements ReminiscenceChapterStore {
  FirestoreReminiscenceChapterStore({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('reminiscence_chapters');

  @override
  Future<ReminiscenceChapterDoc?> get(String uid, int weekIndex) async {
    try {
      final snap = await _col(uid).doc('week_$weekIndex').get();
      final data = snap.data();
      return data == null
          ? null
          : ReminiscenceChapterDoc.fromMap(data, weekIndex: weekIndex);
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceChapterStore] get: $e');
      return null;
    }
  }

  @override
  Stream<ReminiscenceChapterDoc?> watch(String uid, int weekIndex) => _col(uid)
      .doc('week_$weekIndex')
      .snapshots()
      .map((s) {
        final data = s.data();
        return data == null
            ? null
            : ReminiscenceChapterDoc.fromMap(data, weekIndex: weekIndex);
      })
      .handleError((Object e) {
        if (kDebugMode) debugPrint('[ReminiscenceChapterStore] watch: $e');
      });

  @override
  Future<List<ReminiscenceChapterDoc>> list(String uid) async {
    try {
      final snap = await _col(uid).get();
      final out = <ReminiscenceChapterDoc>[];
      for (final d in snap.docs) {
        final w = int.tryParse(d.id.replaceFirst('week_', ''));
        if (w == null) continue;
        out.add(ReminiscenceChapterDoc.fromMap(d.data(), weekIndex: w));
      }
      out.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceChapterStore] list: $e');
      return const [];
    }
  }

  Future<void> _set(String uid, int weekIndex, Map<String, dynamic> data) async {
    try {
      await _col(uid)
          .doc('week_$weekIndex')
          .set(data, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceChapterStore] write: $e');
    }
  }

  Map<String, dynamic> _request(int weekIndex, String source, String status,
          String requestId, Map<String, dynamic> input) =>
      {
        'weekIndex': weekIndex,
        'source': source,
        'status': status,
        'requestId': requestId,
        'requestedAt': FieldValue.serverTimestamp(),
        'input': input,
        // A new chapter: the edit of the previous one no longer applies.
        'editedText': FieldValue.delete(),
        'editRatio': FieldValue.delete(),
        'savedAt': FieldValue.delete(),
      };

  @override
  Future<void> requestHybrid(String uid, int weekIndex,
          {required String requestId, required Map<String, dynamic> input}) =>
      _set(uid, weekIndex,
          _request(weekIndex, 'hybrid', 'requested', requestId, input));

  @override
  Future<void> writeRule(String uid, int weekIndex,
          {required String requestId,
          required Map<String, dynamic> input,
          required String ruleText,
          required int version}) =>
      _set(uid, weekIndex, {
        ..._request(weekIndex, 'rule', 'ready', requestId, input),
        'ruleText': ruleText,
        'version': version,
      });

  @override
  Future<void> saveEdit(String uid, int weekIndex,
          {required String editedText, required double editRatio}) =>
      _set(uid, weekIndex, {
        'editedText': editedText,
        'editRatio': editRatio,
        'savedAt': FieldValue.serverTimestamp(),
      });
}

/// Tests / guest mode.  [writes] keeps every client write in order, with
/// `'<serverTimestamp>'` / `'<delete>'` for the sentinels, so a test can
/// check exactly which fields the App sets.  [serverWrite] plays the
/// server's part (Hybrid generation).
class InMemoryReminiscenceChapterStore implements ReminiscenceChapterStore {
  final docs = <String, Map<String, dynamic>>{};
  final writes = <({String uid, int weekIndex, Map<String, dynamic> data})>[];
  final _controllers = <String, StreamController<ReminiscenceChapterDoc?>>{};

  static const serverTimestamp = '<serverTimestamp>';
  static const deleted = '<delete>';

  static String _k(String uid, int w) => '$uid/week_$w';

  ReminiscenceChapterDoc? _doc(String uid, int w) {
    final d = docs[_k(uid, w)];
    return d == null ? null : ReminiscenceChapterDoc.fromMap(d, weekIndex: w);
  }

  void _apply(String uid, int w, Map<String, dynamic> data) {
    final cur = docs.putIfAbsent(_k(uid, w), () => <String, dynamic>{});
    data.forEach((k, v) {
      if (v == deleted) {
        cur.remove(k);
      } else if (v == serverTimestamp) {
        cur[k] = DateTime.now();
      } else {
        cur[k] = v;
      }
    });
    _controllers[_k(uid, w)]?.add(_doc(uid, w));
  }

  void _clientWrite(String uid, int w, Map<String, dynamic> data) {
    writes.add((uid: uid, weekIndex: w, data: Map.of(data)));
    _apply(uid, w, data);
  }

  /// The server's writes (status generating / ready / failed, finalText,
  /// version, …).
  void serverWrite(String uid, int weekIndex, Map<String, dynamic> data) =>
      _apply(uid, weekIndex, data);

  @override
  Future<ReminiscenceChapterDoc?> get(String uid, int weekIndex) async =>
      _doc(uid, weekIndex);

  @override
  Stream<ReminiscenceChapterDoc?> watch(String uid, int weekIndex) {
    final c = _controllers.putIfAbsent(_k(uid, weekIndex),
        () => StreamController<ReminiscenceChapterDoc?>.broadcast());
    final current = _doc(uid, weekIndex);
    return Stream<ReminiscenceChapterDoc?>.multi((sink) {
      sink.add(current);
      final sub = c.stream.listen(sink.add);
      sink.onCancel = sub.cancel;
    });
  }

  @override
  Future<List<ReminiscenceChapterDoc>> list(String uid) async {
    final out = <ReminiscenceChapterDoc>[];
    for (final e in docs.entries) {
      if (!e.key.startsWith('$uid/')) continue;
      final w = int.parse(e.key.split('week_').last);
      out.add(ReminiscenceChapterDoc.fromMap(e.value, weekIndex: w));
    }
    out.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    return out;
  }

  Map<String, dynamic> _request(int w, String source, String status,
          String requestId, Map<String, dynamic> input) =>
      {
        'weekIndex': w,
        'source': source,
        'status': status,
        'requestId': requestId,
        'requestedAt': serverTimestamp,
        'input': input,
        'editedText': deleted,
        'editRatio': deleted,
        'savedAt': deleted,
      };

  @override
  Future<void> requestHybrid(String uid, int weekIndex,
      {required String requestId, required Map<String, dynamic> input}) async {
    _clientWrite(uid, weekIndex,
        _request(weekIndex, 'hybrid', 'requested', requestId, input));
  }

  @override
  Future<void> writeRule(String uid, int weekIndex,
      {required String requestId,
      required Map<String, dynamic> input,
      required String ruleText,
      required int version}) async {
    _clientWrite(uid, weekIndex, {
      ..._request(weekIndex, 'rule', 'ready', requestId, input),
      'ruleText': ruleText,
      'version': version,
    });
  }

  @override
  Future<void> saveEdit(String uid, int weekIndex,
      {required String editedText, required double editRatio}) async {
    _clientWrite(uid, weekIndex, {
      'editedText': editedText,
      'editRatio': editRatio,
      'savedAt': serverTimestamp,
    });
  }
}

// -------------------------------------------------------------------------
// Ratings
// -------------------------------------------------------------------------

abstract class ReminiscenceRatingStore {
  /// One new `reminiscence_chapter_ratings` doc (`ratedAt` = server time).
  Future<void> add(String uid, Map<String, dynamic> data);
}

class FirestoreReminiscenceRatingStore implements ReminiscenceRatingStore {
  FirestoreReminiscenceRatingStore({FirebaseFirestore? db}) : _db = db;
  final FirebaseFirestore? _db;

  @override
  Future<void> add(String uid, Map<String, dynamic> data) async {
    try {
      await (_db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('reminiscence_chapter_ratings')
          .add({...data, 'ratedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceRatingStore] add: $e');
    }
  }
}

class InMemoryReminiscenceRatingStore implements ReminiscenceRatingStore {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<void> add(String uid, Map<String, dynamic> data) async {
    rows.add({...data, 'uid': uid, 'ratedAt': '<serverTimestamp>'});
  }
}

// -------------------------------------------------------------------------
// The 80-character summary (unchanged home: the M3 week doc)
// -------------------------------------------------------------------------

/// The weekly summary next week's context and memory read
/// (`memory/m3_reminiscence/sessions/week_{N}.end_summary_original`), as
/// the old pages wrote it: Hybrid = the LLM's ≤ 80-character summary,
/// rule arm = the elder's own words.
abstract class ReminiscenceSummaryWriter {
  Future<void> save({
    required String uid,
    required int weekIndex,
    required String armCode,
    required String summary,
  });
}

class M3ReminiscenceSummaryWriter implements ReminiscenceSummaryWriter {
  M3ReminiscenceSummaryWriter({required this.available});
  final bool available;

  @override
  Future<void> save({
    required String uid,
    required int weekIndex,
    required String armCode,
    required String summary,
  }) async {
    final store = M3SessionStore(available: available);
    try {
      await store.startSession(uid: uid, weekIndex: weekIndex, armCode: armCode);
      await store.finalizeSession(
        uid: uid,
        weekIndex: weekIndex,
        armCode: armCode,
        endSummaryOriginal: summary,
        endSummaryEdited: null,
        userEdited: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ReminiscenceSummaryWriter] $e');
    }
  }
}

class InMemoryReminiscenceSummaryWriter implements ReminiscenceSummaryWriter {
  final saved = <({int weekIndex, String armCode, String summary})>[];

  @override
  Future<void> save({
    required String uid,
    required int weekIndex,
    required String armCode,
    required String summary,
  }) async {
    saved.add((weekIndex: weekIndex, armCode: armCode, summary: summary));
  }
}

// -------------------------------------------------------------------------
// Which store the pages use
// -------------------------------------------------------------------------

class ReminiscenceV2Stores {
  ReminiscenceV2Stores._();

  /// Tests / screenshot harness.
  static ReminiscenceWeekStore? weekOverride;
  static ReminiscenceChapterStore? chaptersOverride;
  static ReminiscenceRatingStore? ratingsOverride;
  static ReminiscenceSummaryWriter? summaryOverride;

  // Guest mode (no Firebase): kept for the life of the process.
  static final _guestWeek = InMemoryReminiscenceWeekStore();
  static final _guestChapters = InMemoryReminiscenceChapterStore();
  static final _guestRatings = InMemoryReminiscenceRatingStore();

  static ReminiscenceWeekStore week({required bool available}) =>
      weekOverride ??
      (available ? FirestoreReminiscenceWeekStore() : _guestWeek);

  static ReminiscenceChapterStore chapters({required bool available}) =>
      chaptersOverride ??
      (available ? FirestoreReminiscenceChapterStore() : _guestChapters);

  static ReminiscenceRatingStore ratings({required bool available}) =>
      ratingsOverride ??
      (available ? FirestoreReminiscenceRatingStore() : _guestRatings);

  static ReminiscenceSummaryWriter summary({required bool available}) =>
      summaryOverride ?? M3ReminiscenceSummaryWriter(available: available);

  @visibleForTesting
  static void resetForTest() {
    weekOverride = null;
    chaptersOverride = null;
    ratingsOverride = null;
    summaryOverride = null;
  }
}

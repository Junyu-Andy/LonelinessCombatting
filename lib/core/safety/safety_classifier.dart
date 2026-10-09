/// T8 — the pluggable safety-classifier slot behind [SafetyService]
/// (SPEC C13, decision 0025; both arms confirmed by decision 0033 — switch
/// still off by default, no model yet).
///
/// The lexicon ([DistressDetector]) always runs first and always counts.
/// When `PhaseAConfig.safetyClassifierEnabled` is on, [SafetyService]
/// also asks a [SafetyClassifier] about the participant's text, in both
/// arms, and keeps the higher of the two levels (the classifier can only
/// raise a level, never lower one).
///
/// A classifier returns a risk level and a score — never any text — and
/// never changes the conversation.  It is not a chat model: the call goes
/// to its own Cloud Function (`classifySafety`), not through
/// `proxyDeepSeek`, and does not touch the server's `assertLlmAllowed`
/// guard.
///
/// Timeout (default 1.5 s) or failure → the lexicon result alone, and one
/// `safety_classifier_calls` row (written by the App only for the cases
/// the server cannot see: the call never came back).  The server writes
/// a row for every call it relays.  No row ever holds the text.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'distress_detector.dart';

/// How a classifier call ended.  Codes are stored in
/// `safety_classifier_calls.status` and `safety_events.classifierStatus`.
enum ClassifierStatus {
  /// The model answered with a valid level.
  ok('ok'),

  /// The server switch is off, or no model address is set.
  disabled('disabled'),

  /// The server gave up waiting for the model.
  timeout('timeout'),

  /// The model answered with an error or with something that is not a
  /// valid level.
  error('error'),

  /// The App gave up waiting (offline, slow network, cold start).
  clientTimeout('client_timeout'),

  /// The call failed before an answer came back (offline, auth, …).
  clientError('client_error');

  const ClassifierStatus(this.code);
  final String code;

  static ClassifierStatus parse(Object? raw) {
    for (final s in ClassifierStatus.values) {
      if (s.code == raw) return s;
    }
    return ClassifierStatus.error;
  }
}

/// What a classifier says about one text.  No text, by design.
class ClassifierVerdict {
  const ClassifierVerdict({
    required this.status,
    this.level,
    this.score,
    this.modelVersion,
    this.latencyMs,
  });

  final ClassifierStatus status;

  /// Null unless [status] is [ClassifierStatus.ok].
  final DistressLevel? level;

  /// Model score, 0–1, when the model gives one.
  final double? score;
  final String? modelVersion;
  final int? latencyMs;

  bool get ok => status == ClassifierStatus.ok && level != null;

  /// Parses the `classifySafety` response.  Anything unexpected → error.
  factory ClassifierVerdict.fromResponse(Object? data, {int? latencyMs}) {
    if (data is! Map) {
      return ClassifierVerdict(
          status: ClassifierStatus.error, latencyMs: latencyMs);
    }
    final status = ClassifierStatus.parse(data['status']);
    final rawLevel = data['level'];
    final level = status == ClassifierStatus.ok && rawLevel is String &&
            _levelCodes.contains(rawLevel)
        ? DistressLevel.parse(rawLevel)
        : null;
    final rawScore = data['score'];
    final version = data['modelVersion'];
    return ClassifierVerdict(
      status: status == ClassifierStatus.ok && level == null
          ? ClassifierStatus.error
          : status,
      level: level,
      score: rawScore is num ? rawScore.toDouble() : null,
      modelVersion: version is String ? version : null,
      latencyMs: latencyMs,
    );
  }

  static const _levelCodes = {
    'none', 'low', 'moderate_review', 'moderate_interrupt', 'acute',
  };
}

/// The slot.  One implementation today ([CloudSafetyClassifier]); tests
/// plug in fakes.
abstract class SafetyClassifier {
  /// Classify [text].  [inputPoint] / [source] are the
  /// `SafetyInputPoint` / `SafetySource` codes and [turnId] the turn, so
  /// the log row can be joined to `safety_events`.  Must not throw; the
  /// caller still applies its own timeout.
  Future<ClassifierVerdict> classify(
    String text, {
    required String inputPoint,
    required String source,
    required String turnId,
  });
}

/// Calls the `classifySafety` Cloud Function (asia-east2), which relays
/// the text to the model and logs the call.  The model's address and key
/// never reach the App.
class CloudSafetyClassifier implements SafetyClassifier {
  const CloudSafetyClassifier();

  @override
  Future<ClassifierVerdict> classify(
    String text, {
    required String inputPoint,
    required String source,
    required String turnId,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('classifySafety')
          .call<Object?>({
        'text': text,
        'inputPoint': inputPoint,
        'source': source,
        'turnId': turnId,
      });
      return ClassifierVerdict.fromResponse(res.data,
          latencyMs: sw.elapsedMilliseconds);
    } catch (e) {
      if (kDebugMode) debugPrint('[classifier] call failed: $e');
      return ClassifierVerdict(
          status: ClassifierStatus.clientError,
          latencyMs: sw.elapsedMilliseconds);
    }
  }
}

/// Writes the App's own `safety_classifier_calls` rows — only for calls
/// whose answer never arrived (client timeout / client error).  The
/// server writes every other row.
abstract class ClassifierFallbackLog {
  void record({
    required ClassifierStatus status,
    required String inputPoint,
    required String source,
    required String turnId,
    required int latencyMs,
    String? uid,
  });
}

/// Firestore implementation.  Fire-and-forget: offline, the row is
/// queued and synced later (so offline fallbacks are counted too).
class FirestoreClassifierFallbackLog implements ClassifierFallbackLog {
  const FirestoreClassifierFallbackLog({required this.available});

  final bool available;

  @override
  void record({
    required ClassifierStatus status,
    required String inputPoint,
    required String source,
    required String turnId,
    required int latencyMs,
    String? uid,
  }) {
    if (!available) return;
    final resolved = (uid != null && uid.isNotEmpty)
        ? uid
        : FirebaseAuth.instance.currentUser?.uid;
    if (resolved == null || resolved.isEmpty) return;
    unawaited(FirebaseFirestore.instance
        .collection('safety_classifier_calls')
        .add({
      'uid': resolved,
      'writer': 'app',
      'status': status.code,
      'input_point': inputPoint,
      'source': source,
      'turn_id': turnId,
      'latency_ms': latencyMs,
      'ts': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (Object e) {
      if (kDebugMode) debugPrint('[classifier] log write failed: $e');
    }));
  }
}

/// Lexicon + classifier → one level.  The classifier can only raise
/// (decision 0025): a failed, disabled or lower verdict leaves the
/// lexicon result as it is.  A raise keeps no matched term or category
/// (the model gives neither).
DistressMatch mergeClassifierVerdict(
    DistressMatch lexicon, ClassifierVerdict verdict) {
  final level = verdict.level;
  if (!verdict.ok || level == null) return lexicon;
  if (level.index <= lexicon.level.index) return lexicon;
  return DistressMatch(level);
}

/// Where the final level came from — `safety_events.detector`.
String detectorLabel(DistressMatch lexicon, ClassifierVerdict verdict) {
  final level = verdict.level;
  if (!verdict.ok || level == null) return 'lexicon';
  if (level.index > lexicon.level.index) return 'classifier';
  if (level == lexicon.level && lexicon.isEscalation) return 'both';
  return 'lexicon';
}

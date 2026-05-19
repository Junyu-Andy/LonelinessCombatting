import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Lightweight behaviour-analytics pipeline.
///
/// Design goals:
/// - Works whether or not the user is signed in. When the user is a guest
///   events are queued in memory and flushed on first sign-in, so we never
///   lose the "first-touch" context.
/// - Works whether or not Firebase is configured. When Firestore is
///   unreachable we fall back to debug-printing so developers can still see
///   the event stream while building.
/// - Zero PII in payloads. Callers pass primitives (counts, enum names,
///   durations); free-text fields are summarised to length rather than
///   shipped verbatim.
class AnalyticsService {
  AnalyticsService({required this.firebaseReady})
      : _sessionId = _newId();

  /// Mirrors `AuthService.available` — when false the Firestore writer is
  /// short-circuited and events only ever live in [_buffer].
  final bool firebaseReady;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _uid;
  String _sessionId;
  DateTime? _sessionStartedAt;
  final List<Map<String, dynamic>> _buffer = [];

  /// Context that rides along with every event. Set by the app shell when
  /// the user changes locale / toggles contrast / signs in so downstream
  /// analysts can slice by surface state without each call site caring.
  String _locale = 'zh';
  bool _highContrast = false;

  /// B.3 — arm rides along with every event so analysts can partition
  /// without joining against the user profile.  Set by the auth gate when
  /// the user profile loads; null in guest mode.
  String? _arm;

  String get sessionId => _sessionId;

  void setEnvironment({String? locale, bool? highContrast, String? arm}) {
    if (locale != null) _locale = locale;
    if (highContrast != null) _highContrast = highContrast;
    if (arm != null) _arm = arm;
  }

  /// B.3 — event names that REQUIRE the [_arm] tag to be set.  Asserted in
  /// debug builds so a missing arm field crashes early.  In release builds
  /// the event still fires (with arm=null) so we don't drop data.
  static const Set<String> _armRequiredEvents = {
    'm2_check_in_submitted',
    'm3_session_start', 'm3_turn_sent', 'm3_session_end',
    'm5_reflective_session_start', 'm5_reflective_session_end',
    'm5_thought_exercise_opened', 'm5_thought_exercise_saved',
    'm6_social_suggestion_shown', 'm6_social_suggestion_accepted',
    'm7_plan_saved', 'm7_followup_completed',
    'm8_article_opened',
    'm9_progress_viewed',
    'cross_referral_offered', 'cross_referral_accepted',
    'cross_referral_declined',
    // 3-layer routing telemetry (Sprint 5 fix I): keyword filter
    // match, LLM SURFACE/DEFER/SKIP, cooldown block, and final
    // surface decision.  All arm-required for Phase A calibration.
    'cross_referral_layer1_match', 'cross_referral_layer2_decision',
    'cross_referral_cooldown_blocked', 'cross_referral_surfaced',
    'repair_clicked', 'repair_completed',
    'ppr_brief_shown', 'ppr_brief_submitted', 'ppr_brief_skipped',
    'quiet_today_activated',
  };

  /// Called whenever the signed-in user changes. When transitioning from
  /// guest → signed-in we flush the buffered events under the new uid.
  Future<void> setUser(String? uid) async {
    final previouslyGuest = _uid == null;
    _uid = uid;
    if (uid != null && previouslyGuest && _buffer.isNotEmpty) {
      final buffered = List<Map<String, dynamic>>.from(_buffer);
      _buffer.clear();
      for (final event in buffered) {
        await _persist(event);
      }
    }
  }

  /// Records app moving to the foreground. Safe to call repeatedly —
  /// re-invoking before a matching [endSession] rolls the session id over.
  Future<void> startSession({String? platform}) async {
    _sessionId = _newId();
    _sessionStartedAt = DateTime.now();
    await logEvent('session_start', {
      if (platform != null) 'platform': platform,
    });
  }

  Future<void> endSession() async {
    if (_sessionStartedAt == null) return;
    final duration = DateTime.now().difference(_sessionStartedAt!).inSeconds;
    _sessionStartedAt = null;
    await logEvent('session_end', {
      'durationSeconds': duration,
    });
  }

  /// Core logging primitive. Everything else is a thin wrapper.
  Future<void> logEvent(
    String name, [
    Map<String, dynamic> params = const {},
  ]) async {
    // B.3 — arm tag is required on the per-module event list and asserted
    // in debug so missing-arm bugs surface in dev.  Release builds still
    // ship the event so analysts get partial data.
    assert(
      !_armRequiredEvents.contains(name) || _arm != null,
      'analytics event "$name" requires arm to be set via setEnvironment',
    );

    final event = <String, dynamic>{
      'name': name,
      'params': params,
      'sessionId': _sessionId,
      'locale': _locale,
      'highContrast': _highContrast,
      if (_arm != null) 'arm': _arm,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (kDebugMode) {
      debugPrint('[analytics] $name ${params.isEmpty ? '' : params}');
    }

    if (_uid == null) {
      _buffer.add(event);
      return;
    }

    await _persist(event);
  }

  Future<void> _persist(Map<String, dynamic> event) async {
    if (!firebaseReady || _uid == null) return;
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('events')
          .add({
        ...event,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[analytics] persist failed: $e');
      }
    }
  }

  // Convenience helpers — each call site stays short and readable.

  Future<void> logTabView({
    required String tab,
    required int durationSeconds,
  }) =>
      logEvent('tab_view', {
        'tab': tab,
        'durationSeconds': durationSeconds,
      });

  Future<void> logCheckIn({
    required int mood,
    required int loneliness,
    required int socialEnergy,
  }) =>
      logEvent('check_in_submitted', {
        'mood': mood,
        'loneliness': loneliness,
        'socialEnergy': socialEnergy,
      });

  Future<void> logSocialLogEntry({
    required bool hasPerson,
    required int summaryLength,
    required String feeling,
  }) =>
      logEvent('social_log_entry', {
        'hasPerson': hasPerson,
        'summaryLength': summaryLength,
        'feeling': feeling,
      });

  Future<void> logOpenerCopied({required String audience}) =>
      logEvent('opener_copied', {'audience': audience});

  Future<void> logEmergencyOpened({required String from}) =>
      logEvent('emergency_opened', {'from': from});

  Future<void> logAuth(String kind) => logEvent('auth_$kind');

  // -------------------------------------------------------------------------
  // B.3 — module-level event helpers (Sprint 2.4).
  //
  // Twenty-two new event types wired across M2/M3/M5–M9 + cross-referral +
  // repair + brief PPR + 今日休息.  All carry the implicit `arm` field via
  // [logEvent] (asserted in debug).  Free-text fields are summarised to
  // length / hash to preserve zero-PII.
  // -------------------------------------------------------------------------

  // M2 — daily check-in
  Future<void> logM2CheckInSubmitted({
    required int mood,
    required int loneliness,
    required int socialEnergy,
  }) =>
      logEvent('m2_check_in_submitted', {
        'mood': mood,
        'loneliness': loneliness,
        'socialEnergy': socialEnergy,
      });

  // M3 — reminiscence session
  Future<void> logM3SessionStart({required int weekIndex}) =>
      logEvent('m3_session_start', {'week': weekIndex});

  Future<void> logM3TurnSent({required int turnIndex, required int charLen}) =>
      logEvent('m3_turn_sent', {'turn': turnIndex, 'len': charLen});

  Future<void> logM3SessionEnd({
    required int weekIndex,
    required int turnCount,
    required int durationSeconds,
    required String trigger, // 'manual' | 'idle_60s'
  }) =>
      logEvent('m3_session_end', {
        'week': weekIndex,
        'turns': turnCount,
        'durationSeconds': durationSeconds,
        'trigger': trigger,
      });

  // M5 — reflective dialogue + thought exercise
  Future<void> logM5SessionStart() => logEvent('m5_reflective_session_start');

  Future<void> logM5SessionEnd({
    required int turnCount,
    required int durationSeconds,
  }) =>
      logEvent('m5_reflective_session_end', {
        'turns': turnCount,
        'durationSeconds': durationSeconds,
      });

  Future<void> logM5ThoughtExerciseOpened({required String origin}) =>
      logEvent('m5_thought_exercise_opened', {'origin': origin});

  Future<void> logM5ThoughtExerciseSaved({required int totalCharLen}) =>
      logEvent('m5_thought_exercise_saved', {'len': totalCharLen});

  // M6 — social suggestions
  Future<void> logM6SuggestionShown({required String suggestionId}) =>
      logEvent('m6_social_suggestion_shown', {'id': suggestionId});

  Future<void> logM6SuggestionAccepted({required String suggestionId}) =>
      logEvent('m6_social_suggestion_accepted', {'id': suggestionId});

  // M7 — action loop
  Future<void> logM7PlanSaved({required String kind}) =>
      logEvent('m7_plan_saved', {'kind': kind});

  Future<void> logM7FollowUpCompleted({required String outcome}) =>
      logEvent('m7_followup_completed', {'outcome': outcome});

  // M8 — education
  Future<void> logM8ArticleOpened({required String articleId}) =>
      logEvent('m8_article_opened', {'id': articleId});

  // M9 — progress
  Future<void> logM9ProgressViewed() => logEvent('m9_progress_viewed');

  // Cross-referral (4 events)
  Future<void> logCrossReferralOffered({
    required String fromAgent,
    required String toAgent,
    required int matchedTextLen,
    required String matchedTextPrefix32,
  }) =>
      logEvent('cross_referral_offered', {
        'fromAgent': fromAgent,
        'toAgent': toAgent,
        'matchedTextLen': matchedTextLen,
        // Pre-truncated; the agent UI must never pass full text here.
        'matchedTextPrefix32': matchedTextPrefix32,
      });

  Future<void> logCrossReferralAccepted({
    required String fromAgent,
    required String toAgent,
  }) =>
      logEvent('cross_referral_accepted', {
        'fromAgent': fromAgent,
        'toAgent': toAgent,
      });

  Future<void> logCrossReferralDeclined({
    required String fromAgent,
    required String toAgent,
  }) =>
      logEvent('cross_referral_declined', {
        'fromAgent': fromAgent,
        'toAgent': toAgent,
      });

  // Repair (B.9)
  Future<void> logRepairClicked({
    required String agentId,
    required String moduleId,
  }) =>
      logEvent('repair_clicked', {
        'agentId': agentId,
        'moduleId': moduleId,
      });

  Future<void> logRepairCompleted({
    required String agentId,
    required String moduleId,
    required String resolution, // 'llm_regenerate' | 'template_advance'
  }) =>
      logEvent('repair_completed', {
        'agentId': agentId,
        'moduleId': moduleId,
        'resolution': resolution,
      });

  // Brief PPR (B.6)
  Future<void> logPprBriefShown({required String agentId, required bool mandatory}) =>
      logEvent('ppr_brief_shown', {
        'agentId': agentId,
        'mandatory': mandatory,
      });

  Future<void> logPprBriefSubmitted({required String agentId}) =>
      logEvent('ppr_brief_submitted', {'agentId': agentId});

  Future<void> logPprBriefSkipped({required String agentId}) =>
      logEvent('ppr_brief_skipped', {'agentId': agentId});

  // 今日休息 (B.10)
  Future<void> logQuietTodayActivated() => logEvent('quiet_today_activated');

  static String _newId() {
    final rand = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    // Use the literal 2^32 instead of `1 << 32` because bit-shifts on
    // Dart-for-web (JS) are limited to 32 bits and `1 << 32` evaluates
    // to 0, which makes Random.nextInt throw RangeError.
    final noise = rand.nextInt(0x100000000).toRadixString(36);
    return '$now-$noise';
  }
}

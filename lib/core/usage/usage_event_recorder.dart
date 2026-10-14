/// T40 (registry C23) — usage events: one row when the App comes to the
/// foreground and one when it goes to the background.
///
/// What the PI needs (dev-tasks-1014d §目的): did each participant open
/// the App today, when was the first open, and who has not opened it for
/// several days.  The rows feed the T39 dashboard only; they are process
/// data, never an outcome, never memory, never conversation.
///
/// Rules (dev-tasks-1014d T40):
///   1. Both arms, no UI, nothing the participant can see.
///   2. Not before registration: a row is written only while the signed-in
///      account is enrolled (`users/{uid}.cohort` = `phase_b` / `pilot`).
///      A foreground that happened before the profile was known (cold
///      start) is held and written with its ORIGINAL time once the enrolled
///      profile arrives; if the account turns out not to be enrolled it is
///      dropped.
///   3. Offline: the row goes through the Firestore SDK's offline queue
///      (persistence is on), so it is cached on the phone and uploaded when
///      the network is back.  `clientAt` is the phone's clock at the event;
///      `receivedAt` is a server timestamp, resolved when the server commits
///      the write.  The server trigger (functions/usage_events.js) compares
///      the two and marks `uploadedLate` — the client cannot know reliably
///      whether it is offline, and a process kill while offline would lose
///      a client-side mark.
///   4. Switch `app_config/feature_flags.usageEventsEnabled` (default OFF):
///      off = no row, nothing else changes.  The Phase A analytics rows
///      (`events` `app_foreground` / `app_background`, no client time) keep
///      being written as before in both states.
///
/// Row: `users/{uid}/usage_events/{autoId}` — `type` (`foreground` /
/// `background`), `clientAt` (client clock), `receivedAt` (server),
/// `appVersion`, `buildNumber`, `platform`, `schemaVersion` 1.  The owner
/// can only create rows (no read / update / delete — firestore.rules); the
/// research ID, study day, Hong Kong date and `uploadedLate` are stamped
/// by the server trigger.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../feature_flags/remote_feature_flags.dart';
import '../version/build_info.dart';
import '../../features/auth/data/user_profile.dart';

/// Firestore sub-collection under `users/{uid}`.
const String kUsageEventsCollection = 'usage_events';

/// Row shape version written by this build.
const int kUsageEventSchemaVersion = 1;

enum UsageEventType {
  foreground,
  background;

  String get code => name;
}

/// One usage event, before the server stamps it.
@immutable
class UsageEvent {
  const UsageEvent({
    required this.uid,
    required this.type,
    required this.clientAt,
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
  });

  final String uid;
  final UsageEventType type;

  /// The phone's clock at the moment of the event (kept as-is on a late
  /// upload).
  final DateTime clientAt;
  final String appVersion;
  final String buildNumber;
  final String platform;

  /// The Firestore document (without `receivedAt`, which the sink adds as
  /// a server timestamp).
  Map<String, Object?> toMap() => {
        'type': type.code,
        'clientAt': Timestamp.fromDate(clientAt),
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'platform': platform,
        'schemaVersion': kUsageEventSchemaVersion,
      };
}

/// Where rows go.  [FirestoreUsageEventSink] in the App; tests use
/// [InMemoryUsageEventSink].
abstract class UsageEventSink {
  void write(UsageEvent event);
}

class InMemoryUsageEventSink implements UsageEventSink {
  final List<UsageEvent> events = [];

  @override
  void write(UsageEvent event) => events.add(event);
}

/// Fire-and-forget write through the Firestore SDK (offline queue).  Never
/// throws, never blocks the UI.
class FirestoreUsageEventSink implements UsageEventSink {
  FirestoreUsageEventSink({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;

  @override
  void write(UsageEvent event) {
    unawaited(() async {
      try {
        final db = _db ?? FirebaseFirestore.instance;
        await db
            .collection('users')
            .doc(event.uid)
            .collection(kUsageEventsCollection)
            .add({
          ...event.toMap(),
          'receivedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[UsageEvents] write failed: $e');
      }
    }());
  }
}

/// Turns App lifecycle changes and the signed-in profile into usage
/// events.  Pure Dart: the sink, the switch and the clock are injected so
/// the rules can be tested without Firestore.
class UsageEventRecorder {
  UsageEventRecorder({
    required UsageEventSink sink,
    bool Function()? enabled,
    DateTime Function()? clock,
    String platform = 'unknown',
    String? appVersion,
    String? buildNumber,
  })  : _sink = sink,
        _enabled = enabled ?? _flagEnabled,
        _clock = clock ?? DateTime.now,
        _platform = platform,
        _appVersion = appVersion ?? BuildInfo.appVersion,
        _buildNumber = buildNumber ?? BuildInfo.buildNumber;

  static bool _flagEnabled() => RemoteFeatureFlags.current.usageEventsEnabled;

  final UsageEventSink _sink;
  final bool Function() _enabled;
  final DateTime Function() _clock;
  final String _platform;
  final String _appVersion;
  final String _buildNumber;

  String? _uid;
  bool _enrolled = false;

  bool _inForeground = false;
  DateTime? _foregroundSince;

  /// Whether the current foreground stretch already has a `foreground`
  /// row.  A `background` row is written only for a stretch that has one,
  /// so the pair always matches (no "background" without its "foreground").
  bool _foregroundRecorded = false;

  bool get _canRecord => _enabled() && _enrolled && _uid != null;

  /// The signed-in profile changed (sign-in, sign-out, the researcher's
  /// registration landing while the App is open).  Called on every profile
  /// emission; cheap when nothing changed.
  void setProfile(UserProfile? profile) {
    final uid = profile?.uid;
    final enrolled = profile != null && profile.isEnrolled;
    final uidChanged = uid != _uid;
    _uid = uid;
    _enrolled = enrolled;
    if (uidChanged) {
      // A different account: whatever this stretch recorded belongs to the
      // old one; start the pairing afresh for the new account.
      _foregroundRecorded = false;
    }
    _flushPendingForeground();
  }

  /// The App came to the foreground (also the cold start).
  void onForeground([DateTime? at]) {
    if (_inForeground) return;
    _inForeground = true;
    _foregroundSince = at ?? _clock();
    _foregroundRecorded = false;
    _flushPendingForeground();
  }

  /// The App went to the background (or was hidden / detached).
  void onBackground([DateTime? at]) {
    if (!_inForeground) return;
    _inForeground = false;
    if (_foregroundRecorded && _canRecord) {
      _write(UsageEventType.background, at ?? _clock());
    }
    _foregroundRecorded = false;
    _foregroundSince = null;
  }

  /// Write the foreground row of the current stretch if it is still owed
  /// (cold start before the profile was known; registration landing while
  /// open) and everything now allows it.  Keeps the original time.
  void _flushPendingForeground() {
    if (!_inForeground || _foregroundRecorded || !_canRecord) return;
    _foregroundRecorded = true;
    _write(UsageEventType.foreground, _foregroundSince ?? _clock());
  }

  void _write(UsageEventType type, DateTime at) {
    _sink.write(UsageEvent(
      uid: _uid!,
      type: type,
      clientAt: at,
      appVersion: _appVersion,
      buildNumber: _buildNumber,
      platform: _platform,
    ));
  }
}

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
///      account is enrolled (`users/{uid}.cohort` in Cohorts.enrolled).
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
///
/// 1020c §1(5) — the 小讀本 rows ride on the same collection, the same
/// switch and the same enrolment check ([recordReader]):
///   `reader_open`    + `unitId`
///   `reader_section` + `unitId`, `sectionId` (the page's `data-section`)
///   `reader_cta`     + `unitId`, `cta` (`small_action` / `plan` / `thought`)
///   `reader_close`   + `unitId`, `seconds` (time the reader was on screen)
/// Ids only — never any text.  An id that is not [kReaderIdPattern] is
/// dropped here and refused by the rules.
///
/// 1020m 第二节 — page 1's small-action row (「今日要做嘅事」, both arms)
/// rides on the same collection, switch and enrolment check
/// ([recordHomeSmallAction]):
///   `home_small_action_shown`    + `rowState` (`ask` / `plan` / `done` /
///                                  `next_day_plan` — 1020n), + `planId`
///                                  unless `ask` (one row per plan line)
///   `home_small_action_open`     (the 「今日想做啲咩小行動？」 row tapped)
///   `home_small_action_later`    (「遲啲先」)
///   `home_small_action_done`     + `planId` (「做咗」)
///   `home_small_action_postpone` + `planId`, `moved` (「改日」; `moved` is
///                                  false on the second press)
///   `home_small_action_more`     (1020n: 「仲有冇其他計劃？」 tapped)
///   `home_small_action_list`     (1020n: 「仲有 N 個計劃」 tapped)
/// A plan id that is not [kPlanIdPattern] is dropped here and refused by
/// the rules.
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

/// The shape of a reader unit id and a `data-section` id (1020c).  The
/// same pattern is in firestore.rules (usage_events) and
/// tool/check_reader_html.js.
final RegExp kReaderIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,47}$');

/// The three 小讀本 action buttons (`peizhu://cta/<code>`).
const Set<String> kReaderCtaCodes = {'small_action', 'plan', 'thought'};

/// A reader stay longer than this is recorded as this (a phone left on).
const int kReaderMaxSeconds = 86400;

/// The shape of an `action_plans` document id (1020m; Firestore auto ids
/// are 20 letters and digits).  The same pattern is in firestore.rules.
final RegExp kPlanIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// `rowState` values of `home_small_action_shown` (1020m).
const Set<String> kHomeSmallActionRowStates = {
  'ask',
  'plan',
  'done',
  'next_day_plan',
};

enum UsageEventType {
  foreground('foreground'),
  background('background'),
  readerOpen('reader_open'),
  readerSection('reader_section'),
  readerCta('reader_cta'),
  readerClose('reader_close'),
  // 1020m 第二节 — page 1's small-action row.
  homeSmallActionShown('home_small_action_shown'),
  homeSmallActionOpen('home_small_action_open'),
  homeSmallActionLater('home_small_action_later'),
  homeSmallActionDone('home_small_action_done'),
  homeSmallActionPostpone('home_small_action_postpone'),
  // 1020n 第三节.
  homeSmallActionMore('home_small_action_more'),
  homeSmallActionList('home_small_action_list');

  const UsageEventType(this.code);

  /// The `type` value in the row.
  final String code;

  bool get isReader => code.startsWith('reader_');

  bool get isHomeSmallAction => code.startsWith('home_small_action_');
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
    this.unitId,
    this.sectionId,
    this.cta,
    this.seconds,
    this.rowState,
    this.planId,
    this.moved,
  });

  final String uid;
  final UsageEventType type;

  /// The phone's clock at the moment of the event (kept as-is on a late
  /// upload).
  final DateTime clientAt;
  final String appVersion;
  final String buildNumber;
  final String platform;

  /// 1020c reader rows only (null on foreground / background).
  final String? unitId;
  final String? sectionId;
  final String? cta;
  final int? seconds;

  /// 1020m small-action rows only.
  final String? rowState;
  final String? planId;
  final bool? moved;

  /// The Firestore document (without `receivedAt`, which the sink adds as
  /// a server timestamp).
  Map<String, Object?> toMap() => {
        'type': type.code,
        'clientAt': Timestamp.fromDate(clientAt),
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'platform': platform,
        'schemaVersion': kUsageEventSchemaVersion,
        if (unitId != null) 'unitId': unitId,
        if (sectionId != null) 'sectionId': sectionId,
        if (cta != null) 'cta': cta,
        if (seconds != null) 'seconds': seconds,
        if (rowState != null) 'rowState': rowState,
        if (planId != null) 'planId': planId,
        if (moved != null) 'moved': moved,
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

  /// 1020c §1(5) — one 小讀本 row (switch on, account enrolled, like the
  /// lifecycle rows).  [type] must be a reader type; the fields it needs:
  /// `reader_section` → [sectionId], `reader_cta` → [cta] (one of
  /// [kReaderCtaCodes]), `reader_close` → [seconds] (clamped to
  /// 0…[kReaderMaxSeconds]).  Anything malformed is dropped, not written.
  /// Returns whether a row was written.
  bool recordReader(
    UsageEventType type, {
    required String unitId,
    String? sectionId,
    String? cta,
    int? seconds,
  }) {
    if (!type.isReader || !_canRecord) return false;
    if (!kReaderIdPattern.hasMatch(unitId)) return false;
    switch (type) {
      case UsageEventType.readerOpen:
        sectionId = null;
        cta = null;
        seconds = null;
      case UsageEventType.readerSection:
        if (sectionId == null || !kReaderIdPattern.hasMatch(sectionId)) {
          return false;
        }
        cta = null;
        seconds = null;
      case UsageEventType.readerCta:
        if (cta == null || !kReaderCtaCodes.contains(cta)) return false;
        sectionId = null;
        seconds = null;
      case UsageEventType.readerClose:
        if (seconds == null) return false;
        seconds = seconds.clamp(0, kReaderMaxSeconds);
        sectionId = null;
        cta = null;
      case UsageEventType.foreground:
      case UsageEventType.background:
      case UsageEventType.homeSmallActionShown:
      case UsageEventType.homeSmallActionOpen:
      case UsageEventType.homeSmallActionLater:
      case UsageEventType.homeSmallActionDone:
      case UsageEventType.homeSmallActionPostpone:
      case UsageEventType.homeSmallActionMore:
      case UsageEventType.homeSmallActionList:
        return false;
    }
    _write(type, _clock(),
        unitId: unitId, sectionId: sectionId, cta: cta, seconds: seconds);
    return true;
  }

  /// 1020m 第二节 — one row of page 1's small-action row (switch on,
  /// account enrolled, like the lifecycle rows).  [type] must be a
  /// `home_small_action_*` type; what each needs: `shown` → [rowState]
  /// (one of [kHomeSmallActionRowStates]) and, unless `ask`, [planId];
  /// `done` → [planId]; `postpone` → [planId] and [moved]; `open` /
  /// `later` / `more` / `list` → nothing.  Anything malformed is dropped, not written.
  /// Returns whether a row was written.
  bool recordHomeSmallAction(
    UsageEventType type, {
    String? rowState,
    String? planId,
    bool? moved,
  }) {
    if (!type.isHomeSmallAction || !_canRecord) return false;
    bool idOk(String? id) => id != null && kPlanIdPattern.hasMatch(id);
    switch (type) {
      case UsageEventType.homeSmallActionShown:
        if (rowState == null || !kHomeSmallActionRowStates.contains(rowState)) {
          return false;
        }
        if (rowState == 'ask') {
          planId = null;
        } else if (!idOk(planId)) {
          return false;
        }
        moved = null;
      case UsageEventType.homeSmallActionOpen:
      case UsageEventType.homeSmallActionLater:
      case UsageEventType.homeSmallActionMore:
      case UsageEventType.homeSmallActionList:
        rowState = null;
        planId = null;
        moved = null;
      case UsageEventType.homeSmallActionDone:
        if (!idOk(planId)) return false;
        rowState = null;
        moved = null;
      case UsageEventType.homeSmallActionPostpone:
        if (!idOk(planId) || moved == null) return false;
        rowState = null;
      default:
        return false;
    }
    _write(type, _clock(), rowState: rowState, planId: planId, moved: moved);
    return true;
  }

  void _write(
    UsageEventType type,
    DateTime at, {
    String? unitId,
    String? sectionId,
    String? cta,
    int? seconds,
    String? rowState,
    String? planId,
    bool? moved,
  }) {
    _sink.write(UsageEvent(
      uid: _uid!,
      type: type,
      clientAt: at,
      appVersion: _appVersion,
      buildNumber: _buildNumber,
      platform: _platform,
      unitId: unitId,
      sectionId: sectionId,
      cta: cta,
      seconds: seconds,
      rowState: rowState,
      planId: planId,
      moved: moved,
    ));
  }
}

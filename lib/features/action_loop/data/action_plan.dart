import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'home_small_action.dart';

/// M7 implementation-intention record. Conceptually one if-then plan:
///   "If <when> <where>, with <whoWith>, I will <action>. If it doesn't
///    work out, I will <fallback>."
///
/// Lives at `users/{uid}/action_plans/{autoId}`. The follow-up surface
/// reads this collection to ask "件事點呀？" once the planned moment has
/// passed.
class ActionPlan {
  final String? id;
  final String action;
  final String whenText; // free text e.g. "tomorrow morning" / "聽朝"
  final String whereText;
  final String whoWith;
  final String fallback;

  /// Arm code at the time of authoring. Used for analysis splits.
  final String armCode;

  /// When the plan was created.
  final DateTime createdAt;

  /// Optional concrete reminder time. If null, the follow-up surface
  /// uses a 24-hour heuristic.
  final DateTime? scheduledFor;

  /// Set by the follow-up surface when the user answers "did it happen?".
  final FollowUpOutcome? outcome;

  /// Optional free-text the user added at follow-up.
  final String? followUpNote;

  // ---- 1020e 二.7 (switch actionPlanSimplifiedEnabled).  Written only
  // when the switch is on; null / 0 on every older plan. ----

  /// 2 = saved under the simplified rule (only 做咩 and 幾時 required; an
  /// empty whereText / whoWith / fallback means the elder skipped it).
  final int? planFormVersion;

  /// Where the planner was opened from: [ActionPlanSource].
  final String? source;

  /// The suggestion text the planner was opened with (before any edit).
  final String? seedAction;

  /// How many times 做咩 / 幾時 were changed after saving.
  final int editCount;

  /// When the elder deleted it (soft delete; the row stays).
  final DateTime? deletedAt;

  // ---- 1020m 第二节: page 1's small-action row (HomeSmallActionRow).
  // Written only by the row's 「做咗」 / 「改日」; null / 0 on every other
  // plan.  See [HomeSmallAction] and decision 0064. ----

  /// Hong Kong day (yyyy-MM-dd) the plan is for after 「改日」 moved it.
  /// Null = never moved: the day of its follow-up reminder (saved + 24 h,
  /// [HomeSmallAction.dueDateOf]).
  final String? homeRowDueDate;

  /// The row's last answer: `done` (做咗) or `later` (改日).
  final String? homeRowStatus;

  /// Hong Kong day (yyyy-MM-dd) of that answer.
  final String? homeRowAnsweredDate;

  /// How many times 「改日」 was pressed (the first one moves the plan,
  /// the second does not).
  final int homeRowLaterCount;

  /// Where the follow-up answer (`outcome`) came from: `home_row` when
  /// 「做咗」 set it; null = the 「件事點呀？」 page (as before).
  final String? followUpSource;

  const ActionPlan({
    this.id,
    required this.action,
    required this.whenText,
    required this.whereText,
    required this.whoWith,
    required this.fallback,
    required this.armCode,
    required this.createdAt,
    this.scheduledFor,
    this.outcome,
    this.followUpNote,
    this.planFormVersion,
    this.source,
    this.seedAction,
    this.editCount = 0,
    this.deletedAt,
    this.homeRowDueDate,
    this.homeRowStatus,
    this.homeRowAnsweredDate,
    this.homeRowLaterCount = 0,
    this.followUpSource,
  });

  /// Switch off: exactly the ten keys plans have always had.  The 1020e
  /// keys are added only when set (planFormVersion / source / seedAction
  /// on create; the edit and delete keys come from [ActionPlanEdits]).
  Map<String, dynamic> toMap() => {
        'action': action,
        'whenText': whenText,
        'whereText': whereText,
        'whoWith': whoWith,
        'fallback': fallback,
        'arm': armCode,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'outcome': outcome?.name,
        'followUpNote': followUpNote,
        if (planFormVersion != null) 'planFormVersion': planFormVersion,
        if (source != null) 'source': source,
        if (seedAction != null) 'seedAction': seedAction,
      };

  /// Waiting for 「件事點呀」 and not deleted.
  bool get isPending => outcome == null && deletedAt == null;

  factory ActionPlan.fromMap(String id, Map<String, dynamic> map) {
    DateTime parse(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return ActionPlan(
      id: id,
      action: (map['action'] as String?) ?? '',
      whenText: (map['whenText'] as String?) ?? '',
      whereText: (map['whereText'] as String?) ?? '',
      whoWith: (map['whoWith'] as String?) ?? '',
      fallback: (map['fallback'] as String?) ?? '',
      armCode: (map['arm'] as String?) ?? '',
      createdAt: parse(map['createdAt']),
      scheduledFor: map['scheduledFor'] == null ? null : parse(map['scheduledFor']),
      outcome: FollowUpOutcomeX.tryParse(map['outcome'] as String?),
      followUpNote: map['followUpNote'] as String?,
      planFormVersion: (map['planFormVersion'] as num?)?.toInt(),
      source: map['source'] as String?,
      seedAction: map['seedAction'] as String?,
      editCount: (map['editCount'] as num?)?.toInt() ?? 0,
      deletedAt: map['deletedAt'] == null ? null : parse(map['deletedAt']),
      homeRowDueDate: map['homeRowDueDate'] as String?,
      homeRowStatus: map['homeRowStatus'] as String?,
      homeRowAnsweredDate: map['homeRowAnsweredDate'] as String?,
      homeRowLaterCount: (map['homeRowLaterCount'] as num?)?.toInt() ?? 0,
      followUpSource: map['followUpSource'] as String?,
    );
  }

  /// The parts that were filled in, for display: 幾時 · 邊度 · 同邊個 with
  /// the empty ones left out (an old plan has all of them, so its line is
  /// unchanged).
  static String joinFilled(Iterable<String> parts) =>
      parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' · ');
}

/// Values of [ActionPlan.source].
class ActionPlanSource {
  const ActionPlanSource._();
  static const suggestion = 'suggestion';
  static const landing = 'landing';
  static const checkInQ5 = 'check_in_q5';
}

/// 1020e 二.7: what an edit or a delete writes, as plain data so it can be
/// tested without Firestore.  The repository adds the server timestamps,
/// the increment and the array append.
class ActionPlanEdits {
  const ActionPlanEdits._();

  /// The fields an edit may change.
  static const editable = ['action', 'whenText'];

  /// Field → new value for the ones that really changed (trimmed).
  static Map<String, String> changes(ActionPlan before,
      {required String action, required String whenText}) {
    final out = <String, String>{};
    if (action.trim() != before.action) out['action'] = action.trim();
    if (whenText.trim() != before.whenText) out['whenText'] = whenText.trim();
    return out;
  }

  /// Plain part of the update: the changed fields, `original` on the first
  /// edit only (the plan as first saved), and one `editLog` entry (which
  /// fields, their old values, the phone's clock).  Empty when nothing
  /// changed.
  static Map<String, dynamic> updateData(
    ActionPlan before,
    Map<String, String> changes, {
    required DateTime nowLocal,
  }) {
    if (changes.isEmpty) return const {};
    return {
      ...changes,
      if (before.editCount == 0)
        'original': {'action': before.action, 'whenText': before.whenText},
      'editLogEntry': {
        'atLocal': nowLocal.toIso8601String(),
        'fields': changes.keys.toList(),
        'before': {
          for (final k in changes.keys)
            k: k == 'action' ? before.action : before.whenText,
        },
      },
    };
  }
}

enum FollowUpOutcome { happened, partial, didNotHappen }

extension FollowUpOutcomeX on FollowUpOutcome {
  static FollowUpOutcome? tryParse(String? raw) {
    if (raw == null) return null;
    for (final v in FollowUpOutcome.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Thin Firestore CRUD for [ActionPlan]. Stays tiny on purpose; if it
/// grows we move it to its own service like `AuthService`.
class ActionPlanRepository {
  ActionPlanRepository({required this.available});

  /// The repository the action-loop pages use.  Tests set [testOverride]
  /// to a fake (no Firestore in widget tests).
  factory ActionPlanRepository.forApp({required bool available}) =>
      testOverride ?? ActionPlanRepository(available: available);

  @visibleForTesting
  static ActionPlanRepository? testOverride;

  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('action_plans');

  Future<String?> create(String uid, ActionPlan plan) async {
    if (!available) return null;
    final ref = await _ref(uid).add(plan.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }

  Future<void> updateOutcome(
    String uid,
    String planId, {
    required FollowUpOutcome outcome,
    String? note,
  }) async {
    if (!available) return;
    await _ref(uid).doc(planId).set(
      {
        'outcome': outcome.name,
        if (note != null) 'followUpNote': note,
        'followedUpAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// 1020e 二.7: change 做咩 / 幾時.  Writes the changed fields, `original`
  /// on the first edit, `editCount` + 1, `lastEditedAt`, one `editLog`
  /// entry; then puts the new 做咩 into the plan's unsent reminders (the
  /// stored text only — the push itself never carries it).  The reminder
  /// time does not move.  Returns the changed field names.
  Future<List<String>> update(
    String uid,
    ActionPlan before, {
    required String action,
    required String whenText,
  }) async {
    final changes =
        ActionPlanEdits.changes(before, action: action, whenText: whenText);
    if (!available || before.id == null || changes.isEmpty) {
      return changes.keys.toList();
    }
    final data = Map<String, dynamic>.of(ActionPlanEdits.updateData(
        before, changes,
        nowLocal: DateTime.now()));
    final entry = data.remove('editLogEntry');
    await _ref(uid).doc(before.id).set({
      ...data,
      'editCount': FieldValue.increment(1),
      'lastEditedAt': FieldValue.serverTimestamp(),
      'editLog': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
    if (changes.containsKey('action')) {
      final newAction = changes['action']!;
      for (final d in await _unsentReminders(uid, before.id!)) {
        await d.reference.update({
          'bodyZh': '你之前計劃做：$newAction。',
          'bodyEn': 'Your plan: $newAction.',
        });
      }
    }
    return changes.keys.toList();
  }

  /// 1020e 二.7: soft delete — the row stays with `deletedAt` and
  /// `deletedFrom`; the plan's unsent reminders are deleted (the server
  /// also skips a reminder whose plan has `deletedAt`).
  Future<void> softDelete(String uid, ActionPlan plan,
      {required String from}) async {
    if (!available || plan.id == null) return;
    await _ref(uid).doc(plan.id).set({
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedFrom': from,
    }, SetOptions(merge: true));
    for (final d in await _unsentReminders(uid, plan.id!)) {
      await d.reference.delete();
    }
  }

  /// 1020m 第二节 — 「做咗」 on page 1's small-action row: the follow-up
  /// answer as the 「件事點呀？」 page writes it (`outcome: happened`,
  /// `followedUpAt`) plus `followUpSource: home_row` and the row's status
  /// fields ([HomeSmallAction.doneUpdate]); then the plan's unsent
  /// reminders go, as that page does.  No model call in either arm.
  Future<void> markDoneFromHome(String uid, ActionPlan plan,
      {required DateTime now}) async {
    if (!available || plan.id == null) return;
    final data = Map<String, dynamic>.of(HomeSmallAction.doneUpdate(now));
    final entry = data.remove(HomeSmallAction.logEntryKey);
    await _ref(uid).doc(plan.id).set({
      ...data,
      'followedUpAt': FieldValue.serverTimestamp(),
      'homeRowAnsweredAt': FieldValue.serverTimestamp(),
      'homeRowLog': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
    await _applyReminderOps(uid,
        HomeSmallAction.reminderOpsAfterDone(await _planReminders(uid, plan)));
  }

  /// 1020m 第二节 — 「改日」 on page 1's small-action row: status only
  /// ([HomeSmallAction.postponeUpdate]; no `outcome`, so the plan stays in
  /// 「我嘅計劃」).  The first press moves the plan and its reminder to
  /// tomorrow, same clock time; the second drops the reminder
  /// ([HomeSmallAction.reminderOpsAfterPostpone]).
  Future<HomeSmallActionPostpone> postponeFromHome(String uid, ActionPlan plan,
      {required DateTime now}) async {
    final p = HomeSmallAction.postpone(plan, now);
    if (!available || plan.id == null) return p;
    final data = Map<String, dynamic>.of(HomeSmallAction.postponeUpdate(p, now));
    final entry = data.remove(HomeSmallAction.logEntryKey);
    await _ref(uid).doc(plan.id).set({
      ...data,
      'homeRowAnsweredAt': FieldValue.serverTimestamp(),
      'homeRowLog': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
    await _applyReminderOps(
        uid,
        HomeSmallAction.reminderOpsAfterPostpone(
            plan, p, await _planReminders(uid, plan)));
    return p;
  }

  Future<List<PlanReminder>> _planReminders(String uid, ActionPlan plan) async {
    final docs = await _unsentReminders(uid, plan.id!);
    return [
      for (final d in docs)
        if (d.data()['kind'] == 'm7_followup')
          PlanReminder(
            id: d.id,
            fireAt: d.data()['fireAt'] as String?,
            dispatchStatus: d.data()['dispatchStatus'] as String?,
          ),
    ];
  }

  Future<void> _applyReminderOps(String uid, List<PlanReminderOp> ops) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders');
    for (final op in ops) {
      switch (op.kind) {
        case PlanReminderOpKind.move:
          await col.doc(op.id).update({
            'fireAt': op.to,
            'movedFromFireAt': op.from,
            'movedBy': HomeSmallAction.movedBy,
          });
        case PlanReminderOpKind.delete:
          await col.doc(op.id).delete();
        case PlanReminderOpKind.create:
          await col.add({
            ...op.request!.toMap(),
            'movedBy': HomeSmallAction.movedBy,
          });
      }
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _unsentReminders(
      String uid, String planId) async {
    final q = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .where('linkedDocId', isEqualTo: planId)
        .where('delivered', isEqualTo: false)
        .get();
    return q.docs;
  }

  /// Plans without an `outcome` yet, ordered by `createdAt` ascending so
  /// the oldest awaiting follow-up is shown first.
  ///
  /// Filters `outcome == null` client-side ON PURPOSE: the original
  /// where+orderBy pair needs a composite index that is not deployed
  /// (no firestore.indexes.json), which made this stream error out and
  /// every pending-plan surface silently render nothing.  Per-user
  /// plans are few, so the client-side filter is free and index-proof.
  /// 1020e: a soft-deleted plan (`deletedAt`) is not pending either (no
  /// plan has it while the switch is off).
  Stream<List<ActionPlan>> pending(String uid) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs
            .where((d) =>
                d.data()['outcome'] == null && d.data()['deletedAt'] == null)
            .map((d) => ActionPlan.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<ActionPlan>> all(String uid) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ActionPlan.fromMap(d.id, d.data()))
            .toList());
  }
}

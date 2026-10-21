/// 1020m 第二节 — where page 1's small-action row reads and writes.
///
///   - The plans: `users/{uid}/action_plans` (all of them, through
///     [ActionPlanRepository.all]; the row picks today's with
///     [HomeSmallAction.resolve]).
///   - 「做咗」 / 「改日」: [ActionPlanRepository.markDoneFromHome] /
///     [ActionPlanRepository.postponeFromHome] (the plan's fields and its
///     `reminders`).
///   - 「遲啲先」: one per-phone day mark in `shared_preferences`
///     ([laterKey]), like batch 3's `home.moodRow.skippedDate`.  Nothing
///     about it goes to Firestore except the usage event.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../action_loop/data/action_plan.dart';
import '../../action_loop/data/home_small_action.dart';

abstract class SmallActionRowStore {
  /// Day (yyyy-MM-dd, Hong Kong) 「遲啲先」 was pressed.
  static const String laterKey = 'home.smallAction.laterDate';

  /// Every plan of [uid] (deleted and answered ones too).
  Stream<List<ActionPlan>> plans(String uid);

  /// 「做咗」.
  Future<void> markDone(String uid, ActionPlan plan, DateTime now);

  /// 「改日」.
  Future<HomeSmallActionPostpone> postpone(
      String uid, ActionPlan plan, DateTime now);

  Future<String?> readLaterMark();
  Future<void> writeLaterMark(String dateIso);
}

class DefaultSmallActionRowStore implements SmallActionRowStore {
  DefaultSmallActionRowStore({required this.available});

  final bool available;

  ActionPlanRepository get _repo =>
      ActionPlanRepository.forApp(available: available);

  /// Fallback when shared_preferences cannot be read.
  static final Map<String, String> _memory = {};

  @override
  Stream<List<ActionPlan>> plans(String uid) => _repo.all(uid);

  @override
  Future<void> markDone(String uid, ActionPlan plan, DateTime now) =>
      _repo.markDoneFromHome(uid, plan, now: now);

  @override
  Future<HomeSmallActionPostpone> postpone(
          String uid, ActionPlan plan, DateTime now) =>
      _repo.postponeFromHome(uid, plan, now: now);

  @override
  Future<String?> readLaterMark() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(SmallActionRowStore.laterKey) ??
          _memory[SmallActionRowStore.laterKey];
    } catch (_) {
      return _memory[SmallActionRowStore.laterKey];
    }
  }

  @override
  Future<void> writeLaterMark(String dateIso) async {
    _memory[SmallActionRowStore.laterKey] = dateIso;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SmallActionRowStore.laterKey, dateIso);
    } catch (_) {}
  }
}

/// Tests and screenshots: plan and reminder documents as plain maps, the
/// same field names and the same update maps as Firestore (merge).
class InMemorySmallActionRowStore implements SmallActionRowStore {
  /// `action_plans/{id}` documents.
  final Map<String, Map<String, dynamic>> planDocs = {};

  /// `reminders/{id}` documents.
  final Map<String, Map<String, dynamic>> reminderDocs = {};

  String? laterMark;

  /// Clock for the server-time fields (tests).
  DateTime Function() clock = DateTime.now;

  final _changes = StreamController<List<ActionPlan>>.broadcast();
  int _reminderSeq = 0;

  List<ActionPlan> get _plans => [
        for (final e in planDocs.entries) ActionPlan.fromMap(e.key, e.value),
      ];

  ActionPlan plan(String id) => ActionPlan.fromMap(id, planDocs[id]!);

  /// A plan saved at [createdAt] with the follow-up reminder the planners
  /// queue (saved + 24 h) unless [withReminder] is false.
  void addPlan(
    String id, {
    required String action,
    required DateTime createdAt,
    String arm = 'A',
    bool withReminder = true,
  }) {
    planDocs[id] = {
      ...ActionPlan(
        action: action,
        whenText: '上晝',
        whereText: '',
        whoWith: '',
        fallback: '',
        armCode: arm,
        createdAt: createdAt,
      ).toMap(),
      'createdAt': createdAt.toIso8601String(),
    };
    if (withReminder) {
      _addReminder(HomeSmallAction.followUpRequest(
        planId: id,
        action: action,
        fireAt: createdAt.add(const Duration(hours: 24)),
      ).fireAt, id);
    }
    _emit();
  }

  void _addReminder(DateTime fireAt, String planId,
      {Map<String, dynamic> extra = const {}}) {
    _reminderSeq++;
    reminderDocs['r$_reminderSeq'] = {
      'kind': 'm7_followup',
      'fireAt': fireAt.toIso8601String(),
      'linkedDocId': planId,
      'delivered': false,
      ...extra,
    };
  }

  /// Reminders of [planId], oldest first.
  List<Map<String, dynamic>> remindersOf(String planId) => [
        for (final r in reminderDocs.values)
          if (r['linkedDocId'] == planId) r,
      ];

  /// The server sent [planId]'s reminders (delivered).
  void deliverReminders(String planId) {
    for (final r in remindersOf(planId)) {
      r['delivered'] = true;
      r['dispatchStatus'] = 'sent';
    }
  }

  void _emit() => _changes.add(_plans);

  List<PlanReminder> _unsent(String planId) => [
        for (final e in reminderDocs.entries)
          if (e.value['linkedDocId'] == planId &&
              e.value['delivered'] == false &&
              e.value['kind'] == 'm7_followup')
            PlanReminder(
              id: e.key,
              fireAt: e.value['fireAt'] as String?,
              dispatchStatus: e.value['dispatchStatus'] as String?,
            ),
      ];

  void _apply(List<PlanReminderOp> ops) {
    for (final op in ops) {
      switch (op.kind) {
        case PlanReminderOpKind.move:
          reminderDocs[op.id]!
            ..['fireAt'] = op.to
            ..['movedFromFireAt'] = op.from
            ..['movedBy'] = HomeSmallAction.movedBy;
        case PlanReminderOpKind.delete:
          reminderDocs.remove(op.id);
        case PlanReminderOpKind.create:
          _addReminder(op.request!.fireAt, op.request!.linkedDocId!,
              extra: {'movedBy': HomeSmallAction.movedBy});
      }
    }
  }

  void _merge(String id, Map<String, dynamic> update,
      {List<String> serverTimes = const []}) {
    final data = Map<String, dynamic>.of(update);
    final entry = data.remove(HomeSmallAction.logEntryKey);
    final doc = planDocs[id]!..addAll(data);
    for (final k in serverTimes) {
      doc[k] = clock().toIso8601String();
    }
    if (entry != null) {
      doc['homeRowLog'] = [...(doc['homeRowLog'] as List? ?? const []), entry];
    }
  }

  @override
  Stream<List<ActionPlan>> plans(String uid) async* {
    yield _plans;
    yield* _changes.stream;
  }

  @override
  Future<void> markDone(String uid, ActionPlan plan, DateTime now) async {
    _merge(plan.id!, HomeSmallAction.doneUpdate(now),
        serverTimes: ['followedUpAt', 'homeRowAnsweredAt']);
    _apply(HomeSmallAction.reminderOpsAfterDone(_unsent(plan.id!)));
    _emit();
  }

  @override
  Future<HomeSmallActionPostpone> postpone(
      String uid, ActionPlan plan, DateTime now) async {
    final p = HomeSmallAction.postpone(plan, now);
    _merge(plan.id!, HomeSmallAction.postponeUpdate(p, now),
        serverTimes: ['homeRowAnsweredAt']);
    _apply(
        HomeSmallAction.reminderOpsAfterPostpone(plan, p, _unsent(plan.id!)));
    _emit();
    return p;
  }

  @override
  Future<String?> readLaterMark() async => laterMark;

  @override
  Future<void> writeLaterMark(String dateIso) async => laterMark = dateIso;
}

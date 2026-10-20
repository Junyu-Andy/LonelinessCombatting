/// 1020m 第二节 — page 1's small-action row in 「今日要做嘅事」
/// (`HomeSmallActionRow`; decision 0064).  Which line the row shows and
/// what 「做咗」 / 「改日」 write, as plain data, so it is tested without
/// Firestore.  [ActionPlanRepository] writes these maps; the row reads
/// [resolve].  Both arms identical; nothing here calls a model.
///
/// A plan's day ("計劃日期"): plans have no date field — 幾時 is free text
/// (「聽朝」) or 上晝／下晝／晚上.  The one concrete day the App has is its
/// follow-up reminder, queued for saved + 24 h, whose push says
/// 「你今日有個小計劃」.  So a plan is "for today" on the Hong Kong day of
/// saved + 24 h, or on [ActionPlan.homeRowDueDate] once 「改日」 moved it.
///
/// 「改日」: the first press moves the plan to tomorrow (same time of day:
/// its unsent reminder moves to the same clock time tomorrow; if it had
/// already gone out, a new one is queued for tomorrow).  A second press
/// (the next day) does not move it again: its reminder is dropped, and from
/// the day after the row asks 「今日想做啲咩小行動？」 again.  The plan is
/// never deleted and keeps no `outcome`, so it stays in 「我嘅計劃」.
library;

import '../../../core/reminders/reminder_service.dart';
import '../../today/data/mood_recorder.dart';
import 'action_plan.dart';

/// What the row shows.
enum HomeSmallActionView {
  /// 「今日想做啲咩小行動？」 + 「遲啲先」.
  ask,

  /// 「今日計劃：{…}」 + 「做咗」「改日」.
  plan,

  /// 「今日計劃：{…}」 with a tick (做咗 today).
  done,

  /// Nothing (改日 today, or 遲啲先 within 3 days).
  hidden,
}

class HomeSmallActionState {
  const HomeSmallActionState(this.view, [this.plan]);

  final HomeSmallActionView view;

  /// The plan shown ([HomeSmallActionView.plan] / [HomeSmallActionView.done]).
  final ActionPlan? plan;

  /// `rowState` of the `home_small_action_shown` usage event.
  String get rowState => view.name;

  @override
  bool operator ==(Object other) =>
      other is HomeSmallActionState &&
      other.view == view &&
      other.plan?.id == plan?.id;

  @override
  int get hashCode => Object.hash(view, plan?.id);

  @override
  String toString() => 'HomeSmallActionState(${view.name}, ${plan?.id})';
}

/// What one 「改日」 does.
class HomeSmallActionPostpone {
  const HomeSmallActionPostpone({
    required this.forDate,
    required this.laterCount,
    this.movedTo,
  });

  /// The day 「改日」 was pressed (the plan's day).
  final String forDate;

  /// 「改日」 presses so far, this one included.
  final int laterCount;

  /// The new day when this press moved the plan; null on the second press.
  final String? movedTo;

  bool get moved => movedTo != null;
}

/// One queued `m7_followup` reminder of a plan, as read from
/// `users/{uid}/reminders` (`delivered == false`).
class PlanReminder {
  const PlanReminder({
    required this.id,
    required this.fireAt,
    this.dispatchStatus,
  });

  final String id;

  /// As stored: the App's local ISO string (no offset = Hong Kong time).
  final String? fireAt;

  /// Set by the server (functions/reminders.js); null = still waiting.
  final String? dispatchStatus;

  /// The server will still send it: no status yet, or a retry.
  bool get waiting =>
      dispatchStatus == null || dispatchStatus!.startsWith('retry');
}

enum PlanReminderOpKind { move, delete, create }

/// One change to a plan's reminders.
class PlanReminderOp {
  const PlanReminderOp.move(String this.id,
      {required String this.from, required String this.to})
      : kind = PlanReminderOpKind.move,
        request = null;
  const PlanReminderOp.delete(String this.id)
      : kind = PlanReminderOpKind.delete,
        from = null,
        to = null,
        request = null;
  const PlanReminderOp.create(ReminderRequest this.request)
      : kind = PlanReminderOpKind.create,
        id = null,
        from = null,
        to = null;

  final PlanReminderOpKind kind;
  final String? id;

  /// move: the old and the new `fireAt`.
  final String? from;
  final String? to;

  /// create: the new reminder (same shape the planner queues).
  final ReminderRequest? request;

  @override
  String toString() => switch (kind) {
        PlanReminderOpKind.move => 'move($id $from → $to)',
        PlanReminderOpKind.delete => 'delete($id)',
        PlanReminderOpKind.create => 'create(${request!.fireAt})',
      };
}

class HomeSmallAction {
  HomeSmallAction._();

  static const String statusDone = 'done';
  static const String statusLater = 'later';

  /// `followUpSource` of an `outcome` set from the row (3)(a).
  static const String source = 'home_row';

  /// Reminders the row moved or queued carry `movedBy: home_row`.
  static const String movedBy = 'home_row';

  /// How many 「改日」 presses move the plan: the first only.
  static const int maxMoves = 1;

  /// 「遲啲先」: hidden on the day pressed and the next two; back on day 4.
  static const int snoozeDays = 3;

  /// Key of the one log entry in [doneUpdate] / [postponeUpdate]; the
  /// repository appends it to the plan's `homeRowLog` array.
  static const String logEntryKey = 'homeRowLogEntry';

  /// Hong Kong calendar day (yyyy-MM-dd) of [t].
  static String dayOf(DateTime t) => MoodRecorder.dateIsoFor(t);

  static (int, int, int) _ymd(String dateIso) {
    final p = dateIso.split('-');
    return (int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// [dateIso] + [days] calendar days.
  static String addDays(String dateIso, int days) {
    final (y, m, d) = _ymd(dateIso);
    final t = DateTime.utc(y, m, d + days);
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  /// The plan's day: [ActionPlan.homeRowDueDate] once moved, else the Hong
  /// Kong day of its follow-up reminder (saved + 24 h).
  static String dueDateOf(ActionPlan p) =>
      p.homeRowDueDate ?? dayOf(p.createdAt.add(const Duration(hours: 24)));

  /// 「遲啲先」 pressed on [laterMark]: hidden that day and the next two.
  static bool snoozed(String? laterMark, String today) {
    if (laterMark == null || laterMark.isEmpty) return false;
    return today.compareTo(laterMark) >= 0 &&
        today.compareTo(addDays(laterMark, snoozeDays)) < 0;
  }

  /// The row for [now]:
  ///   1. a plan answered on the row today → its tick (做咗) or nothing
  ///      (改日): one answer a day, never asked again that day;
  ///   2. else the oldest plan for today without an outcome → 「今日計劃」;
  ///      one already answered on the 「件事點呀？」 page → its tick
  ///      (happened) or nothing;
  ///   3. else 「今日想做啲咩小行動？」, unless 「遲啲先」 is in its 3 days.
  /// Soft-deleted plans never show.
  static HomeSmallActionState resolve(Iterable<ActionPlan> plans,
      DateTime now,
      {String? laterMark}) {
    final today = dayOf(now);
    final live = plans.where((p) => p.deletedAt == null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final p in live) {
      if (p.homeRowAnsweredDate == today) {
        return p.homeRowStatus == statusDone
            ? HomeSmallActionState(HomeSmallActionView.done, p)
            : const HomeSmallActionState(HomeSmallActionView.hidden);
      }
    }
    final dueToday = [
      for (final p in live)
        if (dueDateOf(p) == today) p,
    ];
    for (final p in dueToday) {
      if (p.outcome == null) {
        return HomeSmallActionState(HomeSmallActionView.plan, p);
      }
    }
    for (final p in dueToday) {
      return p.outcome == FollowUpOutcome.happened
          ? HomeSmallActionState(HomeSmallActionView.done, p)
          : const HomeSmallActionState(HomeSmallActionView.hidden);
    }
    if (snoozed(laterMark, today)) {
      return const HomeSmallActionState(HomeSmallActionView.hidden);
    }
    return const HomeSmallActionState(HomeSmallActionView.ask);
  }

  /// 「做咗」: the existing follow-up answer (`outcome: happened`, as the
  /// 「件事點呀？」 page writes it) with `followUpSource: home_row`, and the
  /// row's status fields.  The repository adds `followedUpAt` and
  /// `homeRowAnsweredAt` (server time) and appends [logEntryKey] to
  /// `homeRowLog`.  No text.
  static Map<String, dynamic> doneUpdate(DateTime now) {
    final today = dayOf(now);
    return {
      'outcome': FollowUpOutcome.happened.name,
      'followUpSource': source,
      'homeRowStatus': statusDone,
      'homeRowAnsweredDate': today,
      logEntryKey: {
        'status': statusDone,
        'atLocal': now.toIso8601String(),
        'forDate': today,
        'movedTo': null,
      },
    };
  }

  /// 「改日」 on [plan] at [now].
  static HomeSmallActionPostpone postpone(ActionPlan plan, DateTime now) {
    final today = dayOf(now);
    final moves = plan.homeRowLaterCount < maxMoves;
    return HomeSmallActionPostpone(
      forDate: today,
      laterCount: plan.homeRowLaterCount + 1,
      movedTo: moves ? addDays(today, 1) : null,
    );
  }

  /// 「改日」: status only — `later`, the day, the count, the new day when
  /// it moved.  No `outcome` (the plan stays in 「我嘅計劃」).  The
  /// repository adds `homeRowAnsweredAt` and appends [logEntryKey].
  static Map<String, dynamic> postponeUpdate(
      HomeSmallActionPostpone p, DateTime now) {
    return {
      'homeRowStatus': statusLater,
      'homeRowAnsweredDate': p.forDate,
      'homeRowLaterCount': p.laterCount,
      if (p.moved) 'homeRowDueDate': p.movedTo,
      logEntryKey: {
        'status': statusLater,
        'atLocal': now.toIso8601String(),
        'forDate': p.forDate,
        'movedTo': p.movedTo,
      },
    };
  }

  /// The Hong Kong day of a stored `fireAt` (the App writes the phone's
  /// local time, which is Hong Kong time; functions/reminders.js reads a
  /// string without an offset the same way).
  static String? fireAtDay(String? fireAt) {
    final t = fireAt == null ? null : DateTime.tryParse(fireAt);
    return t == null ? null : dayOf(t);
  }

  static int _daysBetween(String from, String to) {
    final (y1, m1, d1) = _ymd(from);
    final (y2, m2, d2) = _ymd(to);
    return DateTime.utc(y2, m2, d2).difference(DateTime.utc(y1, m1, d1)).inDays;
  }

  /// [fireAt] moved to the Hong Kong day [dateIso]: whole days, so the
  /// same clock time, in the same format (local, or UTC with `Z`).
  static String fireAtOnDay(String fireAt, String dateIso) {
    final t = DateTime.parse(fireAt);
    final n = _daysBetween(dayOf(t), dateIso);
    final moved = t.isUtc
        ? DateTime.utc(t.year, t.month, t.day + n, t.hour, t.minute,
            t.second, t.millisecond)
        : DateTime(t.year, t.month, t.day + n, t.hour, t.minute, t.second,
            t.millisecond);
    return moved.toIso8601String();
  }

  /// 「做咗」: the plan's unsent reminders go (as the 「件事點呀？」 page
  /// does), so no push asks again; the server also skips any reminder of
  /// a plan with an `outcome`.
  static List<PlanReminderOp> reminderOpsAfterDone(
          List<PlanReminder> unsent) =>
      [for (final r in unsent) PlanReminderOp.delete(r.id)];

  /// 「改日」: moved → each waiting reminder of the day goes to the same
  /// clock time on the new day; when none is waiting (already sent), one
  /// is queued for the new day at the plan's own reminder time (saved +
  /// 24 h).  Not moved (second press) → its unsent reminders go.
  static List<PlanReminderOp> reminderOpsAfterPostpone(ActionPlan plan,
      HomeSmallActionPostpone p, List<PlanReminder> unsent) {
    final to = p.movedTo;
    if (to == null) {
      return [for (final r in unsent) PlanReminderOp.delete(r.id)];
    }
    final ops = <PlanReminderOp>[];
    var onNewDay = false;
    for (final r in unsent) {
      if (!r.waiting) continue;
      final day = fireAtDay(r.fireAt);
      if (day == null) continue;
      if (day.compareTo(to) >= 0) {
        onNewDay = true;
        continue;
      }
      ops.add(PlanReminderOp.move(r.id,
          from: r.fireAt!, to: fireAtOnDay(r.fireAt!, to)));
      onNewDay = true;
    }
    if (!onNewDay) {
      final first =
          plan.createdAt.add(const Duration(hours: 24)).toIso8601String();
      ops.add(PlanReminderOp.create(followUpRequest(
        planId: plan.id,
        action: plan.action,
        fireAt: DateTime.parse(fireAtOnDay(first, to)),
      )));
    }
    return ops;
  }

  /// The follow-up reminder exactly as the planners queue it
  /// (action_loop_arm_a_page / action_loop_arm_b_page).
  static ReminderRequest followUpRequest({
    required String? planId,
    required String action,
    required DateTime fireAt,
  }) =>
      ReminderRequest(
        kind: 'm7_followup',
        fireAt: fireAt,
        titleZh: '件事點呀？',
        titleEn: 'How did it go?',
        bodyZh: '你之前計劃做：$action。',
        bodyEn: 'Your plan: $action.',
        linkedDocId: planId,
      );
}

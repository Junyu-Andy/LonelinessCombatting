# 两组共用：推送文案和时间表

**结论**：真正会发到手机的推送只有 3 种，全部由服务器发出，两组相同，只有中文，标题都是「陪住」：

| 推送 | 时间（香港时间） | 发给谁 | 正文 |
|---|---|---|---|
| 每日情绪提醒 `dailyMoodReminder` | 周一至周六 19:00 | 所有装了 app 的设备（topic `all`） | 见第 1 节 |
| 每周问卷提醒 `weeklySurveyReminder` | 周日 20:00 | 同上 | 见第 1 节 |
| 第二周推送 `week2Push` | 每天 10:00 检查，入组第 14–16 天发一次 | 该用户的设备 | 见第 1 节 |

另外：测试人员可以手动发测试推送（标题「陪住（測試）」，正文同上）；
每周孤独感问卷 `weeklyLonelinessProbe`（周日 09:00）**不发推送**，而且 Phase A/B 默认关闭；
App 本地没有用本地通知；行动计划的 24 小时提醒只写进 Firestore，**目前没有任何代码把它发出去**（第 3 节）。
App 内横幅（首页的问卷提示等）不是推送，文字也放在第 4 节。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 服务器推送种类 | 3 | `functions/index.js` 中 `admin.messaging().send` 发送的正文：daily_mood_reminder、weekly_survey_reminder、w2_push（`sendTestPush` 复用同 3 条） |
| 排程任务（含不推送的） | 6 | `functions/index.js` 中 `onSchedule(` 个数：dailyMoodReminder、weeklySurveyReminder、week2Push、weeklyLonelinessProbe、blindedDataExport、memorySweep；后 3 个不发推送 |

## 1. 服务器推送（`functions/index.js`）

发送方式和频率约定：

来源：`functions/index.js` 第 1276–1313 行

```js
  },
);

// ---------------------------------------------------------------------------
// T2 — FCM "doorbell" reminders (Dev TestWeek).
//
// Design: the notification is ONLY a doorbell. Tapping it opens the app; the
// in-app `PendingPromptsBanner` owns all routing. No deep links in v1.
//
// Delivery is to the broadcast topic "all" (FcmService subscribes every
// signed-in device), so no per-token fan-out is needed. iOS/APNs is out of
// scope (T10 / Phase A).
//
// Frequency contract: ≤1/day. The daily mood reminder runs Mon–Sat 19:00
// HKT; Sunday's single push is the weekly-survey reminder at 20:00 HKT
// (when the Weekly PR banner is live), so the two never collide.
//
// Copy is gentle Cantonese, "想答先答" — never nagging, never guilt-tripping.
// ---------------------------------------------------------------------------

async function sendDoorbell(title, body, analyticsLabel) {
  // No explicit channelId: a missing channel suppresses the notification on
  // Android 8+. Relying on the firebase_messaging plugin's default channel
  // is the foolproof v1 doorbell. data.kind is for client-side analytics.
  const message = {
    topic: "all",
    notification: {title, body},
    android: {priority: "normal"},
    data: {kind: analyticsLabel},
  };
  try {
    const id = await admin.messaging().send(message);
    console.log(`doorbell sent (${analyticsLabel}): ${id}`);
  } catch (err) {
    console.error(`doorbell send failed (${analyticsLabel}):`, err.message);
  }
}

```

来源：`functions/index.js` 第 1445–1500 行

```js
exports.dailyMoodReminder = onSchedule(
  {
    schedule: "0 19 * * 1-6", // Mon–Sat 19:00 (Sunday handled by weekly)
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await sendDoorbell(
      "陪住",
      "今日過得點？得閒入嚟同我哋講兩句，想講先講，唔講都冇所謂。",
      "daily_mood_reminder",
    );
  },
);

exports.weeklySurveyReminder = onSchedule(
  {
    schedule: "0 20 * * 0", // Sunday 20:00, when the Weekly PR banner is live
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await sendDoorbell(
      "陪住",
      "今個禮拜過得點？得閒入嚟答幾條，想答先答，唔想都冇問題。",
      "weekly_survey_reminder",
    );
    // Phase A L-1 — `weekly_pr_pushed` per participant.  The doorbell is a
    // topic broadcast, so per-device receipt is unknown; this records that
    // the push was issued for the account (testers excluded).
    try {
      const db = admin.firestore();
      const usersSnap = await db.collection("users").get();
      const weekIso = isoWeekLabel(new Date());
      const writes = [];
      for (const userDoc of usersSnap.docs) {
        const data = userDoc.data() || {};
        if (data.isTester === true) continue;
        writes.push(userDoc.ref.collection("events").add({
          name: "weekly_pr_pushed",
          params: {weekIso, channel: "fcm_topic_all"},
          source: "cf_weeklySurveyReminder",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }));
      }
      await Promise.all(writes);
      console.log(`weekly_pr_pushed recorded for ${writes.length} users`);
    } catch (err) {
      console.error("weekly_pr_pushed record failed:", err.message);
    }
  },
);

// ISO-8601 week label (e.g. 2026-W37) in HKT, matching the client's
```

第二周推送参数来源：

来源：`functions/index.js` 第 1510–1546 行

```js
}

// ---------------------------------------------------------------------------
// M-4 (Phase A baseline 2026-09) — Week 2 push.
//
// Daily 10:00 HKT: for every non-tester user whose enrolment day index is
// inside [w2DayOffset, w2DayOffset + w2WindowDays) and who has not yet
// received the push, send a per-device notification (fcm_tokens) and mark
// `w2PushSentAt` on the user doc + a `w2_push_sent` event.  Parameters
// come from `app_config/phase_a` (same doc the client reads) with the spec
// defaults (14 / 3) as fallback.  The in-app banner owns the actual DJG-ES
// + Agent Differentiation routing; this is only the doorbell.
// ---------------------------------------------------------------------------

async function phaseAConfig(db) {
  const defaults = {w2DayOffset: 14, w2WindowDays: 3};
  try {
    const snap = await db.doc("app_config/phase_a").get();
    return {...defaults, ...(snap.exists ? snap.data() : {})};
  } catch (err) {
    return defaults;
  }
}

function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
}

function daysBetweenHk(fromIso, toIso) {
  const a = new Date(`${fromIso}T00:00:00Z`);
  const b = new Date(`${toIso}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

// ---------------------------------------------------------------------------
// assignArm — server-side RCT arm assignment (functions/arm.js).  The app
// calls this right after creating the profile (and again on login while the
```

来源：`functions/index.js` 第 1567–1648 行

```js
exports.week2Push = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    const db = admin.firestore();
    const cfg = await phaseAConfig(db);
    const today = hkDateKey(new Date());
    const usersSnap = await db.collection("users").get();
    let sent = 0;
    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data() || {};
      if (data.isTester === true) continue;
      if (data.w2PushSentAt) continue;
      const createdRaw = data.createdAt;
      if (!createdRaw) continue;
      const createdIso = typeof createdRaw === "string" ?
        createdRaw.slice(0, 10) :
        (createdRaw.toDate ? hkDateKey(createdRaw.toDate()) : null);
      if (!createdIso) continue;
      // 1-based enrolment day (day 1 = signup date), same as the client's
      // enrolmentDay(): 「入組第 14 天」 == day 14.
      const day = daysBetweenHk(createdIso, today) + 1;
      if (day < cfg.w2DayOffset || day >= cfg.w2DayOffset + cfg.w2WindowDays) {
        continue;
      }
      const tokensSnap = await userDoc.ref.collection("fcm_tokens").get();
      const tokens = tokensSnap.docs
          .map((t) => (t.data() || {}).token)
          .filter((t) => typeof t === "string" && t.length > 0);
      let delivered = 0;
      for (const token of tokens) {
        try {
          await admin.messaging().send({
            token,
            notification: {
              title: "陪住",
              body: "入嚟兩個禮拜喇，有幾條短問題想問下你。得閒先答，唔急。",
            },
            android: {priority: "normal"},
            data: {kind: "w2_push"},
          });
          delivered++;
        } catch (err) {
          console.warn(`week2Push token send failed for ${userDoc.id}: ${err.message}`);
        }
      }
      await userDoc.ref.set({
        w2PushSentAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await userDoc.ref.collection("events").add({
        name: "w2_push_sent",
        params: {enrolmentDay: day, tokens: tokens.length, delivered},
        source: "cf_week2Push",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }
    console.log(`week2Push: ${sent} users notified`);
  },
);

// ---------------------------------------------------------------------------
// Tester-only: send one of the real doorbells to the caller's own devices
// (2026-09-23).  Lets a tester verify delivery, copy and the
// notification_opened event without waiting for the cron.
//
// Guard: caller must be signed in AND `users/{uid}.isTester == true`.
// `delaySeconds` (0–45) gives the tester time to put the app in the
// background — Android does not display a system notification for FCM
// messages received while the app is in the foreground.
// iOS devices will not receive anything until APNs is configured.
// ---------------------------------------------------------------------------

const _TEST_PUSH_COPY = {
  daily_mood_reminder: "今日過得點？得閒入嚟同我哋講兩句，想講先講，唔講都冇所謂。",
  weekly_survey_reminder: "今個禮拜過得點？得閒入嚟答幾條，想答先答，唔想都冇問題。",
  w2_push: "入嚟兩個禮拜喇，有幾條短問題想問下你。得閒先答，唔急。",
};
```

## 2. 每周孤独感问卷排程（不发推送）

来源：`functions/index.js` 第 1040–1095 行

```js
// C.1 — Weekly loneliness probe (Sprint 3.3).
//
// Cron: every Sunday 09:00 HKT (Asia/Hong_Kong; no DST so the wall time is
// stable year-round, but we set the tz explicitly to lock the contract).
//
// Phase A gate: writes to a per-user `pending_loneliness_probes/{uid}` doc
// that the client polls on app open.  An FCM push is sent only when the
// `weeklyProbeEnabled` feature flag is true on the user's profile —
// in Phase A this flag is false for every user (kill switch is the default
// state), so the cron emits the doc but the user never sees the probe.
//
// The probe itself: 1-item slider (UCLA-3 short form / single-item
// loneliness scale), captured client-side and written to
// `users/{uid}/loneliness_probes/{auto-id}`.
// ---------------------------------------------------------------------------

exports.weeklyLonelinessProbe = onSchedule(
  {
    schedule: "0 9 * * SUN",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 1,
  },
  async (_event) => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();
    const writes = [];
    const now = admin.firestore.FieldValue.serverTimestamp();
    const todayKey = new Date()
        .toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data() || {};
      const enabled = data.weeklyProbeEnabled === true;
      if (!enabled) continue;
      // B.10 — respect 今日休息.  If the user activated quiet-today
      // (HK local day matches today), skip enqueueing the probe.
      const quietRaw = data.quietTodayActivatedAt;
      if (quietRaw) {
        const quietDate = typeof quietRaw === "string" ?
          quietRaw.slice(0, 10) :
          (quietRaw.toDate ? quietRaw.toDate()
              .toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"}) :
              null);
        if (quietDate === todayKey) continue;
      }
      writes.push(
        db.collection("pending_loneliness_probes").doc(userDoc.id).set({
          uid: userDoc.id,
          dueAt: now,
          status: "pending",
        }, {merge: true}),
      );
    }
    await Promise.all(writes);
    console.log(`weeklyLonelinessProbe: enqueued ${writes.length} probes`);
  },
```

## 3. 行动计划 24 小时提醒（只写入，未发送）

来源：`lib/core/reminders/reminder_service.dart` 第 1–35 行

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/auth/data/user_profile.dart';

/// Spec §M7: "Plan saved with a follow-up reminder for the next session
/// after the planned time." Spec §Adherence: "Reminders configurable by
/// user; respect quiet hours."
///
/// B.10 (Sprint 4 fix): when the user has activated 今日休息 today, the
/// schedule API skips writing the reminder doc entirely.  This is the
/// "dignified pause" behaviour from Product Overview §3.4 — reminders
/// must be suppressed for the day, not merely flagged.  Reminders whose
/// `fireAt` is on a future day still go through, since 今日休息 only
/// covers the current local day.
///
/// This file holds the *interface* between app code and a future local-
/// notification implementation. Concrete delivery (Android channel + iOS
/// permission prompt + `flutter_local_notifications` wire-up) is left
/// for a later sprint so the build doesn't gain a heavy native
/// dependency before we're ready to test on a real device.
///
/// For now the service:
///   - Persists each reminder to `users/{uid}/reminders/{id}` so that
///     when the device-side scheduler comes online it can read the
///     queue and register OS-level alarms.
///   - Skips delivery silently in guest mode or when Firebase is down.
abstract class ReminderService {
  /// Schedule a reminder for [uid].  When [profile] is non-null and
  /// `profile.isQuietToday == true`, requests for **today** are
  /// suppressed (B.10).  Returns null when suppressed.
  Future<String?> schedule({
    required String uid,
    required ReminderRequest request,
    UserProfile? profile,
  });
```

Hybrid 组：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 248–266 行

```dart
      // record the intent.
      final reminders = FirestoreReminderQueue(available: auth.available);
      await reminders.schedule(
        uid: profile.uid,
        // B.10 — pass profile so 今日休息 can suppress same-day reminders.
        profile: profile,
        request: ReminderRequest(
          kind: 'm7_followup',
          fireAt: DateTime.now().add(const Duration(hours: 24)),
          titleZh: '件事點呀？',
          titleEn: 'How did it go?',
          bodyZh: '你之前計劃做：$_action。',
          bodyEn: 'Your plan: $_action.',
          linkedDocId: planId,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
```

规则组：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_b_page.dart` 第 84–98 行

```dart
      if (planId != null) {
        final reminders = FirestoreReminderQueue(available: auth.available);
        await reminders.schedule(
          uid: profile.uid,
          profile: profile, // B.10 — 今日休息 suppression
          request: ReminderRequest(
            kind: 'm7_followup',
            fireAt: DateTime.now().add(const Duration(hours: 24)),
            titleZh: '件事點呀？',
            titleEn: 'How did it go?',
            bodyZh: '你之前計劃做：${_actionCtrl.text.trim()}。',
            bodyEn: 'Your plan: ${_actionCtrl.text.trim()}.',
            linkedDocId: planId,
          ),
        );
```

## 4. 时间参数和 App 内提示横幅

来源：`lib/core/config/phase_a_config.dart`（整个文件，共 125 行，SHA-256 `38fc2980cc264258…`）

```dart
/// Phase A baseline runtime parameters (Dev spec v1 2026-09, §M-7 / §M-1 /
/// §M-2 / §M-4 / §P-1 / §8).
///
/// Every value the PI may still change before participant 1 is enrolled
/// lives here with the spec default, so the decision lands as a config
/// edit rather than a code change.  Two layers:
///
///   1. Compile-time defaults (this file) — always available, used in
///      tests and when Firestore is unreachable.
///   2. Optional remote override — `app_config/phase_a` Firestore document
///      (read-only for clients; written by the research team from the
///      console).  Any key present there replaces the default on the next
///      app start.  Missing keys keep the default.
///
/// Call [PhaseAConfig.load] once at startup; read via [PhaseAConfig.current].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PhaseAConfig {
  const PhaseAConfig({
    this.sessionIdleTimeoutMin = 10,
    this.briefPRMinTurns = 2,
    this.briefPRItemCount = 4,
    this.weeklyPrPushHour = 20,
    this.weeklyPrCloseWeekday = DateTime.tuesday,
    this.w2DayOffset = 14,
    this.w2WindowDays = 3,
    this.week1NudgeDays = const [3, 6],
  });

  /// M-7 — agent session ends after this many minutes without a user
  /// message (`endReason = timeout`).
  final int sessionIdleTimeoutMin;

  /// M-1 — Brief PR is shown only when the session had at least this many
  /// user turns (fallback turns excluded).
  final int briefPRMinTurns;

  /// M-1 — 4 (with insensitivity item) or 3.  PI decision pending; 4 is the
  /// spec default.
  final int briefPRItemCount;

  /// M-2 — Sunday hour (HKT, 24 h) at which the Weekly PR window opens and
  /// the FCM doorbell fires.
  final int weeklyPrPushHour;

  /// M-2 — weekday (Dart constant, Monday = 1) whose 23:59 closes the
  /// Weekly PR window.  Tuesday per spec.
  final int weeklyPrCloseWeekday;

  /// M-4 — days after enrolment for the Week 2 push (DJG-ES + Agent
  /// Differentiation).
  final int w2DayOffset;

  /// M-4 — window (days) during which the Week 2 battery stays open.
  final int w2WindowDays;

  /// P-1 — enrolment days on which the "you haven't tried {agent}" nudge
  /// may show.
  final List<int> week1NudgeDays;

  static PhaseAConfig _current = const PhaseAConfig();

  /// The active configuration (defaults until [load] merges an override).
  static PhaseAConfig get current => _current;

  /// Test / tooling hook.
  @visibleForTesting
  static set current(PhaseAConfig value) => _current = value;

  /// Firestore document holding overrides.  Read-only for clients.
  static const String remotePath = 'app_config/phase_a';

  /// Merge overrides from Firestore.  Never throws; on any failure the
  /// defaults stay in force.
  static Future<PhaseAConfig> load({bool available = true}) async {
    if (!available) return _current;
    try {
      // Bounded: a cold start on a flaky network must not wait on this read;
      // the defaults are always safe and the next launch retries.
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data != null) _current = fromMap(data, base: _current);
    } catch (e) {
      if (kDebugMode) debugPrint('[PhaseAConfig] remote load skipped: $e');
    }
    return _current;
  }

  /// Pure merge used by [load] and tests.
  static PhaseAConfig fromMap(Map<String, dynamic> map,
      {PhaseAConfig base = const PhaseAConfig()}) {
    int i(String k, int d) => (map[k] as num?)?.toInt() ?? d;
    final nudgeRaw = map['week1NudgeDays'];
    final nudge = nudgeRaw is List
        ? nudgeRaw.whereType<num>().map((e) => e.toInt()).toList()
        : base.week1NudgeDays;
    return PhaseAConfig(
      sessionIdleTimeoutMin: i('sessionIdleTimeoutMin', base.sessionIdleTimeoutMin),
      briefPRMinTurns: i('briefPRMinTurns', base.briefPRMinTurns),
      briefPRItemCount: i('briefPRItemCount', base.briefPRItemCount).clamp(3, 4),
      weeklyPrPushHour: i('weeklyPrPushHour', base.weeklyPrPushHour),
      weeklyPrCloseWeekday: i('weeklyPrCloseWeekday', base.weeklyPrCloseWeekday),
      w2DayOffset: i('w2DayOffset', base.w2DayOffset),
      w2WindowDays: i('w2WindowDays', base.w2WindowDays),
      week1NudgeDays: nudge,
    );
  }

  Map<String, dynamic> toMap() => {
        'sessionIdleTimeoutMin': sessionIdleTimeoutMin,
        'briefPRMinTurns': briefPRMinTurns,
        'briefPRItemCount': briefPRItemCount,
        'weeklyPrPushHour': weeklyPrPushHour,
        'weeklyPrCloseWeekday': weeklyPrCloseWeekday,
        'w2DayOffset': w2DayOffset,
        'w2WindowDays': w2WindowDays,
        'week1NudgeDays': week1NudgeDays,
      };
}
```

每周问卷开放窗口：

来源：`lib/features/weekly_pr/data/weekly_pr_window.dart` 第 1–45 行

```dart
/// M-2 — Weekly PR window + referent rules (Phase A baseline 2026-09).
///
/// Pure functions (unit-tested) so the banner / trigger / Cloud Function
/// can agree on "which week is being rated" without touching Firestore.
///
/// Window: opens Sunday [PhaseAConfig.weeklyPrPushHour]:00 (HKT, the app's
/// wall clock) and closes at 23:59 on [PhaseAConfig.weeklyPrCloseWeekday]
/// (Tuesday).  The *rated week* is the ISO week whose Sunday opened the
/// window, i.e. Monday 00:00 → Sunday pushHour:00 of that week; sessions
/// between Sunday pushHour and midnight belong to the next rated week.
library;

import '../../../core/config/phase_a_config.dart';
import 'weekly_pr_response.dart';

class WeeklyPrWindow {
  WeeklyPrWindow._();

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday 00:00 of the ISO week containing [d].
  static DateTime mondayOf(DateTime d) =>
      _midnight(d).subtract(Duration(days: d.weekday - DateTime.monday));

  /// True while the Weekly PR entry is live on the home page.
  static bool isOpen(DateTime now, {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    if (now.weekday == DateTime.sunday) return now.hour >= c.weeklyPrPushHour;
    // Monday … close weekday (inclusive, all day).
    return now.weekday >= DateTime.monday && now.weekday <= c.weeklyPrCloseWeekday;
  }

  /// Monday 00:00 of the week being rated by a window that is open at
  /// [now] — or, when the window is closed, of the week whose window most
  /// recently closed (used for the missed record).
  static DateTime ratedWeekMonday(DateTime now, {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    if (now.weekday == DateTime.sunday && now.hour >= c.weeklyPrPushHour) {
      return mondayOf(now);
    }
    // Any other moment refers to the week that ended on the most recent
    // Sunday (Mon/Tue inside the window; Wed–Sun-before-push after it).
    return mondayOf(now).subtract(const Duration(days: 7));
  }

```

来源：`lib/core/scheduling/pending_prompts_service.dart` 第 60–135 行

```dart
  PendingPromptsService({
    FirebaseFirestore? db,
    WeeklyPrTrigger? weeklyPrTrigger,
    this.analytics,
  })  : _db = db ?? FirebaseFirestore.instance,
        _weeklyTrigger = weeklyPrTrigger ?? WeeklyPrTrigger(db: db);

  final FirebaseFirestore _db;
  final WeeklyPrTrigger _weeklyTrigger;
  final AnalyticsService? analytics;

  Future<PendingPrompts> shouldShowOnHomeNow(
    String uid,
    UserProfile? profile, {
    DateTime? now,
  }) async {
    final t = now ?? AppClock.now();
    final cfg = PhaseAConfig.current;

    bool pgic = false;
    bool weeklyPr = false;
    String? weekIso;
    WeeklyPrAgentUsage? chosenAgent;

    final ratedMonday = WeeklyPrWindow.ratedWeekMonday(t, config: cfg);
    final ratedIso = WeeklyPrWindow.ratedWeekIso(ratedMonday);
    if (WeeklyPrWindow.isOpen(t, config: cfg)) {
      weekIso = ratedIso;
      final hasWeekly = await _weeklyTrigger.hasSubmittedThisWeek(uid, ratedIso);
      pgic = await _noPgicForWeek(uid, ratedMonday, ratedIso);
      if (!hasWeekly) {
        weeklyPr = true;
        chosenAgent = await _weeklyTrigger.referentUsageForRatedWeek(uid, ratedMonday);
      }
    } else if (WeeklyPrWindow.hasClosed(ratedMonday, t, config: cfg)) {
      // M-2 — window closed with nothing submitted → missed record (once).
      await _weeklyTrigger.recordMissedIfNeeded(
        uid: uid,
        arm: profile?.arm?.code ?? 'A',
        ratedMonday: ratedMonday,
        enrolledAt: profile?.createdAt,
        analytics: analytics,
      );
    }

    bool djgEsW2 = false;
    bool agentDiffW2 = false;
    bool agentDiffW4 = false;
    final createdAt = profile?.createdAt;
    if (createdAt != null) {
      // 1-based calendar day (「入組第 N 天」); mirrored in CF week2Push.
      final day = enrolmentDay(createdAt, t);
      final inW2Window =
          day >= cfg.w2DayOffset && day < cfg.w2DayOffset + cfg.w2WindowDays;
      if (inW2Window) {
        if (!await _hasDoc(uid, 'djg_es', 'timepoint', 'week2')) djgEsW2 = true;
        if (!await _hasDoc(uid, 'agent_diff', 'timepoint', 'week2')) agentDiffW2 = true;
      }
      if (day >= 28 && !await _hasDoc(uid, 'agent_diff', 'timepoint', 'week4')) {
        agentDiffW4 = true;
      }
    }

    return PendingPrompts(
      pgic: pgic,
      weeklyPr: weeklyPr,
      weeklyPrWeekIso: weekIso,
      weeklyPrAgent: chosenAgent,
      djgEsW2: djgEsW2,
      agentDiffW2: agentDiffW2,
      agentDiffW4: agentDiffW4,
    );
  }

  Future<bool> _noPgicForWeek(String uid, DateTime ratedMonday, String weekIso) async {
    try {
```

来源：`lib/features/today/presentation/widgets/pending_prompts_banner.dart` 第 75–200 行

```dart
  }

  /// Sunday weekly cycle (M-2): PGIC first (global impression), then the
  /// single-companion Weekly PR.  A week with no agent session asks PGIC
  /// only and writes a `no_referent` record for the 12 items.
  Future<void> _openWeeklyCycle() async {
    final p = _pending;
    if (p == null) return;
    if (p.pgic) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PgicPage(weekIso: p.weeklyPrWeekIso)),
      );
      if (!mounted) return;
    }
    if (p.weeklyPr) {
      final agent = p.weeklyPrAgent;
      if (agent != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WeeklyPrPage(agent: agent, weekIso: p.weeklyPrWeekIso),
          ),
        );
      } else {
        final profile = AppSettingsScope.read(context).profile;
        final isEn = Localizations.localeOf(context).languageCode == 'en';
        if (profile != null) {
          unawaited(WeeklyPrTrigger().writeNoReferent(
            profile.uid,
            Arm.of(context)?.code ?? 'A',
            weekIso: p.weeklyPrWeekIso,
          ));
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isEn
              ? "You didn't chat with a companion this week, so there's nothing more to rate."
              : '本週你冇同 companion 傾偈，今週唔使評夥伴。'),
          duration: const Duration(seconds: 4),
        ));
      }
      if (!mounted) return;
    }
    if (mounted) setState(() => _pending = null);
  }

  /// M-4 — Week 2 battery: DJG-ES then Agent Differentiation; logs
  /// `w2_completed` once both parts are done.
  Future<void> _openWeek2() async {
    final p = _pending;
    if (p == null) return;
    var djgDone = !p.djgEsW2;
    var diffDone = !p.agentDiffW2;
    if (p.djgEsW2) {
      final r = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const DjgEsPage(timepoint: 'week2')),
      );
      djgDone = r == true;
      if (!mounted) return;
    }
    if (p.agentDiffW2) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AgentDiffPage(wave: 2)),
      );
      diffDone = true; // the page persists on submit; skips are re-offered
      if (!mounted) return;
    }
    if (djgDone && diffDone) {
      unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.w2Completed));
    }
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _openAgentDiff(int wave) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AgentDiffPage(wave: wave)),
    );
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    if (p == null || !p.any) return const SizedBox.shrink();
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final tiles = <Widget>[];

    if (p.pgic || p.weeklyPr) {
      final noReferent = p.weeklyPr && p.weeklyPrAgent == null;
      tiles.add(_BannerTile(
        icon: Icons.sentiment_satisfied_outlined,
        title: isEn ? 'A quick weekly check-in' : '今週有個簡短嘅週評',
        // M-2 — a week with no companion session still asks PGIC; say so.
        subtitle: noReferent
            ? (isEn
                ? "You didn't chat with a companion this week — one quick question only."
                : '本週你冇同 companion 傾偈，淨係一條問題。')
            : (isEn
                ? 'Has your loneliness changed since last week?'
                : '同上週比較，孤單感有冇變化？'),
        onTap: _openWeeklyCycle,
      ));
    }

    if (p.w2Any) {
      tiles.add(_BannerTile(
        icon: Icons.assessment_outlined,
        title: isEn ? 'Week 2 questions' : '第 2 週問卷',
        subtitle: isEn
            ? 'A few minutes: how things feel, and the three companions.'
            : '幾分鐘：最近嘅感受，同三個夥伴嘅比較。',
        onTap: _openWeek2,
      ));
    }
    if (p.agentDiffW4) {
      tiles.add(_BannerTile(
        icon: Icons.assessment_outlined,
        title: isEn ? 'Companion assessment (Week 4)' : '夥伴評估（第 4 週）',
        subtitle: isEn
            ? 'A few minutes to compare the three companions.'
            : '請花幾分鐘比較三個夥伴。',
        onTap: () => _openAgentDiff(4),
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

```

来源：`lib/features/today/presentation/widgets/week1_nudge_banner.dart` 第 120–150 行

```dart
    final name = agentId == AgentRegistry.ahJanAhBakId
        ? AgentRegistry.ahJanAhBakName(variant, isEn: isEn)
        : AgentRegistry.byId(agentId).resolveVariant(null).let((v) => isEn ? v.displayNameEn : v.displayNameZh);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            children: [
              Icon(Icons.waving_hand_outlined,
                  size: 26, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEn
                      ? "You haven't chatted with $name yet — want to try?"
                      : '你仲未同 $name 傾過，想試下嗎？',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 18,
                    height: 1.4,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: isEn ? 'Dismiss' : '關閉',
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded),
              ),
```

来源：`lib/features/adherence/presentation/widgets/missed_checkin_banner.dart` 第 60–95 行

```dart
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.waving_hand_outlined,
                  size: 28,
                  color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn
                          ? "Haven't seen you in a few days"
                          : '幾日冇見你',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'A quick check-in only takes a minute. No pressure.'
                          : '快速 check-in 一分鐘就完。冇壓力。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
```

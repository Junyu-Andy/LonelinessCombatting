#!/usr/bin/env node
/**
 * tool/readonly_check_1020.js — READ-ONLY.  The production checks of
 * dev-tasks-1020 that need real data (the dev window has no access):
 *
 *   B(2)   「保留對話紀錄」: which PILOT / PB accounts have retention off
 *          (globally or for any companion).
 *   §1(2)  Action-plan follow-up pushes (dispatchReminders): per account,
 *          queued reminders by status, how many actually went out, the
 *          send errors, and which devices (platform) the account has.
 *          An iPhone push that FCM cannot hand to Apple fails with an
 *          error such as "messaging/third-party-auth-error" (no APNs key).
 *   H(3)   「今日休息」: how often it was switched on
 *          (quiet_today_activated events, quietTodayActivatedAt).
 *   1020b §3(3)  Voice transcription calls per research ID since 10/15
 *          (Hong Kong), from stt_usage — numbers only (ok / failed), never
 *          text or audio (the collection holds none).
 *   §1(4)  Brief PR invitations that expired without ever being shown,
 *          split by the page the session started from.  Sessions do not
 *          record that page, so it is inferred from the tab_view events
 *          (logged when the elder leaves a tab, with how long they stayed):
 *          the tab whose stay covers the session start.  The App opens on
 *          睇今日, so a session with no covering tab_view counts as
 *          "推断不到" rather than guessed.
 *
 * Writes nothing.  Prints research IDs, counts, dates and statuses only —
 * never an arm, a message text, a token or an e-mail address.  Does not
 * read randomization_sequences, randomization_state, arm_assignment_log
 * or any correction record (dev-tasks-1020 rule 6).
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/readonly_check_1020.js
 * Real project (service account in GOOGLE_APPLICATION_CREDENTIALS):
 *   NODE_PATH=functions/node_modules node tool/readonly_check_1020.js \
 *     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
 */
'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');

const PERIODS = ['B', 'PILOT'];
const AGENTS = ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'];
const PAGE_OF_TAB = {today: '第一页（睇今日）', talk: '第二页（搵人傾）'};

/** @return {?Date} */
function toDate(v) {
  if (!v) return null;
  if (typeof v.toDate === 'function') return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === 'string') {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/** Hong Kong date and time, "MM-DD HH:mm". */
function hk(d) {
  if (!d) return '—';
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString()
      .slice(5, 16).replace('T', ' ');
}

/** The participants: enrolments of Phase B (PB-) and the pilot run. */
async function participants(db) {
  const snap = await db.collection('enrollments').get();
  const out = [];
  for (const d of snap.docs) {
    const e = d.data() || {};
    if (PERIODS.indexOf(e.studyPeriod) < 0) continue;
    out.push({uid: d.id, researchId: e.researchId || '(无编号)',
      studyPeriod: e.studyPeriod});
  }
  out.sort((a, b) => a.researchId.localeCompare(b.researchId));
  return out;
}

/** B(2) */
async function retention(db, people) {
  console.log('\n=== B(2) 保留對話紀錄（false = 关掉） ===');
  let off = 0;
  for (const p of people) {
    const u = (await db.doc(`users/${p.uid}`).get()).data() || {};
    const c = u.consent || {};
    const by = c.transcriptRetentionByAgent || {};
    const perAgent = AGENTS.map((a) => {
      const v = Object.prototype.hasOwnProperty.call(by, a) ? by[a] :
        c.transcriptRetention;
      return `${a}=${v === true ? 'true' : String(v)}`;
    });
    const anyOff = c.transcriptRetention !== true ||
      AGENTS.some((a) => by[a] === false);
    if (anyOff) off++;
    console.log(`  ${anyOff ? '✗' : '✓'} ${p.researchId}  全局=` +
      `${String(c.transcriptRetention)}  ${perAgent.join('  ')}`);
  }
  console.log(`  关掉的账号：${off} 个。App 改这个开关时没有记录时间，` +
    '所以“关掉的时间”这里给不出。');
}

/** §1(2) */
async function reminders(db, people) {
  console.log('\n=== 第 1 节 (2) 行动计划跟进推送（dispatchReminders） ===');
  for (const p of people) {
    const ref = db.doc(`users/${p.uid}`);
    const [rems, tokens, sentEvents] = await Promise.all([
      ref.collection('reminders').get(),
      ref.collection('fcm_tokens').get(),
      ref.collection('events').where('name', '==', 'm7_reminder_sent').get(),
    ]);
    const byStatus = {};
    const errors = {};
    let lastSent = null;
    for (const r of rems.docs) {
      const d = r.data() || {};
      const s = d.dispatchStatus || (d.delivered ? 'sent' : '未处理');
      byStatus[s] = (byStatus[s] || 0) + 1;
      if (d.lastDispatchError) {
        for (const e of String(d.lastDispatchError).split(',')) {
          errors[e] = (errors[e] || 0) + 1;
        }
      }
      const at = toDate(d.dispatchedAt);
      if (at && (!lastSent || at > lastSent)) lastSent = at;
    }
    const platforms = tokens.docs.map((t) => (t.data() || {}).platform ||
      '?');
    console.log(`  ${p.researchId}: 提醒 ${rems.size} 条 ` +
      `${JSON.stringify(byStatus)}；发出事件 ${sentEvents.size} 次；` +
      `最后发出 ${hk(lastSent)}；设备 ${platforms.length} 部 ` +
      `[${platforms.join(', ')}]` +
      (Object.keys(errors).length ? `；错误 ${JSON.stringify(errors)}` : ''));
  }
  console.log('  说明：“sent”只表示 FCM 收下了；iPhone 是否真的收到，' +
    '服务器看不到，要看手机。');
}

/** H(3) */
async function quietToday(db, people) {
  console.log('\n=== H(3) 今日休息 用过几次 ===');
  let total = 0;
  for (const p of people) {
    const ref = db.doc(`users/${p.uid}`);
    const [ev, u] = await Promise.all([
      ref.collection('events').where('name', '==', 'quiet_today_activated')
          .get(),
      ref.get(),
    ]);
    const last = toDate((u.data() || {}).quietTodayActivatedAt);
    total += ev.size;
    if (ev.size || last) {
      const days = ev.docs.map((d) => hk(toDate((d.data() || {}).timestamp)));
      console.log(`  ${p.researchId}: ${ev.size} 次 [${days.join(', ')}]；` +
        `账号上最后一次 ${hk(last)}`);
    }
  }
  console.log(`  合计 ${total} 次（没列出的账号 = 0 次）。`);
}

/**
 * The tab the elder was on at [at], from tab_view events (logged on
 * leaving a tab, with durationSeconds).
 * @return {?string}
 */
function tabAt(tabViews, at) {
  for (const v of tabViews) {
    const end = v.at.getTime();
    const start = end - (Number(v.durationSeconds) || 0) * 1000;
    if (start <= at.getTime() && at.getTime() <= end) return v.tab;
  }
  return null;
}

/** 1020b §3(3): stt_usage rows since 10/15 00:00 HKT, per participant. */
const VOICE_SINCE = new Date('2026-10-15T00:00:00+08:00');

async function voice(db, people) {
  console.log('\n=== 1020b 第三节 (3) 自 10/15 起语音转写次数 ===');
  const total = {ok: 0, failed: 0};
  for (const p of people) {
    const rows = await db.collection('stt_usage').where('uid', '==', p.uid)
        .get();
    let ok = 0;
    let failed = 0;
    for (const d of rows.docs) {
      const r = d.data() || {};
      const at = toDate(r.createdAt);
      if (!at || at < VOICE_SINCE) continue;
      if (r.ok === true) ok++;
      else failed++;
    }
    total.ok += ok;
    total.failed += failed;
    console.log(`  ${p.researchId}: ${ok + failed} 次（成功 ${ok}，失败 ` +
      `${failed}）`);
  }
  console.log(`  合计 ${total.ok + total.failed} 次（成功 ${total.ok}，` +
    `失败 ${total.failed}）。只计数，不读文字。`);
}

/** §1(4) */
async function briefPr(db, people) {
  console.log('\n=== 第 1 节 (4) Brief PR：过期且从未展示 ===');
  const sum = {};
  for (const p of people) {
    const ref = db.doc(`users/${p.uid}`);
    const [records, views] = await Promise.all([
      ref.collection('brief_pr').get(),
      ref.collection('events').where('name', '==', 'tab_view').get(),
    ]);
    const tabViews = views.docs.map((d) => {
      const e = d.data() || {};
      const params = e.params || {};
      return {at: toDate(e.timestamp), tab: params.tab,
        durationSeconds: params.durationSeconds};
    }).filter((v) => v.at);
    tabViews.sort((a, b) => a.at - b.at);
    const mine = {};
    for (const r of records.docs) {
      const d = r.data() || {};
      if (d.finalStatus !== 'expired' || d.everShown === true) continue;
      const sid = d.sessionId || r.id;
      const s = (await ref.collection('sessions').doc(sid).get()).data() ||
        {};
      const started = toDate(s.startedAt) || toDate(d.sessionEndedAt);
      const tab = started ? tabAt(tabViews, started) : null;
      const page = PAGE_OF_TAB[tab] || (tab ? `其他（${tab}）` : '推断不到');
      mine[page] = (mine[page] || 0) + 1;
      sum[page] = (sum[page] || 0) + 1;
    }
    if (Object.keys(mine).length) {
      console.log(`  ${p.researchId}: ${JSON.stringify(mine)}`);
    }
  }
  console.log(`  合计：${JSON.stringify(sum)}`);
  console.log('  说明：会话从哪一页开始，App 没有直接记录；这里按离开分页时' +
    '记下的 tab_view 推断。');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`拒绝运行：${t.reason}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();
  console.log(`只读核对（dev-tasks-1020），目标：${t.reason}`);
  const people = await participants(db);
  console.log(`参与者（PB- 和 PILOT-）：${people.length} 人：` +
    people.map((p) => p.researchId).join(', '));
  await retention(db, people);
  await reminders(db, people);
  await quietToday(db, people);
  await voice(db, people);
  await briefPr(db, people);
  console.log('\n完。没有写入任何数据。');
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {tabAt, toDate, hk};

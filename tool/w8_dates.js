#!/usr/bin/env node
/**
 * tool/w8_dates.js — READ-ONLY.  T35 (handover 1021-W8 截止 [待核] and 六
 * (2); decision 0036): the W8 dates of every registered participant, by
 * research ID, computed from users/{uid}.w0Date with the server's own
 * code (functions/w8_questionnaire.js datesFor — the same function that
 * sends the pushes), plus which App build the phone last reported
 * (users/{uid}.appBuild, 开工方式 (4)) and the W8 completion status.
 *
 *   研究编号 | W0 | 第56天 开放、推送 | 第58天 提醒 | 第60天 提醒+电邮 |
 *   第63天 窗口关 | 第70天 首页卡最后一天 | App 版本 | W8 完成状态
 *
 * Who: registered, non-tester accounts (RCT-, PB-, PILOT-), the same rule
 * as the pushes (w8_questionnaire.isTarget).  Never prints an arm, a
 * cohort label, a name, an e-mail, a uid or an answer.  Writes nothing.
 * Reads only: users (field mask cohort, w0Date, createdAt, isTester,
 * appBuild), research_id_map (researchId), weekly_status (bundles.W8).
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/w8_dates.js
 * Real project (service account in GOOGLE_APPLICATION_CREDENTIALS):
 *   NODE_PATH=functions/node_modules node tool/w8_dates.js \
 *     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
 * Options:
 *   --csv        comma-separated instead of the table
 *   --examples   no Firestore at all: the dates of the handover's examples
 *                (W0 10/15 PILOT-02/03, 10/19 PB-01–04, 10/21 first RCT-)
 */
'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');
const w8 = require('../functions/w8_questionnaire');
const studyWeek = require('../functions/study_week');

/** The handover's worked examples (截止 line). */
const EXAMPLES = [
  {label: 'PILOT-02、03（W0 约 10/15）', w0: '2026-10-15'},
  {label: 'PB-01 至 04（W0 约 10/19）', w0: '2026-10-19'},
  {label: '第一位 RCT-（W0 约 10/21）', w0: '2026-10-21'},
];

const WEEKDAY = ['日', '一', '二', '三', '四', '五', '六'];

/**
 * @param {string} key YYYY-MM-DD
 * @return {string} "12/10（四）"
 */
function md(key) {
  const d = new Date(`${key}T00:00:00Z`);
  return `${d.getUTCMonth() + 1}/${d.getUTCDate()}（${WEEKDAY[d.getUTCDay()]}）`;
}

/**
 * The date row of one W0 (pure).
 * @param {string} w0 YYYY-MM-DD
 * @return {{w0: string, d56: string, d58: string, d60: string,
 *     d63: string, d70: string}}
 */
function datesRow(w0) {
  const d = w8.datesFor(w0);
  return {w0, d56: d.openKey, d58: d.remind1Key, d60: d.emailKey,
    d63: d.closeKey, d70: d.lastCardKey};
}

/**
 * @param {?object} b users/{uid}.appBuild
 * @return {string}
 */
function buildText(b) {
  if (!b || typeof b !== 'object') return '未报告（旧版，没有 W8 页面）';
  return `${b.version || '?'}(${b.build || '?'})` +
    (b.w8 === true ? ' 有 W8' : ' 没有 W8');
}

const STATUS_ZH = {
  not_yet: '未到', open: '开放中', in_progress: '做了一部分',
  late: '窗口已关（第 70 天前仍收）', done: '已完成', missed: '过期未完成',
};

/**
 * Every registered participant's row.  Read only.
 * @param {object} db admin.firestore()
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<Array<object>>} sorted by day 56, then research ID
 */
async function collect(db, opts) {
  const now = (opts && opts.now) || new Date();
  const todayKey = studyWeek.hkDateKey(now);
  const users = await db.collection('users')
      .select('cohort', 'w0Date', 'createdAt', 'isTester', 'appBuild').get();
  const rows = [];
  for (const u of users.docs) {
    const data = u.data() || {};
    if (!w8.isTarget(data)) continue;
    const w0 = studyWeek.w0DateKey(data);
    const [rid] = await db.getAll(db.collection('research_id_map').doc(u.id),
        {fieldMask: ['researchId']});
    const [st] = await db.getAll(db.collection('weekly_status').doc(u.id),
        {fieldMask: ['bundles.W8']});
    const status = st.exists ? ((st.get('bundles') || {}).W8 || null) : null;
    const cell = w8.cellFor(status, studyWeek.studyDayOf(w0, todayKey));
    rows.push(Object.assign(datesRow(w0), {
      researchId: (rid.exists && rid.get('researchId')) || '（研究编号缺失）',
      appBuild: buildText(data.appBuild),
      hasW8Build: !!(data.appBuild && data.appBuild.w8 === true),
      w8Status: STATUS_ZH[cell] || cell,
    }));
  }
  rows.sort((a, b) => a.d56.localeCompare(b.d56) ||
    a.researchId.localeCompare(b.researchId));
  return rows;
}

const HEAD = ['研究编号', 'W0', '第56天 开放推送', '第58天 提醒',
  '第60天 提醒+电邮', '第63天 窗口关', '第70天 卡片最后一天', 'App 版本',
  'W8 完成状态'];

/**
 * @param {Array<object>} rows collect() rows
 * @param {{csv: (boolean|undefined)}} opts
 * @return {string}
 */
function format(rows, opts) {
  const csv = !!(opts && opts.csv);
  const cells = (r) => [r.researchId, r.w0, md(r.d56), md(r.d58), md(r.d60),
    md(r.d63), md(r.d70), r.appBuild, r.w8Status];
  if (csv) {
    const q = (v) => (/[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
    return [HEAD, ...rows.map(cells)].map((c) => c.map(q).join(','))
        .join('\n') + '\n';
  }
  const lines = [HEAD.join(' | ')];
  for (const r of rows) lines.push(cells(r).join(' | '));
  const old = rows.filter((r) => !r.hasW8Build).length;
  lines.push('', `共 ${rows.length} 人；App 还没有报告 W8 版本的 ${old} 人` +
    '（要在第 56 天前装新版）。');
  return lines.join('\n') + '\n';
}

/**
 * The handover's examples (no Firestore).
 * @return {string}
 */
function examples() {
  const lines = ['例子 | W0 | 第56天 | 第58天 | 第60天 | 第63天 | 第70天'];
  for (const e of EXAMPLES) {
    const r = datesRow(e.w0);
    lines.push([e.label, r.w0, md(r.d56), md(r.d58), md(r.d60), md(r.d63),
      md(r.d70)].join(' | '));
  }
  return lines.join('\n') + '\n';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.examples) {
    process.stdout.write(examples());
    return;
  }
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(t.reason);
    process.exit(2);
  }
  console.error(`目标：${t.reason}（只读）`);
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const rows = await collect(admin.firestore(), {});
  process.stdout.write(format(rows, {csv: !!args.csv}));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err && err.stack ? err.stack : err);
    process.exit(1);
  });
}

module.exports = {EXAMPLES, datesRow, buildText, collect, format, examples};

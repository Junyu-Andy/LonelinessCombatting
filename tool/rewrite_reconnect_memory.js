#!/usr/bin/env node
/**
 * tool/rewrite_reconnect_memory.js — 1020e 二.13 (2).
 *
 * From 1020e on, 「想重新聯絡嘅人」 goes into 小欣's memory only for the
 * people the elder ticked 「可以講」 (functions/researcher_intake.js
 * intakeFactsFor).  Facts written before that carry every name.  This
 * script rewrites them: for every account whose active intake facts
 * (`source_session_id: "intake"`) hold a 想重新聯絡嘅人 fact that differs
 * from what the stored intake document gives today, it re-seeds the
 * intake facts the same way a new intake recording does
 * (researcher_intake.seedMemoryFacts: old intake facts → superseded, new
 * ones written).  Facts the companions extracted from conversations are
 * never touched.
 *
 * DRY RUN by default: prints, per research ID, how many names would be
 * dropped, and writes nothing.  `--apply` writes.  Never prints a name,
 * an arm or any memory text.  Reads `enrollments` only for the research
 * ID; never reads the sequences, allocation logs or correctArm.
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/rewrite_reconnect_memory.js
 * Real project (needs a service account in GOOGLE_APPLICATION_CREDENTIALS):
 *   NODE_PATH=functions/node_modules node tool/rewrite_reconnect_memory.js \
 *     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
 *   ... then the same with --apply.
 */
'use strict';

const path = require('path');
const {parseArgs, checkTarget} = require('./firestore_target');
const ri = require(path.join(__dirname, '..', 'functions',
    'researcher_intake'));

const KEY = '想重新聯絡嘅人';

/** Names in a stored fact value 「甲（關係）、乙」 → count. */
function countNames(value) {
  if (typeof value !== 'string' || !value.trim()) return 0;
  return value.split('、').filter((s) => s.trim()).length;
}

/**
 * One account: what the 想重新聯絡嘅人 fact is now and should be.
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?{before: number, after: number, input: object}>} null
 *     when the account has no active intake 想重新聯絡嘅人 fact or nothing
 *     would change
 */
async function planFor(db, uid) {
  const facts = await db.collection('users').doc(uid)
      .collection('mem_facts')
      .where('source_session_id', '==', ri.INTAKE_SOURCE)
      .where('status', '==', 'active').get();
  const current = facts.docs.filter((d) => d.get('key') === KEY);
  if (!current.length) return null;
  const intake = await db.doc(ri.intakeDocPath(uid)).get();
  const input = ri.factsInputFromDoc(intake.exists ? intake.data() : {});
  const want = ri.intakeFactsFor(input).filter((f) => f.key === KEY);
  const wantValue = want.length ? want[0].value : '';
  const values = current.map((d) => d.get('value'));
  if (values.every((v) => v === wantValue) && want.length) return null;
  return {before: countNames(values[0]), after: countNames(wantValue), input};
}

/**
 * Every enrolled account with an intake 想重新聯絡嘅人 fact to rewrite.
 * @param {object} db
 * @param {{apply: boolean, now: Date, log: function(string): void}} o
 * @return {Promise<{checked: number, changed: number}>}
 */
async function run(db, o) {
  const log = o.log || console.log;
  const enrolments = await db.collection('enrollments').get();
  let checked = 0;
  let changed = 0;
  const rows = enrolments.docs
      .map((d) => ({uid: d.id, rid: d.get('researchId') || '(无编号)'}))
      .sort((a, b) => a.rid.localeCompare(b.rid));
  for (const r of rows) {
    checked++;
    const p = await planFor(db, r.uid);
    if (!p) continue;
    changed++;
    log(`  ${r.rid}: 想重新聯絡嘅人 ${p.before} 个名 → ${p.after} 个名` +
      (o.apply ? '（已重写）' : '（预演，没写）'));
    if (o.apply) await ri.seedMemoryFacts(db, r.uid, p.input, o.now);
  }
  return {checked, changed};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`拒绝运行：${t.reason}`);
    process.exit(2);
  }
  const apply = args.apply === true;
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();
  console.log(`1020e 二.13 重写「想重新聯絡嘅人」记忆，目标：${t.reason}；` +
    (apply ? '会写入' : '预演，不写入（加 --apply 才写）'));
  const out = await run(db, {apply, now: new Date()});
  console.log(`\n查了 ${out.checked} 个登记账号；要改 ${out.changed} 个。` +
    (apply ? '已写完。' : '没有写入任何数据。'));
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {planFor, run, countNames, KEY};

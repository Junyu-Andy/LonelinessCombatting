#!/usr/bin/env node
/**
 * tool/export_agent_contexts.js — READ-ONLY backup (dev-tasks 1020j §1(3)).
 *
 * Copies users/{uid}/agent_contexts/* (each companion's memory document:
 * the short-term buffer of verbatim turns while a session is open, the
 * rolling summary, named entities, theme threads) of the PILOT- and PB-
 * accounts into one JSON file on this computer, before later sessions
 * overwrite it.  The App folds the buffer into the summary and clears it
 * at the end of each session (lib/core/agent_context/
 * rolling_summary_compiler.dart), so what is there is mostly summaries.
 *
 * Writes nothing to Firestore.  Reads only:
 *   enrollments                      researchId, studyPeriod (field mask)
 *   users/{uid}/agent_contexts/*     everything (it is what is backed up)
 * Never reads randomization_sequences, randomization_state, sequence
 * versions, allocation logs or correctArm records (dev-tasks rule 6).
 * Prints counts per research ID only — never any text.
 *
 * The file holds conversation text: it is written with mode 0600, outside
 * the repository (refused inside), default
 * ~/dev/backups/agent_contexts_<Hong Kong date-time>.json.
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/export_agent_contexts.js
 * Real project (a key in GOOGLE_APPLICATION_CREDENTIALS; the dashboard's
 * read-only key is enough):
 *   NODE_PATH=functions/node_modules node tool/export_agent_contexts.js \
 *     --project=loneliness-pilot-dev \
 *     --production-confirm=loneliness-pilot-dev
 * Options: --out=<file>  --prefix=PILOT-,PB-  (research ID prefixes)
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const {parseArgs, checkTarget} = require('./firestore_target');

const ROOT = path.resolve(__dirname, '..');
const DEFAULT_PREFIXES = ['PILOT-', 'PB-'];

function isInside(child, parent) {
  const rel = path.relative(parent, child);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

/** Hong Kong "YYYY-MM-DD-HH-mm". */
function hkStamp(d) {
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString()
      .slice(0, 16).replace(/[:T]/g, '-');
}

/** Firestore values → plain JSON (Timestamps as ISO strings). */
function toPlain(v) {
  if (v === null || v === undefined) return null;
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  if (Array.isArray(v)) return v.map(toPlain);
  if (typeof v === 'object') {
    const out = {};
    for (const k of Object.keys(v)) out[k] = toPlain(v[k]);
    return out;
  }
  return v;
}

/** Output path: --out, else the default; never inside the repository. */
function outPath(args, now) {
  const p = path.resolve(typeof args.out === 'string' ? args.out :
    path.join(os.homedir(), 'dev', 'backups',
        `agent_contexts_${hkStamp(now)}.json`));
  if (p === ROOT || isInside(p, ROOT)) {
    throw new Error('the backup holds conversation text: write it outside ' +
      'the repository (--out)');
  }
  return p;
}

/**
 * @param {object} db
 * @param {Array<string>} prefixes
 * @return {Promise<object>} the backup document
 */
async function buildBackup(db, prefixes) {
  const snap = await db.collection('enrollments')
      .select('researchId', 'studyPeriod').get();
  const people = snap.docs
      .map((d) => ({uid: d.id, researchId: d.get('researchId')}))
      .filter((p) => typeof p.researchId === 'string' &&
        prefixes.some((pre) => p.researchId.startsWith(pre)))
      .sort((a, b) => a.researchId.localeCompare(b.researchId));
  const participants = [];
  for (const p of people) {
    const ctx = await db.collection('users').doc(p.uid)
        .collection('agent_contexts').get();
    const agentContexts = {};
    for (const d of ctx.docs) agentContexts[d.id] = toPlain(d.data());
    participants.push({researchId: p.researchId, uid: p.uid, agentContexts});
  }
  return {participants};
}

/** Per research ID: documents, buffered turns, summary present. */
function summaryLines(backup) {
  return backup.participants.map((p) => {
    const docs = Object.keys(p.agentContexts);
    let turns = 0;
    let summaries = 0;
    for (const id of docs) {
      const c = p.agentContexts[id] || {};
      if (Array.isArray(c.shortTermBuffer)) turns += c.shortTermBuffer.length;
      if (typeof c.rollingSummary === 'string' && c.rollingSummary.trim()) {
        summaries++;
      }
    }
    return `${p.researchId}: ${docs.length} 位陪伴者的文档，` +
      `缓冲区 ${turns} 轮，摘要 ${summaries} 份`;
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const target = checkTarget(process.env, args);
  if (!target.ok) {
    console.error(`✗ ${target.reason}`);
    process.exit(2);
  }
  const prefixes = typeof args.prefix === 'string' ?
    args.prefix.split(',').map((s) => s.trim()).filter(Boolean) :
    DEFAULT_PREFIXES;
  const now = new Date();
  let file;
  try {
    file = outPath(args, now);
  } catch (err) {
    console.error(`✗ ${err.message}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: target.projectId});
  const backup = await buildBackup(admin.firestore(), prefixes);
  const doc = Object.assign({
    exportedAt: now.toISOString(),
    target: target.target,
    projectId: target.projectId,
    prefixes,
    note: '只读备份：users/{uid}/agent_contexts。含对话内容，请放在加密磁盘上，' +
      '不要发邮件、不要放进仓库。',
  }, backup);
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  fs.writeFileSync(file, JSON.stringify(doc, null, 2), {mode: 0o600});
  fs.chmodSync(file, 0o600);
  console.log(`目标：${target.reason}`);
  for (const line of summaryLines(backup)) console.log(`  ${line}`);
  console.log(`共 ${backup.participants.length} 人。已写入：${file}`);
  console.log('只读完成，没有写入 Firestore。');
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err && err.message || err);
    process.exit(1);
  });
}

module.exports = {DEFAULT_PREFIXES, toPlain, outPath, buildBackup,
  summaryLines, hkStamp};

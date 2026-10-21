#!/usr/bin/env node
/**
 * tool/read_transcripts.js — READ-ONLY.  Prints the research transcript of
 * ONE TEST ACCOUNT (`users/{uid}/chat_transcripts`, decisions 0063 / 0069)
 * so the lead can check, after a phone test, what the App stored.  Writes
 * nothing.
 *
 * Test accounts only (decisions-log 10/21: isTester true AND no RCT-,
 * PB- or PILOT- research ID; everything else refused).  It first reads
 * `users/{uid}` with a field mask of `isTester` and `cohort` only; unless
 * isTester is literally `true` it refuses (exit 3) BEFORE anything else is
 * read.  A tester is then refused too when its cohort is a study one
 * (`phase_b` / `rct` / `pilot`, set from those prefixes) or when
 * `research_id_map/{uid}` (field mask `researchId` only) holds an ID
 * starting RCT-, PB- or PILOT-.  Real participants are refused outright:
 * the proper tool (non-blinded roles, by research ID, with an audit log)
 * comes after the freeze (docs/dev/backlog.md).  The research ID is read
 * only to check its prefix and is never printed; it never reads an e-mail
 * address, an arm or any allocation data, and never touches the
 * randomization collections (sequences, randomization_state, the
 * allocation log, arm corrections).
 *
 * Output: the rows in time order — each row's time is `userSentAt`, else
 * `replyShownAt` (companion rows have no `userSentAt`), else `receivedAt`;
 * Hong Kong time — grouped by `sessionId` with a header per session
 * (sessions in the order of their first row).  Each row: time, role,
 * agentId, moduleId, userInput, userText, replyText (its line breaks kept,
 * indented; bubbles are separated by a blank line), replyStatus.  Schema 1
 * rows (App builds before the freeze) have no role / userInput and say so.
 *
 * Options:
 *   --uid=<uid>          the test account (required)
 *   --since=YYYY-MM-DD   only rows from that day on (Hong Kong time)
 *   --limit=<n>          only the latest n rows (still printed oldest first)
 *   --json               JSON instead of text
 *
 * Target (tool/firestore_target.js, as tool/check_prelaunch_values.js):
 * the emulator (FIRESTORE_EMULATOR_HOST set) is the default and prints
 * the rows.  A real project needs --project=<id> --production-confirm=<id>;
 * that alone is a DRY RUN: the account check and the number of rows (and
 * sessions) it would show, reading only the time fields — no text is read
 * or printed.  Adding --production prints the rows (the repo's convention:
 * outside the emulator the real action also needs --production, as in
 * tool/delete_participant.js and tool/purge_tester_data.js).
 *
 * Emulator (default):
 *   NODE_PATH=functions/node_modules node tool/read_transcripts.js --uid=<uid>
 * Real project (service account in GOOGLE_APPLICATION_CREDENTIALS):
 *   NODE_PATH=functions/node_modules node tool/read_transcripts.js \
 *     --uid=<uid> --project=loneliness-pilot-dev \
 *     --production-confirm=loneliness-pilot-dev            # dry run
 *   ... the same plus --production                        # the rows
 *
 * Exit codes: 0 done; 2 bad option or target refused; 3 account refused
 * (no such account, or not a tester); 1 anything else.
 * Guide: docs/release/transcript-test-1021.md.
 */
'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');
const studyPeriod = require('../functions/study_period');

const COLLECTION = 'chat_transcripts';

/** Fields read in a dry run: the order and the grouping, never text. */
const TIME_FIELDS = ['sessionId', 'userSentAt', 'replyShownAt', 'receivedAt'];

/** Between two bubbles in `replyText` (TranscriptRow.partSeparator). */
const PART_SEPARATOR = '\n\n';

const REFUSE_NOT_TESTER = '这个工具只给测试员账号用。真实参与者的原文一律' +
  '不读；给非盲角色、带审计记录的正式读取工具冻结后再做（见 ' +
  'docs/dev/backlog.md）。';

/** Study research-ID prefixes (RCT-, PB-, PILOT-) and the cohorts set from
 * them: the one list in functions/study_period.js. */
const STUDY_PREFIXES = studyPeriod.PERIODS.map((p) => p.prefix);
const STUDY_COHORTS = studyPeriod.ENROLLED_COHORTS;

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

/** Hong Kong time, "YYYY-MM-DD HH:mm:ss". */
function hk(d) {
  if (!d) return '—';
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString()
      .slice(0, 19).replace('T', ' ');
}

/**
 * The time a row is ordered by, and which field it came from.
 * @param {object} data a chat_transcripts document
 * @return {{at: ?Date, field: ?string}}
 */
function sortTime(data) {
  for (const f of ['userSentAt', 'replyShownAt', 'receivedAt']) {
    const d = toDate(data[f]);
    if (d) return {at: d, field: f};
  }
  return {at: null, field: null};
}

/**
 * The command-line options, checked.  Throws on a bad one.
 * @param {object} args parseArgs output
 * @return {{uid: string, json: boolean, since: ?Date, sinceText: ?string,
 *     limit: ?number}}
 */
function parseOptions(args) {
  const uid = args.uid;
  if (typeof uid !== 'string' || !uid || uid.indexOf('/') >= 0) {
    throw new Error('要给 --uid=<测试员账号的 uid>');
  }
  let since = null;
  let sinceText = null;
  if (args.since !== undefined) {
    const s = String(args.since);
    const d = /^\d{4}-\d{2}-\d{2}$/.test(s) ?
      new Date(`${s}T00:00:00+08:00`) : null;
    if (!d || isNaN(d.getTime()) ||
        hk(d).slice(0, 10) !== s) {
      throw new Error('--since 要写成 YYYY-MM-DD（香港日期），例如 ' +
        '--since=2026-10-21');
    }
    since = d;
    sinceText = s;
  }
  let limit = null;
  if (args.limit !== undefined) {
    const s = String(args.limit);
    if (!/^\d+$/.test(s) || Number(s) < 1) {
      throw new Error('--limit 要写正整数，例如 --limit=20');
    }
    limit = Number(s);
  }
  return {uid, json: args.json === true, since, sinceText, limit};
}

/**
 * What a run may show.  The emulator: the rows.  A real project: a dry
 * run (account check + counts) unless --production.
 * @param {{target: string}} t checkTarget result
 * @param {object} args parseArgs output
 * @return {string} 'full' | 'count'
 */
function decideMode(t, args) {
  if (t.target === 'emulator') return 'full';
  return args.production === true ? 'full' : 'count';
}

/**
 * Step 1: is users/{uid} a tester without a study research ID?  Reads
 * users/{uid} with a field mask of `isTester` and `cohort` (no e-mail or
 * arm); only for a tester, `research_id_map/{uid}` with a field mask of
 * `researchId`.  The ID is compared with [STUDY_PREFIXES], never printed.
 * @return {Promise<{ok: boolean, message: string}>}
 */
async function checkAccount(db, uid) {
  const [snap] = await db.getAll(db.doc(`users/${uid}`),
      {fieldMask: ['isTester', 'cohort']});
  if (!snap.exists) {
    return {ok: false, message: `拒绝：users/${uid} 不存在，没有读取任何原文。`};
  }
  if (snap.get('isTester') !== true) {
    return {ok: false, message: `拒绝：users/${uid} 不是测试员账号` +
      '（isTester 不是 true），没有读取任何原文。\n' + REFUSE_NOT_TESTER};
  }
  const [map] = await db.getAll(db.doc(`research_id_map/${uid}`),
      {fieldMask: ['researchId']});
  const rid = map.exists ? map.get('researchId') : null;
  const studyId = typeof rid === 'string' && STUDY_PREFIXES.some(
      (p) => rid.trim().toUpperCase().indexOf(p) === 0);
  if (studyId || STUDY_COHORTS.indexOf(snap.get('cohort')) !== -1) {
    return {ok: false, message: `拒绝：users/${uid} 虽然是测试员，但有正式` +
      '研究编号（RCT-、PB- 或 PILOT- 开头），没有读取任何原文。\n' +
      REFUSE_NOT_TESTER};
  }
  return {ok: true, message: `账号 ${uid}：测试员（isTester = true），` +
    '没有正式研究编号 ✓'};
}

/**
 * Step 2 (only after step 1 passed): the account's rows.  A dry run reads
 * only [TIME_FIELDS].
 * @return {Promise<Array<{id: string, data: object}>>}
 */
async function loadRows(db, uid, countOnly) {
  const col = db.collection(`users/${uid}/${COLLECTION}`);
  const snap = countOnly ? await col.select(...TIME_FIELDS).get() :
    await col.get();
  return snap.docs.map((d) => ({id: d.id, data: d.data() || {}}));
}

/**
 * Sort by time (ties: receivedAt, then the id), keep rows from [since]
 * on, then only the latest [limit].
 * @return {Array<{id: string, data: object, at: ?Date, field: ?string}>}
 */
function selectRows(rows, since, limit) {
  const timed = rows.map((r) => {
    const t = sortTime(r.data);
    return {id: r.id, data: r.data, at: t.at, field: t.field};
  });
  const ms = (d) => (d ? d.getTime() : 0);
  timed.sort((a, b) => ms(a.at) - ms(b.at) ||
      ms(toDate(a.data.receivedAt)) - ms(toDate(b.data.receivedAt)) ||
      (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  let out = since ? timed.filter((r) => r.at && r.at >= since) : timed;
  if (limit && out.length > limit) out = out.slice(out.length - limit);
  return out;
}

/**
 * Group by sessionId; sessions in the order of their first row.
 * @return {Array<{sessionId: string, rows: Array}>}
 */
function groupSessions(rows) {
  const bySession = new Map();
  for (const r of rows) {
    const s = typeof r.data.sessionId === 'string' && r.data.sessionId ?
      r.data.sessionId : '（没有 sessionId）';
    if (!bySession.has(s)) bySession.set(s, {sessionId: s, rows: []});
    bySession.get(s).rows.push(r);
  }
  return Array.from(bySession.values());
}

/** How many bubbles a replyText holds (blank line between two). */
function bubbleCount(text) {
  if (typeof text !== 'string' || !text.trim()) return 0;
  return text.split(PART_SEPARATOR).filter((p) => p.trim()).length;
}

/** @return {string} the value, or a dash for null / missing */
function show(v) {
  if (v === undefined || v === null) return '—';
  return String(v);
}

/** One row as text lines. */
function rowLines(r, n) {
  const d = r.data;
  const v1 = d.role === undefined;
  const lines = [];
  lines.push(`  [${n}] ${hk(r.at)}（香港时间，按 ${show(r.field)}）`);
  lines.push(`      role: ${v1 ? '—（schema 1 旧格式，没有这个字段；' +
    '一行 = 老人一句 + 回复）' : show(d.role)}   agentId: ${show(d.agentId)}` +
    `   moduleId: ${show(d.moduleId)}`);
  lines.push(`      userInput: ${v1 ? '—（schema 1 旧格式没有）' :
    show(d.userInput)}`);
  lines.push(`      userText: ${show(d.userText)}`);
  const reply = typeof d.replyText === 'string' ? d.replyText : '';
  if (!reply) {
    lines.push('      replyText: （空）');
  } else {
    const bubbles = bubbleCount(reply);
    lines.push(`      replyText（${bubbles} 个气泡` +
      `${bubbles > 1 ? '，气泡之间空一行' : ''}）:`);
    for (const l of reply.split('\n')) lines.push(l ? `        ${l}` : '');
  }
  lines.push(`      replyStatus: ${show(d.replyStatus)}   schemaVersion: ` +
    `${show(d.schemaVersion)}   turnId: ${show(d.turnId || r.id)}`);
  return lines;
}

/** One row for --json. */
function rowJson(r) {
  const d = r.data;
  const iso = (v) => {
    const x = toDate(v);
    return x ? x.toISOString() : null;
  };
  return {
    turnId: d.turnId || r.id,
    time: hk(r.at),
    timeField: r.field,
    role: d.role === undefined ? null : d.role,
    agentId: show(d.agentId),
    moduleId: show(d.moduleId),
    userInput: d.userInput === undefined ? null : d.userInput,
    userText: d.userText === undefined ? null : d.userText,
    replyText: typeof d.replyText === 'string' ? d.replyText : '',
    replyStatus: d.replyStatus === undefined ? null : d.replyStatus,
    schemaVersion: d.schemaVersion === undefined ? null : d.schemaVersion,
    userSentAt: iso(d.userSentAt),
    replyShownAt: iso(d.replyShownAt),
    receivedAt: iso(d.receivedAt),
  };
}

/** The filters in words, for the summary line. */
function filterText(opts) {
  const f = [];
  if (opts.sinceText) f.push(`--since=${opts.sinceText}`);
  if (opts.limit) f.push(`--limit=${opts.limit}`);
  return f.length ? `（按 ${f.join(' ')}）` : '';
}

/**
 * The account check, then (only if it passed) the rows.
 * @param {object} db admin.firestore()
 * @param {{uid: string, json: boolean, since: ?Date, sinceText: ?string,
 *     limit: ?number, mode: string, target: string}} opts
 * @param {{log: function(string), error: function(string)}} out
 * @return {Promise<{status: number, rows: ?number, sessions: ?number}>}
 */
async function run(db, opts, out) {
  const log = out.log;
  const account = await checkAccount(db, opts.uid);
  if (!account.ok) {
    out.error(account.message);
    return {status: 3, rows: null, sessions: null};
  }
  const countOnly = opts.mode === 'count';
  const all = await loadRows(db, opts.uid, countOnly);
  const rows = selectRows(all, opts.since, opts.limit);
  const sessions = groupSessions(rows);

  if (opts.json) {
    const base = {mode: countOnly ? 'dry_run' : 'rows', target: opts.target,
      uid: opts.uid, isTester: true, totalRows: all.length,
      rows: rows.length, sessionCount: sessions.length};
    if (!countOnly) {
      base.sessions = sessions.map((s) => ({sessionId: s.sessionId,
        rows: s.rows.map(rowJson)}));
    }
    log(JSON.stringify(base, null, 2));
    return {status: 0, rows: rows.length, sessions: sessions.length};
  }

  log(`目标：${opts.target}（只读，不写任何数据）`);
  if (countOnly) {
    log('试运行（dry run）：只核对账号、数行数，只读时间字段，不读也不显示' +
      '原文。要显示原文，同一条命令末尾加 --production 再跑一次。');
  }
  log(account.message);
  log(`users/${opts.uid}/${COLLECTION}：共 ${all.length} 行；` +
    `${countOnly ? '会显示' : '显示'} ${rows.length} 行，` +
    `${sessions.length} 个会话${filterText(opts)}。`);
  if (countOnly) {
    log('\n完。没有写入任何数据。');
    return {status: 0, rows: rows.length, sessions: sessions.length};
  }
  log('每行的时间按 userSentAt；陪伴者行没有，用 replyShownAt；' +
    '再没有用 receivedAt。');
  let n = 0;
  sessions.forEach((s, i) => {
    const first = s.rows[0].at;
    const last = s.rows[s.rows.length - 1].at;
    log('');
    log(`══ 会话 ${i + 1}/${sessions.length} · sessionId: ${s.sessionId} · ` +
      `${s.rows.length} 行 · ${hk(first)} 至 ${hk(last)}（香港时间）══`);
    for (const r of s.rows) {
      n++;
      for (const l of rowLines(r, n)) log(l);
    }
  });
  log('\n完。没有写入任何数据。');
  return {status: 0, rows: rows.length, sessions: sessions.length};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  let opts;
  try {
    opts = parseOptions(args);
  } catch (err) {
    console.error(`拒绝运行：${err.message}`);
    process.exit(2);
  }
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`拒绝运行：${t.reason}`);
    process.exit(2);
  }
  if (t.target === 'emulator' && args.production !== undefined) {
    console.error('拒绝运行：设了 FIRESTORE_EMULATOR_HOST（模拟器），又给了 ' +
      '--production，目标不清楚。');
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  opts.mode = decideMode(t, args);
  opts.target = t.reason;
  const r = await run(admin.firestore(), opts, {
    log: (s) => console.log(s),
    error: (s) => console.error(s),
  });
  process.exit(r.status);
}

module.exports = {run, checkAccount, loadRows, selectRows, groupSessions,
  sortTime, parseOptions, decideMode, hk, bubbleCount, TIME_FIELDS};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

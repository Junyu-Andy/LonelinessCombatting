#!/usr/bin/env node
/**
 * tool/purge_tester_data.js
 *
 * T32 item 6 (dev-tasks-1010 §4 T32.6, dev-tasks-1010b §2 T32; SPEC:C22,
 * C20; 10/9 item 18 (7)): everything in the Firebase project before the
 * 10/19 enrolment belongs to testers and is not kept.  This script finds
 * those accounts and, only on request, deletes each one with
 * tool/delete_participant.js.
 *
 * Who is listed (one line per account, union of Auth users and users/*):
 *
 *   tester      users/{uid}.isTester == true
 *   unenrolled  no study period: users/{uid}.cohort is not "phase_b" or
 *               "pilot" (functions/study_period.js isEnrolled), including
 *               accounts with no users/{uid} document at all and old
 *               "phase_a" accounts
 *
 * Who is NEVER touched (listed as kept, with the reason):
 *
 *   enrolled    cohort "phase_b" or "pilot", or an enrollments/{uid}
 *               record — even when isTester is also true
 *   staff       Auth custom claim role = unblinded / blinded (and the
 *               retired names pi / researcher), i.e. researcher and
 *               assessor accounts (tool/provision_researcher.js)
 *   --keep      uids given on the command line
 *
 * Per account the data volume comes from delete_participant.js's dry run:
 * document counts per users/{uid} subcollection, rows in the top-level
 * collections that carry the uid (llm_calls, safety_events, …), the Auth
 * account, Storage files and rows in the weekly exports.  Counts only; no
 * field values, no text, no e-mail addresses.
 *
 * Modes:
 *   default            list only (nothing is written to Firestore)
 *   --confirm          delete every tester / unenrolled account, one
 *                      delete_participant.js run per uid (its receipts are
 *                      written too), then write a run log
 *
 * Target guard (same pattern as tool/firestore_target.js): the emulator
 * (FIRESTORE_EMULATOR_HOST set) needs nothing more.  Outside it,
 * --confirm needs ALL of --production --project=<id>
 * --production-confirm=<id>, where <id> is the real project id.
 *
 * Run log: --confirm writes admin_runs/{autoId} (server-only: no
 * firestore.rules match, so no client can read or write it) with the
 * mode, time, operator, counts and the uid + kind + verification result
 * of every account; kept accounts are listed with the reason.  A local
 * JSON copy (--receipt=<path>, default
 * ./purge-tester-receipt-<time>.json) holds the same plus each per-user
 * deletion receipt.  Nothing in either carries field values or text.
 *
 * What stays after a run: everything delete_participant.js lists as not
 * covered — arm_assignment_log, pilot_assignment_log, the used sequence
 * positions, Cloud Logging, provider-side copies, weekly export rows
 * (counted, not rewritten unless --rewrite-exports), local admin dumps.
 *
 * Usage (run from the repo root):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   NODE_PATH=functions/node_modules node tool/purge_tester_data.js \
 *       --project=loneliness-pilot-dev            # list only
 *   ... --confirm --production --project=loneliness-pilot-dev \
 *       --production-confirm=loneliness-pilot-dev --operator=<email>
 * Options:
 *   --only=testers|unenrolled   restrict to one kind
 *   --keep=<uid>[,<uid>…]       never touch these uids
 *   --created-before=<ISO date> only accounts whose Auth account was
 *                               created before this moment (accounts
 *                               without an Auth record always qualify)
 *   --rewrite-exports           passed through to delete_participant.js
 *   --bucket=<name>             Storage bucket (default as in
 *                               delete_participant.js)
 *   --receipt=<path>            where the local JSON log goes
 *   --operator=<text>           recorded in the run log
 *   --no-volumes                skip the per-user dry run when listing
 *                               (faster; kinds and counts of accounts
 *                               only)
 */

'use strict';

const fs = require('fs');
const admin = require('firebase-admin');
const deletion = require('./delete_participant');
const {parseArgs, checkTarget} = require('./firestore_target');
const studyPeriod = require('../functions/study_period');

const PROJECT = 'loneliness-pilot-dev';
const DEFAULT_BUCKET = 'loneliness-pilot-dev.firebasestorage.app';

/** Auth custom-claim roles that mark staff (T19 names + T12 legacy). */
const STAFF_ROLES = ['unblinded', 'blinded', 'pi', 'researcher'];

const KINDS = {
  TESTER: 'tester',
  UNENROLLED: 'unenrolled',
  ENROLLED: 'enrolled',
  STAFF: 'staff',
  KEEP: 'keep',
};

/** Kinds this script deletes with --confirm. */
const PURGEABLE = [KINDS.TESTER, KINDS.UNENROLLED];

/** --only values and the kind each one keeps. */
const ONLY = {testers: KINDS.TESTER, unenrolled: KINDS.UNENROLLED};

/**
 * Every Auth user, with uid, role claim, creation time.
 * @param {object} auth admin.auth()
 * @return {Promise<Map<string, {role: ?string, createdAt: ?string}>>}
 */
async function listAuthUsers(auth) {
  const out = new Map();
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    for (const u of page.users) {
      const claims = u.customClaims || {};
      const meta = u.metadata || {};
      out.set(u.uid, {
        role: typeof claims.role === 'string' ? claims.role : null,
        createdAt: meta.creationTime ?
          new Date(meta.creationTime).toISOString() : null,
      });
    }
    token = page.pageToken;
  } while (token);
  return out;
}

/**
 * Decide what an account is.  Pure, so the tests can cover every case.
 * @param {{user: ?object, role: ?string, enrollment: boolean,
 *   keep: boolean}} a
 * @return {{kind: string, reason: string}}
 */
function classify(a) {
  if (a.keep) return {kind: KINDS.KEEP, reason: '--keep on the command line'};
  if (a.role && STAFF_ROLES.indexOf(a.role) >= 0) {
    return {kind: KINDS.STAFF, reason: `Auth role claim "${a.role}"`};
  }
  const u = a.user || {};
  if (studyPeriod.isEnrolled(u)) {
    return {kind: KINDS.ENROLLED, reason: `cohort "${u.cohort}"`};
  }
  if (a.enrollment) {
    return {kind: KINDS.ENROLLED,
      reason: 'enrollments/{uid} record exists'};
  }
  if (u.isTester === true) return {kind: KINDS.TESTER, reason: 'isTester'};
  if (!a.user) {
    return {kind: KINDS.UNENROLLED, reason: 'no users/{uid} document'};
  }
  const c = typeof u.cohort === 'string' ? `cohort "${u.cohort}"` :
    'no cohort';
  return {kind: KINDS.UNENROLLED, reason: `${c} (not phase_b / pilot)`};
}

/**
 * Union of Auth users and users/* documents, classified.
 * @param {{db: object, auth: object, keep: string[]}} ctx
 * @return {Promise<Array<{uid: string, kind: string, reason: string,
 *   hasAuth: boolean, hasUserDoc: boolean, createdAt: ?string,
 *   arm: ?string}>>}
 */
async function listAccounts(ctx) {
  const {db, auth} = ctx;
  const keep = new Set(ctx.keep || []);
  const authUsers = await listAuthUsers(auth);
  const userDocs = new Map();
  for (const d of (await db.collection('users').get()).docs) {
    userDocs.set(d.id, d.data() || {});
  }
  const enrolled = new Set();
  for (const d of (await db.collection('enrollments').get()).docs) {
    enrolled.add(d.id);
  }
  const uids = new Set([...authUsers.keys(), ...userDocs.keys()]);
  const out = [];
  for (const uid of [...uids].sort()) {
    const a = authUsers.get(uid) || null;
    const user = userDocs.has(uid) ? userDocs.get(uid) : null;
    const c = classify({user, role: a ? a.role : null,
      enrollment: enrolled.has(uid), keep: keep.has(uid)});
    out.push({
      uid, kind: c.kind, reason: c.reason,
      hasAuth: Boolean(a), hasUserDoc: Boolean(user),
      createdAt: a ? a.createdAt : null,
      arm: user && typeof user.arm === 'string' ? user.arm : null,
    });
  }
  return out;
}

/**
 * Apply --only and --created-before to the purgeable accounts.  Accounts
 * that are not purgeable are always kept and never filtered out of the
 * listing.
 * @param {Array<object>} accounts from listAccounts
 * @param {{only: ?string, createdBefore: ?string}} f
 * @return {{selected: Array<object>, kept: Array<object>}}
 */
function select(accounts, f) {
  const before = f.createdBefore ? Date.parse(f.createdBefore) : NaN;
  const onlyKind = f.only ? (ONLY[f.only] || f.only) : null;
  const selected = [];
  const kept = [];
  for (const a of accounts) {
    let keep = PURGEABLE.indexOf(a.kind) < 0;
    let why = a.reason;
    if (!keep && onlyKind && a.kind !== onlyKind) {
      keep = true;
      why = `${a.reason}; left out by --only=${f.only}`;
    }
    if (!keep && !isNaN(before) && a.createdAt &&
        Date.parse(a.createdAt) >= before) {
      keep = true;
      why = `${a.reason}; created ${a.createdAt}, not before ` +
        `--created-before=${f.createdBefore}`;
    }
    if (keep) kept.push(Object.assign({}, a, {reason: why}));
    else selected.push(a);
  }
  return {selected, kept};
}

/** Counts-only view of one delete_participant.js receipt. */
function volume(receipt) {
  const firestore = {};
  let docs = 0;
  for (const g of receipt.found.firestore) {
    if (g.count) {
      firestore[g.location] = g.count;
      docs += g.count;
    }
  }
  const exportRows = receipt.found.exports
      .reduce((n, e) => n + e.rows, 0);
  return {
    auth: receipt.found.auth,
    firestoreDocs: docs,
    firestore,
    storageUserFiles: receipt.found.storageUserFiles,
    exportRows,
  };
}

/**
 * List, optionally delete, and build the run log.
 * @param {{db: object, auth: object, bucket: object, confirm: boolean,
 *   only: ?string, keep: string[], createdBefore: ?string,
 *   rewriteExports: boolean, volumes: boolean, operator: ?string,
 *   target: string, now: (Date|undefined)}} ctx
 * @return {Promise<object>} the run log (also written to admin_runs when
 *   confirm is true)
 */
async function run(ctx) {
  const now = ctx.now || new Date();
  const accounts = await listAccounts(ctx);
  const {selected, kept} = select(accounts,
      {only: ctx.only || null, createdBefore: ctx.createdBefore || null});
  const wantVolumes = ctx.volumes !== false;

  const rows = [];
  const receipts = {};
  for (const a of selected) {
    const row = {uid: a.uid, kind: a.kind, reason: a.reason,
      hasAuth: a.hasAuth, hasUserDoc: a.hasUserDoc, arm: a.arm,
      createdAt: a.createdAt};
    if (ctx.confirm) {
      // delete_participant.js scans before deleting, so its receipt
      // already carries the volume.
      const r = await deletion.run({db: ctx.db, auth: ctx.auth,
        bucket: ctx.bucket, uid: a.uid, confirm: true,
        rewriteExports: ctx.rewriteExports === true, now});
      receipts[a.uid] = r;
      row.volume = volume(r);
      row.deleted = true;
      row.verified = r.verified === true;
    } else {
      if (wantVolumes) {
        const dry = await deletion.run({db: ctx.db, auth: ctx.auth,
          bucket: ctx.bucket, uid: a.uid, confirm: false,
          rewriteExports: false, now});
        row.volume = volume(dry);
      }
      row.deleted = false;
    }
    rows.push(row);
  }

  const byKind = {};
  for (const a of accounts) byKind[a.kind] = (byKind[a.kind] || 0) + 1;
  const log = {
    tool: 'tool/purge_tester_data.js',
    mode: ctx.confirm ? 'confirm' : 'list-only',
    target: ctx.target || 'unknown',
    at: now.toISOString(),
    operator: ctx.operator || null,
    filters: {only: ctx.only || null, keep: ctx.keep || [],
      createdBefore: ctx.createdBefore || null,
      rewriteExports: ctx.rewriteExports === true},
    accountsSeen: accounts.length,
    byKind,
    selected: rows,
    kept: kept.map((a) => ({uid: a.uid, kind: a.kind, reason: a.reason})),
    allVerified: ctx.confirm ? rows.every((r) => r.verified) : null,
    notCovered: deletion.NOT_COVERED,
  };
  if (ctx.confirm) {
    const ref = await ctx.db.collection('admin_runs').add(log);
    log.adminRunId = ref.id;
  }
  return {log, receipts};
}

function fmtVolume(v) {
  if (!v) return '';
  return `auth ${v.auth}, firestore ${v.firestoreDocs}, ` +
    `storage ${v.storageUserFiles}, export rows ${v.exportRows}`;
}

function print(log) {
  console.log(`${log.mode === 'confirm' ? 'DELETED' : 'Would delete'} ` +
      `${log.selected.length} account(s); kept ${log.kept.length}; ` +
      `${log.accountsSeen} seen (${JSON.stringify(log.byKind)}). ` +
      `Target: ${log.target}.`);
  for (const r of log.selected) {
    console.log(`  ${r.deleted ? (r.verified ? 'OK  ' : 'FAIL') : '    '} ` +
        `${r.uid}  ${r.kind} (${r.reason})` +
        (r.arm ? `  arm=${r.arm}` : '') +
        (r.volume ? `  [${fmtVolume(r.volume)}]` : ''));
    if (r.volume) {
      for (const [loc, n] of Object.entries(r.volume.firestore)) {
        console.log(`           ${loc}  ${n}`);
      }
    }
  }
  if (log.kept.length) console.log('Kept (never touched):');
  for (const k of log.kept) {
    console.log(`  keep ${k.uid}  ${k.kind} (${k.reason})`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const confirm = args.confirm === true;
  const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  let target = 'emulator';
  let projectId = typeof args.project === 'string' ? args.project :
    (process.env.GCLOUD_PROJECT || PROJECT);
  if (!emulator) {
    const t = checkTarget(process.env, args);
    if (!t.ok) {
      console.error(`Refusing: ${t.reason}`);
      process.exit(2);
    }
    target = t.target;
    projectId = t.projectId;
    if (confirm && args.production !== true) {
      console.error('Not on the emulator: --confirm also needs ' +
          '--production (plus --project and --production-confirm).');
      process.exit(2);
    }
  } else if (args['production-confirm'] || args.production) {
    console.error('FIRESTORE_EMULATOR_HOST is set but a production flag ' +
        'was given; refusing an ambiguous target.');
    process.exit(2);
  }
  if (args.only && !ONLY[args.only]) {
    console.error(`--only must be one of ${Object.keys(ONLY).join(', ')}.`);
    process.exit(2);
  }
  admin.initializeApp({projectId,
    storageBucket: args.bucket || DEFAULT_BUCKET});
  const keep = typeof args.keep === 'string' ?
    args.keep.split(',').map((s) => s.trim()).filter(Boolean) : [];
  const {log, receipts} = await run({
    db: admin.firestore(), auth: admin.auth(),
    bucket: admin.storage().bucket(),
    confirm, only: typeof args.only === 'string' ? args.only : null, keep,
    createdBefore: typeof args['created-before'] === 'string' ?
      args['created-before'] : null,
    rewriteExports: confirm && args['rewrite-exports'] === true,
    volumes: args['no-volumes'] !== true,
    operator: typeof args.operator === 'string' ? args.operator : null,
    target,
  });
  print(log);
  const path = typeof args.receipt === 'string' ? args.receipt :
    `purge-tester-receipt-${log.at.replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(path, JSON.stringify({log, receipts}, null, 2));
  console.log(`Log: ${path}` +
      (log.adminRunId ? `; admin_runs/${log.adminRunId}` : ''));
  if (confirm && !log.allVerified) {
    console.error('Verification FAILED for at least one account; see the ' +
        'per-user receipts in the log file.');
    process.exit(1);
  }
  if (!confirm) {
    console.log('Nothing was deleted. Re-run with --confirm' +
        (emulator ? '' : ' --production --project=<id> ' +
          '--production-confirm=<id>') + ' to delete.');
  }
}

module.exports = {run, listAccounts, classify, select, volume, KINDS,
  PURGEABLE, ONLY, STAFF_ROLES};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

#!/usr/bin/env node
/**
 * tool/delete_participant.js
 *
 * Deletes ONE participant's data everywhere the code writes it — for
 * withdrawal under the ICF (SPEC:C20, decision 0020). Covers:
 *
 *   Auth       the Firebase Auth account
 *   Firestore  users/{uid} and EVERY subcollection under it, found by
 *              walking the tree (so nothing is missed if a new
 *              subcollection appears): profile, intake, sessions, turns,
 *              events, surveys, memory v0 + v1, action plans, reminders…
 *              Top-level collections, by the field that holds the uid:
 *              llm_calls, safety_events, safety_event_dedup, pi_alerts,
 *              te_audit_queue, stt_usage, safety_classifier_calls (T8,
 *              may not exist yet), pending_loneliness_probes (doc id or
 *              uid field), hotline_filter_log (T7), research_id_map
 *              (doc id) and research_ids (T12).
 *   Storage    any file under users/{uid}/ (the App writes none today);
 *              rows in the weekly blinded exports exports/{date}/*.ndjson
 *              — see "Exports" below.
 *
 * Not reachable from here (listed in the receipt as "not covered"):
 * Cloud Logging lines, data DeepSeek / Brave keep on their side, local
 * copies made with tool/admin_dump.js, the phone's Firestore cache,
 * meta/arm_counter (counts only, kept as the randomisation record).
 * There is no vector index in this codebase, so nothing to delete there.
 *
 * Exports: each weekly export is one file per collection holding every
 * participant. Rows of this person are found by uidHash (recomputed from
 * export_blind_keys/{date}.salt), participantId or any field equal to the
 * uid. They are only COUNTED; the files are not touched — decision
 * 0020: de-identified exported data already used for analysis is kept.
 * --rewrite-exports (with --confirm) rewrites each file without those
 * rows; NOT the default, only if the research team decides otherwise.
 *
 * Dry run by default: lists what would be deleted. --confirm deletes,
 * scans again and fails unless nothing is left. Either way a receipt
 * (JSON: counts per location, no field values, no text) is written.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   NODE_PATH=functions/node_modules node tool/delete_participant.js \
 *       --uid=abc123                       # dry run
 *   ... --uid=abc123 --confirm --production
 *   ... --email=x@hku.hk --confirm --production --rewrite-exports
 * Options: --bucket=<name> (default loneliness-pilot-dev.firebasestorage.app)
 *          --receipt=<path> (default ./deletion-receipt-<uid>-<time>.json)
 * Outside the emulator, --confirm also needs --production.
 */

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const admin = require('firebase-admin');

const PROJECT = 'loneliness-pilot-dev';
const DEFAULT_BUCKET = 'loneliness-pilot-dev.firebasestorage.app';

/** Top-level collections and the field that names the participant. */
const TOP_LEVEL = [
  {collection: 'llm_calls', field: 'uid'},
  {collection: 'safety_events', field: 'uid'},
  {collection: 'safety_event_dedup', field: 'uid'},
  {collection: 'pi_alerts', field: 'uid'},
  {collection: 'te_audit_queue', field: 'uid'},
  {collection: 'stt_usage', field: 'uid'},
  {collection: 'safety_classifier_calls', field: 'uid'},
  {collection: 'pending_loneliness_probes', field: 'uid', docIdIsUid: true},
  // T7 (decision 0018): one row per reply whose phone numbers were replaced.
  {collection: 'hotline_filter_log', field: 'uid'},
  // T12 (decision 0021): research-ID lookup, both directions.
  {collection: 'research_id_map', field: 'uid', docIdIsUid: true},
  {collection: 'research_ids', field: 'uid'},
];

const NOT_COVERED = [
  'Cloud Logging (function logs may name the uid; follow the project ' +
      'log retention)',
  'DeepSeek / Brave Search copies (provider terms)',
  'local JSON made with tool/admin_dump.js on researcher machines',
  'Firestore offline cache on the participant\'s phone (uninstall the App)',
  'meta/arm_counter (counts only, kept as the randomisation record)',
  'vector index: none exists in this codebase',
];

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

/** Same as hashUid in functions/index.js (blindedDataExport). */
function hashUid(uid, salt) {
  return crypto.createHash('sha256').update(`${salt}|${uid}`, 'utf8')
      .digest('hex').slice(0, 16);
}

/** Path with ids replaced, so the receipt groups docs by kind. */
function pattern(path, uid) {
  const parts = path.split('/');
  return parts.map((p, i) => {
    if (i % 2 === 0) return p; // collection name
    if (p === uid) return '{uid}';
    return '*';
  }).join('/');
}

/**
 * Every existing document under ref, depth first. listDocuments() also
 * returns "missing" parents that only hold subcollections (for example
 * memory/{moduleId}); those are walked but not counted.
 */
async function walk(ref, out) {
  for (const col of await ref.listCollections()) {
    const existing = new Set((await col.get()).docs.map((d) => d.ref.path));
    for (const doc of await col.listDocuments()) {
      await walk(doc, out);
      if (existing.has(doc.path)) out.push(doc);
    }
  }
  return out;
}

async function firestorePlan(db, uid) {
  const userRef = db.collection('users').doc(uid);
  const refs = await walk(userRef, []);
  if ((await userRef.get()).exists) refs.push(userRef);

  const groups = {};
  const add = (key, how, ref) => {
    if (!groups[key]) groups[key] = {location: key, matchedBy: how, refs: []};
    groups[key].refs.push(ref);
  };
  for (const r of refs) {
    add(pattern(r.path, uid), 'path users/{uid}/…', r);
  }
  for (const t of TOP_LEVEL) {
    const key = t.collection;
    const how = t.docIdIsUid ? `doc id = uid, or ${t.field} = uid` :
      `${t.field} = uid`;
    const seen = new Set();
    const snap = await db.collection(t.collection)
        .where(t.field, '==', uid).get();
    for (const d of snap.docs) {
      seen.add(d.ref.path);
      add(key, how, d.ref);
    }
    if (t.docIdIsUid) {
      const d = await db.collection(t.collection).doc(uid).get();
      if (d.exists && !seen.has(d.ref.path)) add(key, how, d.ref);
    }
    if (!groups[key]) groups[key] = {location: key, matchedBy: how, refs: []};
  }
  return Object.values(groups);
}

async function authPlan(auth, uid) {
  try {
    await auth.getUser(uid);
    return 1;
  } catch (err) {
    if (err && err.code === 'auth/user-not-found') return 0;
    throw err;
  }
}

function rowMatches(line, uid, uidHash) {
  if (!line.trim()) return false;
  let row;
  try {
    row = JSON.parse(line);
  } catch (_) {
    return line.includes(uid);
  }
  if (uidHash && row.uidHash === uidHash) return true;
  if (row.participantId === uid || row.uid === uid) return true;
  // Paths such as thought_exercise.originTurnRef carry the raw uid.
  return line.includes(uid);
}

async function storagePlan(db, bucket, uid) {
  const [userFiles] = await bucket.getFiles({prefix: `users/${uid}/`});
  const [exportFiles] = await bucket.getFiles({prefix: 'exports/'});
  const salts = {};
  const exportsOut = [];
  for (const f of exportFiles) {
    const m = f.name.match(/^exports\/([^/]+)\/(.+)$/);
    if (!m) continue;
    const date = m[1];
    if (!(date in salts)) {
      const k = await db.collection('export_blind_keys').doc(date).get();
      salts[date] = k.exists ? k.get('salt') || null : null;
    }
    const uidHash = salts[date] ? hashUid(uid, salts[date]) : null;
    const [buf] = await f.download();
    const lines = buf.toString('utf8').split('\n');
    const hits = lines.filter((l) => rowMatches(l, uid, uidHash)).length;
    if (hits) {
      exportsOut.push({file: f, name: f.name, rows: hits,
        saltFound: Boolean(salts[date])});
    }
  }
  return {userFiles, exports: exportsOut};
}

async function rewriteExport(file, uid, uidHash) {
  const [buf] = await file.download();
  const [meta] = await file.getMetadata();
  const kept = buf.toString('utf8').split('\n')
      .filter((l) => l.trim() && !rowMatches(l, uid, uidHash));
  const custom = Object.assign({}, meta.metadata || {},
      {rowCount: String(kept.length), rewrittenForDeletion: 'true'});
  await file.save(kept.join('\n'), {
    resumable: false,
    contentType: meta.contentType || 'application/x-ndjson',
    metadata: {metadata: custom},
  });
}

async function deleteRefs(db, refs) {
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    for (const r of refs.slice(i, i + 400)) batch.delete(r);
    await batch.commit();
  }
}

async function scan(ctx) {
  const {db, auth, bucket, uid} = ctx;
  return {
    firestore: await firestorePlan(db, uid),
    auth: await authPlan(auth, uid),
    storage: await storagePlan(db, bucket, uid),
  };
}

function summarise(plan) {
  return {
    auth: plan.auth,
    firestore: plan.firestore
        .map((g) => ({location: g.location, matchedBy: g.matchedBy,
          count: g.refs.length}))
        .sort((a, b) => a.location.localeCompare(b.location)),
    storageUserFiles: plan.storage.userFiles.length,
    exports: plan.storage.exports.map((e) => ({file: e.name, rows: e.rows,
      saltFound: e.saltFound})),
  };
}

function total(sum) {
  return sum.auth + sum.storageUserFiles +
      sum.firestore.reduce((n, g) => n + g.count, 0) +
      sum.exports.reduce((n, e) => n + e.rows, 0);
}

/**
 * Plan, optionally delete, verify; returns the receipt object.
 * @param {{db: object, auth: object, bucket: object, uid: string,
 *   confirm: boolean, rewriteExports: boolean, now: (Date|undefined)}} ctx
 * @return {Promise<object>}
 */
async function run(ctx) {
  const {db, auth, bucket, uid, confirm, rewriteExports} = ctx;
  const before = await scan(ctx);
  const found = summarise(before);
  const receipt = {
    tool: 'tool/delete_participant.js',
    mode: confirm ? 'confirm' : 'dry-run',
    uid,
    at: (ctx.now || new Date()).toISOString(),
    found,
    exportsPolicy: rewriteExports ? 'rewritten without this participant' :
      'counted only, files not modified',
    notCovered: NOT_COVERED,
  };
  if (!confirm) return receipt;

  for (const g of before.firestore) await deleteRefs(db, g.refs);
  if (before.auth) await auth.deleteUser(uid);
  for (const f of before.storage.userFiles) await f.delete();
  if (rewriteExports) {
    for (const e of before.storage.exports) {
      const date = e.name.split('/')[1];
      const k = await db.collection('export_blind_keys').doc(date).get();
      const salt = k.exists ? k.get('salt') : null;
      await rewriteExport(e.file, uid, salt ? hashUid(uid, salt) : null);
    }
  }

  const after = summarise(await scan(ctx));
  const left = total(after) -
      (rewriteExports ? 0 : after.exports.reduce((n, e) => n + e.rows, 0));
  receipt.remaining = after;
  receipt.verified = left === 0;
  return receipt;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const confirm = args.confirm === true;
  const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (confirm && !emulator && args.production !== true) {
    console.error('Not on the emulator: add --production to really delete.');
    process.exit(2);
  }
  if (args['rewrite-exports'] && !confirm) {
    console.error('--rewrite-exports only applies with --confirm.');
  }
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || PROJECT,
    storageBucket: args.bucket || DEFAULT_BUCKET,
  });
  const db = admin.firestore();
  const auth = admin.auth();
  let uid = args.uid;
  if (!uid && args.email) uid = (await auth.getUserByEmail(args.email)).uid;
  if (!uid || typeof uid !== 'string') {
    console.error('Need --uid=<uid> or --email=<email>.');
    process.exit(2);
  }
  const receipt = await run({db, auth, bucket: admin.storage().bucket(), uid,
    confirm, rewriteExports: confirm && args['rewrite-exports'] === true});
  const path = typeof args.receipt === 'string' ? args.receipt :
    `deletion-receipt-${uid}-${receipt.at.replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(path, JSON.stringify(receipt, null, 2));
  const keptRows = receipt.exportsPolicy.startsWith('counted') ?
    receipt.found.exports.reduce((m, e) => m + e.rows, 0) : 0;
  const n = total(receipt.found) - keptRows;
  console.log(`${confirm ? 'Deleted' : 'Dry run — would delete'} ${n} ` +
      `item(s) for ${uid}` +
      (keptRows ? `; ${keptRows} export row(s) left in place` : '') +
      `. Receipt: ${path}`);
  for (const g of receipt.found.firestore) {
    if (g.count) console.log(`  ${g.location}  ${g.count}`);
  }
  console.log(`  auth account  ${receipt.found.auth}`);
  for (const e of receipt.found.exports) {
    console.log(`  ${e.file}  ${e.rows} row(s)` +
        (receipt.exportsPolicy.startsWith('counted') ? ' (not modified)' : ''));
  }
  if (confirm && !receipt.verified) {
    console.error('Verification FAILED: data left, see receipt.remaining.');
    process.exit(1);
  }
  if (!confirm) console.log('Re-run with --confirm to delete.');
}

module.exports = {run, hashUid, rowMatches, pattern, TOP_LEVEL};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

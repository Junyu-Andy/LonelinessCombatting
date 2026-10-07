#!/usr/bin/env node
/**
 * tool/delete_memory.js
 *
 * Deletes a participant's companion memory — for withdrawal, or for every
 * participant once the ICF retention period ends (3 years after the study).
 * It never touches research measures (turns, sessions, surveys, mood,
 * safety events); only what the companions remember:
 *
 *   memory v1  mem_facts, mem_summaries, mem_followups,
 *              mem_injections, mem_extractions
 *   memory v0  agent_contexts (rolling summary + short-term buffer),
 *              memory/{moduleId}/entries, shared_context, agent_greetings,
 *              cross_module_callbacks
 *
 * Dry run by default: prints what it would delete. Add --confirm to delete.
 *
 * With --confirm it also turns memory off for the user: memory_enabled
 * false and memoryWithdrawnAt (T10, decision 0024). The server honours
 * memoryWithdrawnAt even for Phase B Arm A, where memory is otherwise
 * mandatory, so nothing new is recorded afterwards (meta/memory_config
 * .honourMemoryWithdrawal, default on). To clear memory but keep it
 * running (e.g. test accounts), add --keep-memory-on.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node tool/delete_memory.js --uid=abc123            # dry run, one user
 *   node tool/delete_memory.js --email=x@hku.hk --confirm
 *   node tool/delete_memory.js --all --confirm          # 3 years after study
 *
 * Needs the firebase-admin package (cd functions && npm ci, then run with
 * NODE_PATH=functions/node_modules).
 */

'use strict';

const admin = require('firebase-admin');

const FLAT = [
  'mem_facts',
  'mem_summaries',
  'mem_followups',
  'mem_injections',
  'mem_extractions',
  'agent_contexts',
  'shared_context',
  'agent_greetings',
  'cross_module_callbacks',
];

function parseArgs() {
  const out = {};
  for (const a of process.argv.slice(2)) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

async function deleteDocs(db, refs, confirm) {
  for (let i = 0; i < refs.length; i += 400) {
    if (!confirm) continue;
    const batch = db.batch();
    for (const r of refs.slice(i, i + 400)) batch.delete(r);
    await batch.commit();
  }
  return refs.length;
}

async function memoryRefs(userRef) {
  const refs = [];
  const counts = {};
  for (const name of FLAT) {
    const docs = await userRef.collection(name).listDocuments();
    counts[name] = docs.length;
    refs.push(...docs);
  }
  // v0 module summaries: memory/{moduleId}/entries/* and
  // memory/m3_reminiscence/sessions/* — the module docs themselves too.
  let nested = 0;
  for (const moduleDoc of await userRef.collection('memory').listDocuments()) {
    for (const sub of await moduleDoc.listCollections()) {
      const docs = await sub.listDocuments();
      nested += docs.length;
      refs.push(...docs);
    }
    refs.push(moduleDoc);
  }
  counts['memory/*'] = nested;
  return {refs, counts};
}

async function forUser(db, uid, confirm, keepOn) {
  const userRef = db.collection('users').doc(uid);
  const {refs, counts} = await memoryRefs(userRef);
  const n = await deleteDocs(db, refs, confirm);
  if (confirm && keepOn) {
    await userRef.set({memoryDeletedAt: new Date()}, {merge: true});
  } else if (confirm) {
    // Turn memory off so nothing new is extracted for a withdrawn user.
    const now = new Date();
    await userRef.set({memory_enabled: false, memoryDeletedAt: now,
      memoryWithdrawnAt: now}, {merge: true});
  }
  console.log(`${confirm ? 'deleted' : 'would delete'} ${n} docs for ${uid}`,
      JSON.stringify(counts));
  return n;
}

async function main() {
  const args = parseArgs();
  const confirm = args.confirm === true;
  admin.initializeApp();
  const db = admin.firestore();

  let uids;
  if (args.all) {
    uids = (await db.collection('users').listDocuments()).map((d) => d.id);
  } else {
    let uid = args.uid;
    if (!uid && args.email) {
      uid = (await admin.auth().getUserByEmail(args.email)).uid;
    }
    if (!uid) {
      console.error('Need --uid=<uid>, --email=<email> or --all.');
      process.exit(2);
    }
    uids = [uid];
  }

  let total = 0;
  for (const uid of uids) {
    total += await forUser(db, uid, confirm, args['keep-memory-on'] === true);
  }
  console.log(`${confirm ? 'Deleted' : 'Dry run — would delete'} ${total} ` +
      `docs across ${uids.length} participant(s).` +
      (confirm ? '' : ' Re-run with --confirm to delete.'));
}

module.exports = {memoryRefs, forUser};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

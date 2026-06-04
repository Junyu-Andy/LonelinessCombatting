#!/usr/bin/env node
/**
 * tool/admin_dump.js
 *
 * T9 (Dev TestWeek) — per-user data dump for debugging internal tests.
 *
 * Pulls everything we look at when triaging a tester's session: the rolling
 * summaries + fold status, cross-module session memory, per-turn LLM
 * features (incl. latency), thumbs / tester feedback, and that user's
 * safety events. Read-only.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node tool/admin_dump.js --uid=abc123
 *   node tool/admin_dump.js --email=tester@hku.hk --out=dump.json
 *
 * Output: pretty JSON to stdout, or to --out=<file> when given.
 */

'use strict';

const fs = require('fs');
const admin = require('firebase-admin');

function parseArgs() {
  const out = {};
  for (const a of process.argv.slice(2)) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

async function dumpCollection(ref) {
  const snap = await ref.get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

// Recurse one level into known nested memory: memory/{moduleId}/entries/*.
async function dumpMemory(userRef) {
  const out = {};
  const modules = await userRef.collection('memory').get();
  for (const m of modules.docs) {
    out[m.id] = await dumpCollection(m.ref.collection('entries'));
  }
  return out;
}

async function main() {
  const args = parseArgs();
  admin.initializeApp();
  const db = admin.firestore();
  const auth = admin.auth();

  let uid = args.uid;
  if (!uid && args.email) {
    uid = (await auth.getUserByEmail(args.email)).uid;
  }
  if (!uid) {
    console.error('Need --uid=<uid> or --email=<email>.');
    process.exit(2);
  }

  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();

  // Per-user subcollections (the ones we triage during the test week).
  const subcollections = [
    'agent_contexts', // rollingSummary + lastFold* (T5)
    'shared_context',
    'llm_turn_features', // incl. latencyMs (T8)
    'tester_feedback', // 👎 with promptHash (T7)
    'response_feedback',
    'daily_mood',
    'brief_pr',
    'weekly_pr',
    'pgic',
    'agent_diff',
    'thought_exercise',
    'loneliness_probes',
  ];

  const dump = {
    uid,
    generatedAt: new Date().toISOString(),
    profile: userSnap.exists ? userSnap.data() : null,
    memory: await dumpMemory(userRef),
  };
  for (const sub of subcollections) {
    dump[sub] = await dumpCollection(userRef.collection(sub));
  }

  // Top-level safety_events are keyed by a uid field, not nested.
  dump.safety_events = (
    await db.collection('safety_events').where('uid', '==', uid).get()
  ).docs.map((d) => ({id: d.id, ...d.data()}));

  const json = JSON.stringify(dump, null, 2);
  if (args.out) {
    fs.writeFileSync(args.out, json);
    console.error(`Wrote ${args.out} (${json.length} bytes).`);
  } else {
    process.stdout.write(json + '\n');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

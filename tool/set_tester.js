#!/usr/bin/env node
/**
 * tool/set_tester.js — set or clear `users/{uid}.isTester` (1014e §2.3,
 * backlog 96).  Since this change the flag is admin-only: the Firestore
 * rules refuse any client write, so the App's old tester switch is gone
 * and this script (Admin SDK) or the console is the only way.
 *
 * What the flag does: a tester account passes the enrolment gate without
 * a cohort, is excluded from exports and the dashboards' numbers, and its
 * acute safety events are logged but not e-mailed (T34).  Set it on the
 * team's and the assessors' accounts BEFORE the enrolment gate opens;
 * never on a PILOT- or PB- participant.
 *
 * Usage (emulator by default; a real project needs --project and
 * --production-confirm, see tool/firestore_target.js):
 *   node tool/set_tester.js --uid=<uid> --tester=true
 *   node tool/set_tester.js --email=<login e-mail> --tester=false \
 *     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
 *   node tool/set_tester.js --list            # every account with isTester
 *
 * Refuses an account that is registered (enrollments/{uid} exists) unless
 * --allow-registered is given, so a participant is not flagged by mistake.
 */
'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');

/**
 * @param {object} db admin.firestore()
 * @param {?object} auth admin.auth() (needed for --email)
 * @param {object} args parsed flags
 * @param {{log: function(string)}} out
 * @return {Promise<{uid: ?string, isTester: ?boolean, listed: ?number}>}
 */
async function run(db, auth, args, out) {
  const log = (out && out.log) || console.log;
  if (args.list) {
    const snap = await db.collection('users').where('isTester', '==', true)
        .get();
    for (const d of snap.docs) {
      log(`${d.id}\t${d.get('email') || ''}\t${d.get('displayName') || ''}`);
    }
    log(`${snap.size} tester account(s)`);
    return {uid: null, isTester: null, listed: snap.size};
  }
  let uid = typeof args.uid === 'string' ? args.uid : null;
  if (!uid && typeof args.email === 'string') {
    if (!auth) throw new Error('--email needs Auth (admin.auth())');
    const user = await auth.getUserByEmail(args.email);
    uid = user.uid;
  }
  if (!uid) throw new Error('give --uid=<uid> or --email=<e-mail>');
  if (args.tester !== 'true' && args.tester !== 'false') {
    throw new Error('give --tester=true or --tester=false');
  }
  const value = args.tester === 'true';
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new Error(`users/${uid} does not exist`);
  const enrolled = await db.collection('enrollments').doc(uid).get();
  if (value && enrolled.exists && !args['allow-registered']) {
    throw new Error(`users/${uid} is a registered participant ` +
      `(${enrolled.get('researchId') || 'enrollments row'}); refusing to ` +
      'flag it as a tester (add --allow-registered to override)');
  }
  await ref.set({isTester: value}, {merge: true});
  log(`users/${uid}.isTester = ${value}`);
  return {uid, isTester: value, listed: null};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`set_tester: ${t.reason}`);
    process.exit(2);
  }
  console.log(`set_tester: target = ${t.reason}`);
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  try {
    await run(admin.firestore(), admin.auth(), args);
  } catch (err) {
    console.error(`set_tester: ${err.message}`);
    process.exit(2);
  }
}

module.exports = {run};

if (require.main === module) main();

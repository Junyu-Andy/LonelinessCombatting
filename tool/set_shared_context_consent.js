#!/usr/bin/env node
/**
 * tool/set_shared_context_consent.js
 *
 * Sets users/{uid}.consent.sharedContextUse from the back end (decision
 * 0020). The participant has no switch for it in the App: new accounts get
 * it on from the consent page; a participant who does not want the three
 * companions to share basic information asks the research team, who run
 * this script.
 *
 *   --all            every existing account → true (one-off migration;
 *                    run BEFORE deploying the version that enforces it,
 *                    or everyone's sharing stops that day)
 *   --uid=X --off    that one account → false
 *   --uid=X --on     that one account → true
 *
 * Only consent.sharedContextUse is written, plus two audit fields on the
 * user doc (sharedContextUseSetBy, sharedContextUseSetAt). Accounts already
 * at the target value are left alone.
 *
 * Dry run by default: lists what would change. --confirm writes. Outside
 * the emulator, --confirm also needs --production.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   NODE_PATH=functions/node_modules node tool/set_shared_context_consent.js --all
 *   ... --all --confirm --production
 *   ... --uid=abc123 --off --confirm --production
 */

'use strict';

const admin = require('firebase-admin');

const PROJECT = 'loneliness-pilot-dev';
const SCRIPT = 'tool/set_shared_context_consent.js';

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

function current(data) {
  const consent = (data && data.consent) || {};
  return consent.sharedContextUse === true;
}

/**
 * @param {{db: object, uids: ?Array<string>, value: boolean,
 *   confirm: boolean, now: (Date|undefined)}} opts uids null = every user
 * @return {Promise<{target: boolean, changed: Array<string>,
 *   unchanged: number, missing: Array<string>, written: boolean}>}
 */
async function run(opts) {
  const {db, uids, value, confirm} = opts;
  const snaps = [];
  const missing = [];
  if (uids) {
    for (const uid of uids) {
      const s = await db.collection('users').doc(uid).get();
      if (s.exists) snaps.push(s);
      else missing.push(uid);
    }
  } else {
    snaps.push(...(await db.collection('users').get()).docs);
  }
  const todo = snaps.filter((s) => current(s.data()) !== value);
  if (confirm) {
    const at = opts.now || new Date();
    for (let i = 0; i < todo.length; i += 400) {
      const batch = db.batch();
      for (const s of todo.slice(i, i + 400)) {
        batch.update(s.ref, {
          'consent.sharedContextUse': value,
          'sharedContextUseSetBy': SCRIPT,
          'sharedContextUseSetAt': at,
        });
      }
      await batch.commit();
    }
  }
  return {
    target: value,
    changed: todo.map((s) => s.id),
    unchanged: snaps.length - todo.length,
    missing,
    written: confirm,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const confirm = args.confirm === true;
  const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (confirm && !emulator && args.production !== true) {
    console.error('Not on the emulator: add --production to really write.');
    process.exit(2);
  }
  let uids = null;
  let value;
  if (args.all === true && !args.uid) {
    value = true;
  } else if (typeof args.uid === 'string' && args.uid &&
      (args.on === true) !== (args.off === true)) {
    uids = [args.uid];
    value = args.on === true;
  } else {
    console.error('Need --all, or --uid=<uid> with exactly one of --on/--off.');
    process.exit(2);
  }
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || PROJECT});
  const r = await run({db: admin.firestore(), uids, value, confirm});
  console.log(`${confirm ? 'Set' : 'Dry run — would set'} ` +
      `sharedContextUse=${value} on ${r.changed.length} account(s); ` +
      `${r.unchanged} already ${value}.`);
  for (const uid of r.changed) console.log(`  ${uid}`);
  for (const uid of r.missing) console.log(`  not found: ${uid}`);
  if (!confirm && r.changed.length) console.log('Re-run with --confirm.');
  if (r.missing.length) process.exit(1);
}

module.exports = {run};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

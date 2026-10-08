#!/usr/bin/env node
/**
 * tool/prelaunch_config.js — write the server switches Phase B needs
 * (T13, decision 0022; T19, decision 0029).  Without them the Hybrid arm
 * has no memory and nobody can be registered and allocated.
 *
 *   meta/memory_config          {enabled: true, policy: "C", phaseBArmA: true}
 *   meta/randomization_config   {enabled: true, stratification, method}
 *
 * It also CHECKS (never writes) that the unblinded researcher has uploaded
 * both allocation sequences (randomization_sequences/{low,high}, at least
 * 60 positions, nothing allocated yet before launch).  It prints only the
 * lengths and fingerprints, never the arms, so the PI may run it.  The
 * upload itself is tool/randomization_sequence.js, run by the unblinded
 * researcher.
 *
 * T19 retired app_config/arm_assignment.randomise and meta/arm_counter
 * (minimisation); the script reports if the old flag is still on.
 *
 * SAFETY — refuses by default unless it is talking to the Firestore
 * emulator (FIRESTORE_EMULATOR_HOST set).  The real project id
 * (loneliness-pilot-dev) is also the id the emulator tests use, so the id
 * alone proves nothing; the emulator variable is the test.  Running
 * against a real project needs BOTH --project=<id> and
 * --production-confirm=<same id>, and is meant for the PI/research team
 * on launch day, following docs/release/prelaunch-checklist.md.
 *
 * Dry run by default: prints what is there and what it would write.
 * Add --apply to write.  An existing doc with different values is never
 * replaced unless --overwrite is given.
 *
 * Usage (emulator):
 *   firebase emulators:exec --only firestore --project demo-prelaunch \
 *     "NODE_PATH=functions/node_modules node tool/prelaunch_config.js \
 *      --phase=b --apply"
 *
 * Needs firebase-admin (cd functions && npm ci; run with
 * NODE_PATH=functions/node_modules).
 */

'use strict';

const DESIRED = {
  'meta/memory_config': {enabled: true, policy: 'C', phaseBArmA: true},
  // Stratification and method are fixed in functions/randomization.js;
  // they are written here so the config snapshot records them.
  'meta/randomization_config': {
    enabled: true,
    stratifyBy: 'w0_djg_emotional',
    strata: 'low=0-1,high=2-3',
    method: 'permuted_block_v1',
    blockSizes: '2,4',
  },
};
const STRATA = ['low', 'high'];
const MIN_SEQUENCE_LENGTH = 60;

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

/**
 * Decide whether we may run, and against what.  Pure, for tests.
 * @return {{ok: boolean, reason: string, target?: string,
 *     projectId?: string}}
 */
function checkTarget(env, args) {
  if (args.phase !== 'b') {
    return {ok: false, reason: 'pass --phase=b (only Phase B is supported)'};
  }
  if (env.FIRESTORE_EMULATOR_HOST) {
    if (args['production-confirm']) {
      return {ok: false, reason: '--production-confirm given but ' +
        'FIRESTORE_EMULATOR_HOST is set; refusing an ambiguous target'};
    }
    return {
      ok: true,
      reason: `emulator at ${env.FIRESTORE_EMULATOR_HOST}`,
      target: 'emulator',
      projectId: args.project || env.GCLOUD_PROJECT || 'demo-prelaunch',
    };
  }
  const project = typeof args.project === 'string' ? args.project : '';
  if (!project) {
    return {ok: false, reason: 'not on the emulator ' +
      '(FIRESTORE_EMULATOR_HOST unset) and no --project; refusing'};
  }
  if (project.startsWith('demo-')) {
    return {ok: false, reason: `${project} is a demo- project: it only ` +
      'exists in the emulator; set FIRESTORE_EMULATOR_HOST'};
  }
  if (args['production-confirm'] !== project) {
    return {ok: false, reason: `refusing to touch real project ${project}. ` +
      'Run on the emulator, or (launch day only, per ' +
      'docs/release/prelaunch-checklist.md) add ' +
      `--production-confirm=${project}`};
  }
  return {ok: true, reason: `REAL PROJECT ${project}`, target: 'production',
    projectId: project};
}

function sameValues(existing, desired) {
  return Object.keys(desired).every((k) => existing[k] === desired[k]);
}

/**
 * Plan + optionally apply.  Returns a list of lines and an ok flag.
 */
async function run(db, args, log) {
  const apply = args.apply === true;
  let ok = true;
  for (const [path, desired] of Object.entries(DESIRED)) {
    const snap = await db.doc(path).get();
    const existing = snap.exists ? snap.data() : null;
    if (existing && sameValues(existing, desired)) {
      log(`= ${path}: already ${JSON.stringify(desired)}`);
      continue;
    }
    if (existing && !args.overwrite) {
      log(`! ${path}: exists with different values ` +
        `${JSON.stringify(existing)}; not replaced (add --overwrite)`);
      ok = false;
      continue;
    }
    log(`${apply ? '+' : '~'} ${path}: ${existing ? 'update' : 'create'} ` +
      `${JSON.stringify(desired)}${apply ? '' : ' (dry run)'}`);
    if (apply) {
      await db.doc(path).set({
        ...desired,
        configuredBy: 'tool/prelaunch_config.js',
        configuredAt: new Date(),
      }, {merge: true});
    }
  }

  // Sequences: check only.  Never print the arms.
  for (const st of STRATA) {
    const seq = await db.doc(`randomization_sequences/${st}`).get();
    const state = await db.doc(`randomization_state/${st}`).get();
    if (!seq.exists) {
      log(`! randomization_sequences/${st}: not uploaded — the unblinded ` +
        'researcher runs tool/randomization_sequence.js --upload');
      ok = false;
      continue;
    }
    const len = Number(seq.get('length')) || 0;
    const used = state.exists ? Number(state.get('next')) || 0 : 0;
    const fp = String(seq.get('sha256') || '').slice(0, 12);
    if (len < MIN_SEQUENCE_LENGTH) {
      log(`! randomization_sequences/${st}: only ${len} positions ` +
        `(need ${MIN_SEQUENCE_LENGTH})`);
      ok = false;
      continue;
    }
    log(`= randomization_sequences/${st}: ${len} positions, ${used} used, ` +
      `fingerprint ${fp}…`);
  }

  const legacy = await db.doc('app_config/arm_assignment').get();
  if (legacy.exists && legacy.get('randomise') === true) {
    log('note app_config/arm_assignment.randomise is still true: retired ' +
      'in T19 and ignored while meta/randomization_config.enabled is on; ' +
      'delete it in the console');
  }
  return ok;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`prelaunch_config: ${t.reason}`);
    process.exit(2);
  }
  console.log(`prelaunch_config: target = ${t.reason} ` +
    `(project ${t.projectId})${args.apply ? '' : ' — DRY RUN'}`);
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const ok = await run(admin.firestore(), args, (l) => console.log(l));
  process.exit(ok ? 0 : 1);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {DESIRED, parseArgs, checkTarget, run};

#!/usr/bin/env node
/**
 * tool/randomization_sequence.js — T19 (decision 0029), reworked in T30
 * (dev-tasks-1010 §四 T30 §2.4; dev-tasks-1014 §二 rule 9).  Run ONLY by
 * the person holding the `sequence_uploader` role (the study member with
 * no other role; 10/19: Qingyang Li for v2), on their own machine.  Junyu
 * does not generate, upload or see the sequence; the seed never leaves
 * that machine.  Steps for v2: docs/release/sequence-v2-upload-20261020.md.
 *
 * Generates one permuted-block sequence per stratum (low = W0 DJG
 * emotional 0–1, high = 2–3) from a seed the uploader chooses: 1:1,
 * blocks of 2 and 4 mixed at random, at least 80 positions each by
 * default (functions/randomization.js generateSequences).  Same seed →
 * same sequences, so the offline copy can be re-checked — and v2 MUST use
 * a NEW seed: the server refuses a v2 that repeats v1 (same_seed_as_v1).
 *
 * Steps
 *   1. generate  — writes ONE file with the seed and both sequences into
 *                  randomization-private/ (git-ignored).  Prints only the
 *                  lengths and SHA-256 fingerprints, never the arms.
 *                  Hand that file to the supervisor's offline store, then
 *                  delete it from the laptop.
 *   2. --upload --version=v2 — signs the uploader in with THEIR OWN App
 *                  login (e-mail + password, Firebase Auth REST) and calls
 *                  the uploadRandomizationSequence Cloud Function with the
 *                  version and the two sequences (arms, blocks,
 *                  fingerprints — no seed).  The server checks the role
 *                  (`sequence_uploader`), the switch
 *                  meta/randomization_config.sequenceUploadEnabled, the
 *                  version (v2), ≥ 80 positions, that nobody has been
 *                  allocated from v2 and that v2 does not repeat v1, and
 *                  logs the upload.  NO service-account credentials.
 *
 * Targets
 *   emulator (default): FIREBASE_AUTH_EMULATOR_HOST and
 *     FUNCTIONS_EMULATOR_HOST (e.g. localhost:9099 / localhost:5001) set.
 *   real project: --project=<id> --production-confirm=<same id>
 *     (and neither emulator variable set).
 *
 * Usage
 *   NODE_PATH=functions/node_modules node tool/randomization_sequence.js \
 *     --seed-file=/path/to/new-seed.txt [--length=80] [--out=randomization-private]
 *   ... --seed-file=... --upload --version=v2 --email=uploader@example.org \
 *       --password-file=/path/to/pw.txt [--replace]
 *   ... (real project) --project=loneliness-pilot-dev \
 *       --production-confirm=loneliness-pilot-dev [--api-key=<web API key>]
 *
 * --seed=<text> also works but leaves the seed in the shell history;
 * prefer --seed-file.  The seed must be at least 16 characters.  --length
 * defaults to 80 (the v2 minimum).  The web
 * API key (public, not a secret) is read from android/app/google-services
 * .json when --api-key is not given.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const {parseArgs} = require('./firestore_target');
const randomization = require('../functions/randomization');

const REGION = 'asia-east2';
const CALLABLE = 'uploadRandomizationSequence';
// 10/19 (dev-tasks-1020 §C): uploads name their version; v2 needs ≥ 80.
const DEFAULT_LENGTH = 80;

function readSeed(args) {
  if (typeof args['seed-file'] === 'string') {
    return fs.readFileSync(args['seed-file'], 'utf8').trim();
  }
  if (typeof args.seed === 'string') return args.seed;
  return '';
}

function summary(seqs) {
  return randomization.STRATA.map((s) =>
    `  ${s}: ${seqs[s].length} positions, ${seqs[s].blocks.length} blocks, ` +
    `sha256 ${seqs[s].sha256}`).join('\n');
}

/**
 * The callable payload: arms, blocks and fingerprint per stratum.  Never
 * the seed.
 */
function buildPayload(seqs, opts) {
  const sequences = {};
  for (const s of randomization.STRATA) {
    sequences[s] = {arms: seqs[s].arms, blocks: seqs[s].blocks,
      sha256: seqs[s].sha256};
  }
  return {sequences, replace: !!(opts && opts.replace),
    version: (opts && opts.version) || null};
}

/**
 * Which Auth / Functions endpoints to talk to.
 * @return {{ok: boolean, reason: string, authUrl?: string,
 *     functionUrl?: string, projectId?: string}}
 */
function callableTarget(env, args) {
  const authHost = env.FIREBASE_AUTH_EMULATOR_HOST;
  const fnHost = env.FUNCTIONS_EMULATOR_HOST;
  if (authHost || fnHost) {
    if (!authHost || !fnHost) {
      return {ok: false, reason: 'set BOTH FIREBASE_AUTH_EMULATOR_HOST and ' +
        'FUNCTIONS_EMULATOR_HOST for the emulator, or neither'};
    }
    if (args['production-confirm']) {
      return {ok: false, reason: '--production-confirm given but emulator ' +
        'hosts are set; refusing an ambiguous target'};
    }
    const projectId = args.project || env.GCLOUD_PROJECT ||
      'demo-randomization';
    return {ok: true, reason: `emulator (${authHost}, ${fnHost})`, projectId,
      authUrl: `http://${authHost}/identitytoolkit.googleapis.com/v1/` +
        'accounts:signInWithPassword?key=emulator',
      functionUrl: `http://${fnHost}/${projectId}/${REGION}/${CALLABLE}`};
  }
  const project = typeof args.project === 'string' ? args.project : '';
  if (!project) {
    return {ok: false, reason: 'not on the emulator and no --project; ' +
      'refusing'};
  }
  if (args['production-confirm'] !== project) {
    return {ok: false, reason: `refusing to touch real project ${project}. ` +
      `Add --production-confirm=${project}`};
  }
  const apiKey = typeof args['api-key'] === 'string' ? args['api-key'] :
    readWebApiKey();
  if (!apiKey) {
    return {ok: false, reason: 'no web API key: pass --api-key=<key> ' +
      '(Firebase console → project settings → Web API key)'};
  }
  return {ok: true, reason: `REAL PROJECT ${project}`, projectId: project,
    authUrl: 'https://identitytoolkit.googleapis.com/v1/' +
      `accounts:signInWithPassword?key=${apiKey}`,
    functionUrl: `https://${REGION}-${project}.cloudfunctions.net/` +
      CALLABLE};
}

function readWebApiKey() {
  try {
    const f = path.join(__dirname, '..', 'android', 'app',
        'google-services.json');
    const j = JSON.parse(fs.readFileSync(f, 'utf8'));
    return j.client[0].api_key[0].current_key || null;
  } catch (_) {
    return null;
  }
}

/**
 * Sign in with e-mail + password and call the callable.  `fetchFn` is
 * injectable for tests.  Returns {ok, status, body}.
 */
async function uploadViaCallable(p) {
  const fetchFn = p.fetch || global.fetch;
  const signIn = await fetchFn(p.authUrl, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email: p.email, password: p.password,
      returnSecureToken: true}),
  });
  const signInBody = await signIn.json();
  if (!signIn.ok || !signInBody.idToken) {
    return {ok: false, status: signIn.status, body: {
      error: (signInBody.error && signInBody.error.message) || 'sign-in ' +
        'failed'}};
  }
  const call = await fetchFn(p.functionUrl, {
    method: 'POST',
    headers: {'Content-Type': 'application/json',
      'Authorization': `Bearer ${signInBody.idToken}`},
    body: JSON.stringify({data: p.payload}),
  });
  const body = await call.json();
  return {ok: call.ok && !body.error, status: call.status, body};
}

/**
 * Admin-SDK upload — used ONLY by the emulator tests to seed sequences
 * (functions/test/randomization_emulator_test.js).  Not reachable from the
 * command line: the uploader goes through the callable above.
 * opts.version: "v1" (default, the old low/high documents) or "v2"
 * (v2_low / v2_high).
 */
async function upload(db, seqs, opts) {
  const lines = [];
  const S = randomization;
  const version = (opts && opts.version) || 'v1';
  for (const s of S.STRATA) {
    if (!S.sequenceValid(seqs[s])) {
      return {ok: false, lines: [`! ${s}: sequence failed validation`]};
    }
  }
  return db.runTransaction(async (tx) => {
    const refs = {};
    const snaps = {};
    for (const s of S.STRATA) {
      refs[s] = {
        seq: db.collection(S.SEQ_COLLECTION).doc(S.sequenceDocId(version, s)),
        state: db.collection(S.STATE_COLLECTION)
            .doc(S.sequenceDocId(version, s)),
      };
      snaps[s] = {
        seq: await tx.get(refs[s].seq),
        state: await tx.get(refs[s].state),
      };
    }
    for (const s of S.STRATA) {
      if (snaps[s].seq.exists && !opts.replace) {
        lines.push(`! ${s}: a sequence is already uploaded; not replaced ` +
          '(add --replace only if nobody has been allocated yet)');
        return {ok: false, lines};
      }
      const used = snaps[s].state.exists ?
        Number(snaps[s].state.get('next')) || 0 : 0;
      if (used > 0) {
        lines.push(`! ${s}: ${used} position(s) already allocated; ` +
          'refusing to replace');
        return {ok: false, lines};
      }
    }
    const now = new Date();
    for (const s of S.STRATA) {
      tx.set(refs[s].seq, {
        stratum: s,
        arms: seqs[s].arms,
        blocks: seqs[s].blocks,
        length: seqs[s].length,
        sha256: seqs[s].sha256,
        generatorVersion: S.GENERATOR_VERSION,
        studyPeriod: 'B',
        uploadedAt: now,
        uploadedBy: opts.operator || null,
      });
      tx.set(refs[s].state, {next: 0, updatedAt: now});
      lines.push(`+ ${s}: uploaded ${seqs[s].length} positions`);
    }
    return {ok: true, lines};
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const seed = readSeed(args);
  let seqs;
  try {
    seqs = randomization.generateSequences(seed,
        args.length ? Number(args.length) : DEFAULT_LENGTH);
  } catch (e) {
    console.error(`randomization_sequence: ${e.message} ` +
      '(need --seed-file with at least 16 characters; --length ≥ 80)');
    process.exit(2);
  }
  console.log('Generated (arms not shown):\n' + summary(seqs));

  if (!args.upload) {
    const dir = typeof args.out === 'string' ? args.out :
      'randomization-private';
    fs.mkdirSync(dir, {recursive: true});
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '');
    const file = path.join(dir, `randomization_sequence_${stamp}.json`);
    fs.writeFileSync(file, JSON.stringify({
      generatorVersion: randomization.GENERATOR_VERSION,
      generatedAt: new Date().toISOString(),
      seed,
      sequences: seqs,
    }, null, 2), {mode: 0o600});
    console.log(`Wrote ${file} — contains the SEED. Hand it to the ` +
      'supervisor for offline storage; never commit it.');
    return;
  }

  if (args.version !== 'v2') {
    console.error('randomization_sequence: --upload needs --version=v2 ' +
      '(v1 is retired; see docs/release/sequence-v2-upload-20261020.md)');
    process.exit(2);
  }
  const t = callableTarget(process.env, args);
  if (!t.ok) {
    console.error(`randomization_sequence: ${t.reason}`);
    process.exit(2);
  }
  const email = typeof args.email === 'string' ? args.email : '';
  const password = typeof args['password-file'] === 'string' ?
    fs.readFileSync(args['password-file'], 'utf8').trim() : '';
  if (!email || !password) {
    console.error('Need --email=<your App login> and --password-file=<file ' +
      'holding your password> (your own account, role sequence_uploader).');
    process.exit(2);
  }
  console.log(`Upload target: ${t.reason} (project ${t.projectId}), as ` +
    `${email} through ${CALLABLE}`);
  const r = await uploadViaCallable({
    fetch: global.fetch, authUrl: t.authUrl, functionUrl: t.functionUrl,
    email, password, payload: buildPayload(seqs, {replace: args.replace ===
      true, version: args.version}),
  });
  if (!r.ok) {
    const err = r.body && r.body.error;
    const msg = err && (err.message || err.status || err) || 'unknown error';
    console.error(`! upload refused (${r.status}): ${msg}` +
      (msg === 'same_seed_as_v1' ? ' — this seed repeats v1; choose a ' +
        'NEW seed and generate again' : ''));
    process.exit(1);
  }
  const result = r.body.result || {};
  for (const s of randomization.STRATA) {
    const u = result.uploaded && result.uploaded[s];
    if (u) console.log(`+ ${s}: uploaded ${u.length} positions, sha256 ${u.sha256}`);
  }
  console.log(result.replaced ? `Replaced the earlier ${result.version || ''} sequences.` :
    `Done (${result.version || 'v2'}). The server logged the upload ` +
    '(sequence_upload_log) and marked v1 retired (sequence_versions).');
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {upload, readSeed, buildPayload, callableTarget,
  uploadViaCallable, REGION, CALLABLE, DEFAULT_LENGTH};

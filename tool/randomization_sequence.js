#!/usr/bin/env node
/**
 * tool/randomization_sequence.js — T19 (decision 0029).  Run by the
 * UNBLINDED researcher only (Keran).  The PI must not run it, see its
 * output, or know the seed.
 *
 * Generates one permuted-block sequence per stratum (low = W0 DJG
 * emotional 0–1, high = 2–3) from a seed the researcher chooses: 1:1,
 * blocks of 2 and 4 mixed at random, at least 60 positions each
 * (functions/randomization.js generateSequences).  Same seed → same
 * sequences, so the offline copy can be re-checked.
 *
 * Steps
 *   1. generate  — writes ONE file with the seed and both sequences into
 *                  randomization-private/ (git-ignored).  Prints only the
 *                  lengths and SHA-256 fingerprints, never the arms.
 *                  Hand that file to the supervisor for offline storage,
 *                  then delete it from the laptop.
 *   2. --upload  — writes randomization_sequences/{low,high} and sets
 *                  randomization_state/{low,high}.next = 0.  Refuses if a
 *                  sequence is already there (use --replace only before
 *                  anyone has been allocated).  The seed is never uploaded.
 *
 * Target: the Firestore emulator by default.  A real project needs
 * --project=<id> --production-confirm=<same id> (tool/firestore_target.js).
 *
 * Usage
 *   NODE_PATH=functions/node_modules node tool/randomization_sequence.js \
 *     --seed-file=/path/to/my-seed.txt [--length=60] [--out=randomization-private]
 *   ... --seed-file=... --upload --operator=keran@example.org
 *   ... (real project) --project=loneliness-pilot-dev \
 *       --production-confirm=loneliness-pilot-dev
 *
 * --seed=<text> also works but leaves the seed in the shell history;
 * prefer --seed-file.  The seed must be at least 16 characters.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const {parseArgs, checkTarget} = require('./firestore_target');
const randomization = require('../functions/randomization');

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
 * Upload both sequences.  Returns {ok, lines}.
 */
async function upload(db, seqs, opts) {
  const lines = [];
  const S = randomization;
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
        seq: db.collection(S.SEQ_COLLECTION).doc(s),
        state: db.collection(S.STATE_COLLECTION).doc(s),
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
        args.length ? Number(args.length) : undefined);
  } catch (e) {
    console.error(`randomization_sequence: ${e.message} ` +
      '(need --seed-file with at least 16 characters; --length ≥ 60)');
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

  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`randomization_sequence: ${t.reason}`);
    process.exit(2);
  }
  console.log(`Upload target: ${t.reason} (project ${t.projectId})`);
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const r = await upload(admin.firestore(), seqs, {
    replace: args.replace === true,
    operator: typeof args.operator === 'string' ? args.operator : null,
  });
  r.lines.forEach((l) => console.log(l));
  process.exit(r.ok ? 0 : 1);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {upload, readSeed};

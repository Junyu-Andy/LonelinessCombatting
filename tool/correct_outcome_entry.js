#!/usr/bin/env node
/**
 * tool/correct_outcome_entry.js — T30.  Correct one W4 paper outcome
 * entry (`outcome_entries/{id}`) after the assessor submitted it.
 *
 * The assessor cannot change a submitted entry (the callable refuses a
 * second entry for the same research ID / timepoint / instrument).  A
 * correction is an admin operation: one item's raw value, the assessment
 * date or the mode, with a reason of at least 10 characters and the
 * operator's name; the server re-scores and writes a row in
 * `outcome_entry_corrections` (before / after / reason / who / when).
 * Nothing prints a score.
 *
 * Usage (emulator by default; a real project needs --project and
 * --production-confirm, tool/firestore_target.js):
 *   NODE_PATH=functions/node_modules node tool/correct_outcome_entry.js \
 *     --entry=<docId> --item=q3 --value=no \
 *     --reason="paper form shows 不是, typed 是" --operator=junyu@… --confirm
 *   ... --entry=<docId> --assessment-date=2026-11-14 --reason=… --operator=…
 *   ... --entry=<docId> --mode=phone --reason=… --operator=…
 * --value=skipped marks the item missing.  Without --confirm it only
 * prints what would change.
 */

'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');
const assessor = require('../functions/assessor');

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (typeof args.entry !== 'string' || !args.entry) {
    console.error('Need --entry=<outcome_entries doc id>.');
    process.exit(2);
  }
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`correct_outcome_entry: ${t.reason}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();
  const p = {
    entryId: args.entry,
    item: typeof args.item === 'string' ? args.item : null,
    value: args.value === undefined ? undefined :
      /^\d+$/.test(String(args.value)) ? Number(args.value) : args.value,
    assessmentDate: typeof args['assessment-date'] === 'string' ?
      args['assessment-date'] : null,
    mode: typeof args.mode === 'string' ? args.mode : null,
    reason: typeof args.reason === 'string' ? args.reason : '',
    operator: typeof args.operator === 'string' ? args.operator : '',
  };
  if (args.confirm !== true) {
    const snap = await db.collection(assessor.ENTRIES).doc(p.entryId).get();
    if (!snap.exists) {
      console.error('entry not found');
      process.exit(1);
    }
    const e = snap.data();
    console.log(`Dry run (${t.reason}). Entry ${p.entryId}: ` +
      `${e.researchId} ${e.instrument} ${e.timepoint}, date ` +
      `${e.assessmentDate}, mode ${e.mode}, missing ` +
      `[${(e.missingItems || []).join(',')}]`);
    console.log(`Would apply: ${JSON.stringify({item: p.item, value: p.value,
      assessmentDate: p.assessmentDate, mode: p.mode})}`);
    console.log('Re-run with --confirm to write the correction.');
    return;
  }
  try {
    const r = await assessor.correctEntry(db, p);
    console.log(`Corrected ${p.entryId} (${t.reason}): ` +
      `${JSON.stringify(r.before)} -> ${JSON.stringify(r.after)}`);
    console.log('Logged in outcome_entry_corrections.');
  } catch (err) {
    console.error(`correct_outcome_entry: ${err.assessorCode || err.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

#!/usr/bin/env node
/**
 * tool/correct_arm_assignment.js — T19 (decision 0029).  The ONLY way to
 * change an arm after allocation.  Unblinded researcher only, and only
 * when the research team has agreed the correction in writing.
 *
 * Changes users/{uid}.arm and enrollments/{uid}.arm, keeps the sequence
 * position that was used, and writes an arm_assignment_log row with
 * action "correction", the previous arm, the new arm, the reason and the
 * operator.  The Cloud Functions' arm cache picks the change up within
 * 10 minutes; the participant's App on its next cold start.
 *
 *   --research-id=B001 | --uid=<uid>   who
 *   --arm=A|B                          the corrected arm
 *   --reason="..."                     at least 10 characters (required)
 *   --operator=<email>                 who is running this (required)
 *   --confirm                          write (default: dry run)
 *
 * Target: the Firestore emulator by default; a real project needs
 * --project=<id> --production-confirm=<same id>.
 *
 *   NODE_PATH=functions/node_modules node tool/correct_arm_assignment.js \
 *     --research-id=B001 --arm=B --reason="..." --operator=keran@... --confirm
 */

'use strict';

const {parseArgs, checkTarget} = require('./firestore_target');
const randomization = require('../functions/randomization');

async function findUid(db, args) {
  if (typeof args.uid === 'string') return args.uid;
  const rid = randomization.normaliseResearchId(args['research-id']);
  if (!rid) return null;
  const snap = await db.collection('research_ids').doc(rid).get();
  return snap.exists ? snap.get('uid') : null;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`correct_arm_assignment: ${t.reason}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();
  const uid = await findUid(db, args);
  if (!uid) {
    console.error('correct_arm_assignment: participant not found ' +
      '(--research-id or --uid)');
    process.exit(2);
  }
  const e = await db.collection(randomization.ENROLL_COLLECTION).doc(uid)
      .get();
  if (!e.exists) {
    console.error('correct_arm_assignment: not enrolled');
    process.exit(2);
  }
  console.log(`target ${t.reason}: ${e.get('researchId')} ` +
    `${e.get('arm')} → ${args.arm}`);
  if (args.confirm !== true) {
    console.log('dry run — add --confirm to write');
    return;
  }
  try {
    const r = await randomization.correctArm(db, {
      uid, arm: args.arm, reason: args.reason, operator: args.operator,
    });
    console.log(`corrected ${r.previousArm} → ${r.arm}; logged`);
  } catch (err) {
    console.error(`correct_arm_assignment: ${err.enrolCode || err.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

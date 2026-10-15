/**
 * 1014e §2.3 — tool/set_tester.js against the Firestore emulator: sets and
 * clears users/{uid}.isTester, lists testers, refuses a registered
 * participant unless --allow-registered, refuses a missing account.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/set_tester_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const tool = require("../../tool/set_tester");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const quiet = {log: () => {}};

async function fails(p, re) {
  try {
    await p;
  } catch (e) {
    assert.ok(re.test(e.message), e.message);
    return;
  }
  assert.fail("expected an error");
}

(async () => {
  for (const c of ["users", "enrollments"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
  await db.doc("users/staff1").set({uid: "staff1", email: "s@x.test",
    displayName: "Staff"});
  await db.doc("users/pilot1").set({uid: "pilot1", cohort: "pilot", arm: "A"});
  await db.doc("enrollments/pilot1").set({uid: "pilot1",
    researchId: "PILOT-01", studyPeriod: "PILOT"});

  // set
  const r1 = await tool.run(db, null, {uid: "staff1", tester: "true"}, quiet);
  assert.deepStrictEqual(r1, {uid: "staff1", isTester: true, listed: null});
  assert.strictEqual((await db.doc("users/staff1").get()).get("isTester"),
      true);
  assert.strictEqual((await db.doc("users/staff1").get()).get("displayName"),
      "Staff", "merge keeps the rest");
  console.log("ok - sets isTester on a staff account");

  // list
  const r2 = await tool.run(db, null, {list: true}, quiet);
  assert.strictEqual(r2.listed, 1);
  console.log("ok - lists tester accounts");

  // registered participant refused
  await fails(tool.run(db, null, {uid: "pilot1", tester: "true"}, quiet),
      /registered participant/);
  assert.strictEqual((await db.doc("users/pilot1").get()).get("isTester"),
      undefined);
  console.log("ok - refuses a registered participant");
  const r3 = await tool.run(db, null, {"uid": "pilot1", "tester": "true",
    "allow-registered": true}, quiet);
  assert.strictEqual(r3.isTester, true);
  console.log("ok - --allow-registered overrides");

  // clear
  await tool.run(db, null, {uid: "staff1", tester: "false"}, quiet);
  assert.strictEqual((await db.doc("users/staff1").get()).get("isTester"),
      false);
  console.log("ok - clears the flag");

  // bad input
  await fails(tool.run(db, null, {uid: "nobody", tester: "true"}, quiet),
      /does not exist/);
  await fails(tool.run(db, null, {uid: "staff1"}, quiet), /--tester/);
  await fails(tool.run(db, null, {tester: "true"}, quiet), /--uid/);
  await fails(tool.run(db, null, {email: "s@x.test", tester: "true"}, quiet),
      /Auth/);
  console.log("ok - bad input refused");

  for (const c of ["users", "enrollments"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
  console.log("all set_tester emulator tests passed");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

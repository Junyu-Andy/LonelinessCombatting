/**
 * assignArm against the Firestore emulator (T19, decision 0029): the old
 * minimisation is gone.  assignArm returns a stored arm, gives Arm A to
 * Phase A / pilot accounts while meta/randomization_config is off, never
 * assigns while it is on, and refuses the retired randomise flag.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/arm_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const {assignArm} = require("../arm");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

async function reset({randomise, enrollment}) {
  for (const path of ["users", "meta", "app_config"]) {
    const docs = await db.collection(path).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  if (randomise !== undefined) {
    await db.doc("app_config/arm_assignment").set({randomise});
  }
  if (enrollment !== undefined) {
    await db.doc("meta/randomization_config").set({enabled: enrollment});
  }
}

const user = async (uid) => (await db.doc(`users/${uid}`).get()).data();

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("phase A default: no config → A (force_a), no counter", async () => {
  await reset({});
  await db.doc("users/u1").set({ageGroup: "75+", baselineUclaScore: 60});
  const r = await assignArm(db, "u1");
  assert.deepStrictEqual(r, {arm: "A", cell: null, mode: "force_a",
    assigned: true});
  const u = await user("u1");
  assert.strictEqual(u.arm, "A");
  assert.strictEqual(u.armAssignedBy, "server");
  assert.strictEqual(u.armAssignmentMode, "force_a");
  assert.strictEqual(u.strataCell, undefined);
  assert.strictEqual((await db.doc("meta/arm_counter").get()).exists, false);
});

test("enrolment switch on: never assigns, arm stays null", async () => {
  await reset({enrollment: true});
  await db.doc("users/u1").set({displayName: "x"});
  const r = await assignArm(db, "u1");
  assert.deepStrictEqual(r, {arm: null, cell: null, mode: "enrollment",
    assigned: false});
  assert.strictEqual((await user("u1")).arm, undefined);
});

test("retired randomise flag with the switch off: refuses, no Arm A",
    async () => {
      await reset({randomise: true});
      await db.doc("users/u1").set({displayName: "x"});
      const r = await assignArm(db, "u1");
      assert.strictEqual(r.arm, null);
      assert.strictEqual(r.mode, "randomise_retired");
      assert.strictEqual((await user("u1")).arm, undefined);
    });

test("an existing arm is returned unchanged in every mode", async () => {
  for (const cfg of [{}, {enrollment: true}, {randomise: true}]) {
    await reset(cfg);
    await db.doc("users/u1").set({arm: "B", strataCell: 1,
      armAssignmentMode: "randomise"});
    const r = await assignArm(db, "u1");
    assert.deepStrictEqual(r, {arm: "B", cell: 1, mode: "randomise",
      assigned: false});
  }
});

test("concurrent calls in phase A write once", async () => {
  await reset({});
  await db.doc("users/u1").set({displayName: "x"});
  const results = await Promise.all([1, 2, 3, 4].map(() =>
    assignArm(db, "u1")));
  assert.ok(results.every((r) => r.arm === "A"));
  assert.strictEqual(results.filter((r) => r.assigned).length, 1);
});

test("no profile → error", async () => {
  await reset({});
  await assert.rejects(assignArm(db, "ghost"), /profile_missing/);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL  ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();

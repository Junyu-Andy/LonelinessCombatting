/**
 * Server-side arm assignment against the Firestore emulator.
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

async function reset({randomise}) {
  for (const path of ["users", "meta", "app_config"]) {
    const docs = await db.collection(path).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  if (randomise !== undefined) {
    await db.doc("app_config/arm_assignment").set({randomise});
  }
}

const counter = async () => (await db.doc("meta/arm_counter").get()).data();

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("phase A default: no config doc → A, counted in the right cell",
    async () => {
      await reset({});
      await db.doc("users/u1").set({ageGroup: "75+", baselineUclaScore: 60});
      const r = await assignArm(db, "u1");
      assert.deepStrictEqual(r, {arm: "A", cell: 3, mode: "force_a",
        assigned: true});
      const u = (await db.doc("users/u1").get()).data();
      assert.strictEqual(u.arm, "A");
      assert.strictEqual(u.strataCell, 3);
      assert.strictEqual(u.armAssignedBy, "server");
      assert.strictEqual(u.armAssignmentMode, "force_a");
      assert.deepStrictEqual((await counter()).cell_3,
          {aCount: 1, bCount: 0});
    });

test("idempotent: a second call returns the arm without counting again",
    async () => {
      await reset({randomise: true});
      await db.doc("users/u1").set({ageGroup: "60-64"});
      const first = await assignArm(db, "u1");
      const again = await assignArm(db, "u1");
      assert.strictEqual(again.arm, first.arm);
      assert.strictEqual(again.assigned, false);
      assert.strictEqual(again.mode, "randomise");
      const c = (await counter()).cell_0;
      assert.strictEqual(c.aCount + c.bCount, 1);
    });

test("concurrent calls for one user count once", async () => {
  await reset({randomise: true});
  await db.doc("users/u1").set({ageGroup: "60-64"});
  const results = await Promise.all(
      [1, 2, 3, 4].map(() => assignArm(db, "u1")));
  assert.strictEqual(new Set(results.map((r) => r.arm)).size, 1);
  assert.strictEqual(results.filter((r) => r.assigned).length, 1);
  const c = (await counter()).cell_0;
  assert.strictEqual(c.aCount + c.bCount, 1);
});

test("randomise mode keeps each cell balanced", async () => {
  await reset({randomise: true});
  for (let i = 0; i < 10; i++) {
    await db.doc(`users/u${i}`).set({ageGroup: "70-74", baselineUclaScore: 30});
    await assignArm(db, `u${i}`);
  }
  const c = (await counter()).cell_1;
  assert.deepStrictEqual(c, {aCount: 5, bCount: 5});
});

test("an existing arm is never changed", async () => {
  await reset({randomise: true});
  await db.doc("users/u1").set({arm: "B", strataCell: 2});
  const r = await assignArm(db, "u1");
  assert.deepStrictEqual(r, {arm: "B", cell: 2, mode: null,
    assigned: false});
  assert.strictEqual(await counter(), undefined, "nothing counted");
});

test("no profile → error, nothing counted", async () => {
  await reset({});
  await assert.rejects(assignArm(db, "ghost"), /profile_missing/);
  assert.strictEqual(await counter(), undefined);
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

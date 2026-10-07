/**
 * tool/prelaunch_config.js against the Firestore emulator, plus its
 * refuse-by-default guard.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/prelaunch_config_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const tool = require("../../tool/prelaunch_config");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const silent = () => {};
const SCRIPT = path.resolve(__dirname, "../../tool/prelaunch_config.js");

async function reset() {
  for (const p of ["users", "meta", "app_config"]) {
    await db.recursiveDelete(db.collection(p));
  }
}

const data = async (p) => (await db.doc(p).get()).data();

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("guard: refuses without the emulator, whatever the project", () => {
  const env = {};
  const cases = [
    {phase: "b"},
    {phase: "b", project: "loneliness-pilot-dev"},
    {"phase": "b", "project": "demo-x", "production-confirm": "demo-x"},
    {"phase": "b", "project": "loneliness-pilot-dev",
      "production-confirm": "other"},
    {"project": "loneliness-pilot-dev",
      "production-confirm": "loneliness-pilot-dev"}, // no --phase
  ];
  for (const args of cases) {
    assert.strictEqual(tool.checkTarget(env, args).ok, false,
        JSON.stringify(args));
  }
  const e = tool.checkTarget({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"},
      {"phase": "b", "production-confirm": "x"});
  assert.strictEqual(e.ok, false); // ambiguous target
  const ok = tool.checkTarget({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"},
      {phase: "b"});
  assert.strictEqual(ok.target, "emulator");
});

test("guard: the CLI exits 2 off the emulator and writes nothing", () => {
  const env = {...process.env};
  delete env.FIRESTORE_EMULATOR_HOST;
  const r = spawnSync(process.execPath,
      [SCRIPT, "--phase=b", "--apply", "--project=loneliness-pilot-dev"],
      {env, encoding: "utf8"});
  assert.strictEqual(r.status, 2, r.stderr);
  assert.match(r.stderr, /refusing/);
});

test("dry run writes nothing", async () => {
  await reset();
  const ok = await tool.run(db, {phase: "b"}, silent);
  assert.strictEqual(ok, true);
  assert.strictEqual(await data("meta/memory_config"), undefined);
  assert.strictEqual(await data("app_config/arm_assignment"), undefined);
});

test("--apply creates both docs with the values the server reads",
    async () => {
      await reset();
      await tool.run(db, {phase: "b", apply: true}, silent);
      const m = await data("meta/memory_config");
      assert.strictEqual(m.enabled, true);
      assert.strictEqual(m.policy, "C");
      assert.strictEqual(m.phaseBArmA, true);
      assert.strictEqual((await data("app_config/arm_assignment")).randomise,
          true);
      // Re-run is a no-op.
      const lines = [];
      await tool.run(db, {phase: "b", apply: true}, (l) => lines.push(l));
      assert.ok(lines.every((l) => l.startsWith("=")), lines.join("\n"));
    });

test("a differing doc is not replaced without --overwrite", async () => {
  await reset();
  await db.doc("meta/memory_config").set({enabled: false, policy: "B"});
  const ok = await tool.run(db, {phase: "b", apply: true}, silent);
  assert.strictEqual(ok, false);
  assert.strictEqual((await data("meta/memory_config")).policy, "B");
  await tool.run(db, {phase: "b", apply: true, overwrite: true}, silent);
  assert.strictEqual((await data("meta/memory_config")).policy, "C");
});

test("--reset-arm-counter zeroes it, but never after randomisation",
    async () => {
      await reset();
      await db.doc("meta/arm_counter").set({cell_0: {aCount: 5, bCount: 0}});
      await tool.run(db, {"phase": "b", "apply": true,
        "reset-arm-counter": true}, silent);
      assert.deepStrictEqual((await data("meta/arm_counter")).cell_0,
          {aCount: 0, bCount: 0});
      await db.doc("meta/arm_counter").set({cell_0: {aCount: 1, bCount: 1}});
      await db.doc("users/u1").set({arm: "B", armAssignmentMode: "randomise"});
      const ok = await tool.run(db, {"phase": "b", "apply": true,
        "reset-arm-counter": true}, silent);
      assert.strictEqual(ok, false);
      assert.deepStrictEqual((await data("meta/arm_counter")).cell_0,
          {aCount: 1, bCount: 1});
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ✓ ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`  ✗ ${t.name}\n    ${err.stack}`);
    }
  }
  console.log(failed ? `${failed} failed` : `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

/**
 * tool/export_agent_contexts.js (dev-tasks 1020j §1(3)) against the
 * Firestore emulator with synthetic accounts: it backs up PILOT- and PB-
 * agent_contexts to a local file (mode 0600), leaves RCT- out, writes
 * nothing to Firestore, prints no text, and refuses a file inside the
 * repository or a real project without the confirmation.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/export_agent_contexts_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const tool = require("../../tool/export_agent_contexts");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const SCRIPT = path.resolve(__dirname, "../../tool/export_agent_contexts.js");
const NODE_PATH = path.resolve(__dirname, "../node_modules");
const SECRET_TEXT = "我好掛住阿女 SYNTHETIC-TURN-7781";

function run(args, extraEnv) {
  return spawnSync(process.execPath, [SCRIPT].concat(args || []),
      {env: Object.assign({}, process.env, {NODE_PATH}, extraEnv || {}),
        encoding: "utf8"});
}

async function seed() {
  for (const p of ["users", "enrollments", "randomization_state"]) {
    await db.recursiveDelete(db.collection(p));
  }
  const people = [["uP1", "PILOT-01"], ["uB1", "PB-01"], ["uR1", "RCT-001"]];
  for (const [uid, rid] of people) {
    await db.doc(`enrollments/${uid}`).set({researchId: rid,
      studyPeriod: rid.startsWith("PILOT") ? "PILOT" : "B", arm: "A",
      sequencePosition: 4, stratum: "high"});
    await db.doc(`users/${uid}/agent_contexts/siu_yan`).set({
      shortTermBuffer: [
        {fromUser: true, text: `${rid} ${SECRET_TEXT}`,
          timestamp: "2026-10-19T10:00:00.000"},
        {fromUser: false, text: "我明白", timestamp: "2026-10-19T10:00:05.000"},
      ],
      rollingSummary: `${rid} 嘅摘要`,
      lastUpdated: admin.firestore.Timestamp.fromDate(
          new Date("2026-10-19T02:00:00Z")),
    });
  }
  await db.doc("users/uB1/agent_contexts/tung_tung").set({
    shortTermBuffer: [], rollingSummary: ""});
  await db.doc("randomization_state/rct").set({next: 9});
}

async function count(coll) {
  return (await db.collection(coll).count().get()).data().count;
}

(async () => {
  await seed();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "agentctx-"));
  const out = path.join(dir, "backup.json");
  const before = {users: await count("users"),
    enrollments: await count("enrollments")};

  const r = run([`--out=${out}`]);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(r.stdout.indexOf("PILOT-01") >= 0 && r.stdout.indexOf("PB-01") >= 0);
  assert.ok(r.stdout.indexOf("SYNTHETIC-TURN") < 0, "no text on screen");
  assert.ok(r.stdout.indexOf("RCT-001") < 0);
  console.log("ok - backs up PILOT- and PB-, prints counts only");

  const doc = JSON.parse(fs.readFileSync(out, "utf8"));
  assert.deepStrictEqual(doc.participants.map((p) => p.researchId),
      ["PB-01", "PILOT-01"]);
  const pilot = doc.participants.find((p) => p.researchId === "PILOT-01");
  assert.strictEqual(pilot.agentContexts.siu_yan.shortTermBuffer[0].text,
      `PILOT-01 ${SECRET_TEXT}`);
  assert.strictEqual(pilot.agentContexts.siu_yan.lastUpdated,
      "2026-10-19T02:00:00.000Z");
  assert.ok(JSON.stringify(doc).indexOf("sequencePosition") < 0);
  assert.ok(JSON.stringify(doc).indexOf("stratum") < 0);
  assert.strictEqual(fs.statSync(out).mode & 0o777, 0o600);
  console.log("ok - the file has the turns and summaries, mode 0600, " +
    "no allocation fields");

  assert.strictEqual(await count("users"), before.users);
  assert.strictEqual(await count("enrollments"), before.enrollments);
  assert.strictEqual((await db.doc("randomization_state/rct").get())
      .get("next"), 9);
  console.log("ok - nothing written to Firestore");

  const inRepo = run([`--out=${path.resolve(__dirname, "x.json")}`]);
  assert.strictEqual(inRepo.status, 2);
  assert.ok(/outside/.test(inRepo.stderr));
  const prod = run([`--out=${out}`], {FIRESTORE_EMULATOR_HOST: ""});
  assert.strictEqual(prod.status, 2);
  assert.ok(/refusing/.test(prod.stderr));
  console.log("ok - refuses a file in the repository and an unconfirmed " +
    "real project");

  const prefixed = run([`--out=${out}`, "--prefix=RCT-"]);
  assert.strictEqual(prefixed.status, 0, prefixed.stderr);
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(out, "utf8"))
      .participants.map((p) => p.researchId), ["RCT-001"]);
  assert.deepStrictEqual(tool.DEFAULT_PREFIXES, ["PILOT-", "PB-"]);
  console.log("ok - --prefix chooses other research IDs");

  console.log("all 5 export_agent_contexts emulator tests passed");
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

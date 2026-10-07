/**
 * T19 (decision 0029) — registration and allocation against the Firestore
 * emulator, with 72 synthetic participants.
 *
 * Covers: switch off by default; only the unblinded role; dry run reveals
 * no arm and writes nothing; 72 allocations by two researchers submitting
 * at the same time (no position used twice, arm = sequence position);
 * per-stratum counts and the largest A–B gap along the way; resubmission
 * and simultaneous double submission never re-randomise; research ID
 * clashes; exhaustion; the logged correction; the sequence upload guard;
 * assignArm after registration; the blinded export carries no arm.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/randomization_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const R = require("../randomization");
const {assignArm} = require("../arm");
const blinding = require("../blinding");
const seqTool = require("../../tool/randomization_sequence");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const CHECKER = path.resolve(__dirname, "../../tool/check_blinded_export.js");

const K1 = {uid: "keran", email: "k1@example.org", role: "unblinded"};
const K2 = {uid: "keran2", email: "k2@example.org", role: "unblinded"};
const SEED = "synthetic-test-seed-t19-0001";
const NOW = new Date("2026-10-07T04:00:00Z");

async function reset() {
  for (const c of ["users", "meta", "app_config", "randomization_sequences",
    "randomization_state", "enrollments", "arm_assignment_log",
    "research_id_map", "research_ids", "export_blind_keys"]) {
    await db.recursiveDelete(db.collection(c));
  }
}

async function setup({enabled = true, upload = true} = {}) {
  await reset();
  if (enabled) await db.doc(R.CONFIG_DOC).set({enabled: true});
  if (upload) {
    const r = await seqTool.upload(db, R.generateSequences(SEED),
        {operator: "k1@example.org"});
    assert.ok(r.ok, r.lines.join("\n"));
  }
}

async function account(uid, extra) {
  await db.doc(`users/${uid}`).set(Object.assign({
    displayName: `Synthetic ${uid}`, createdAt: "2026-10-01T10:00:00",
  }, extra || {}));
}

function input(uid, rid, score, more) {
  return Object.assign({uid, researchId: rid, w0DjgEmotional: score,
    companionVariant: score % 2 ? "masculine" : "feminine",
    confirmed: true}, more || {});
}

const enrolCode = async (p) => {
  try {
    await p;
  } catch (e) {
    return e.enrolCode || e.message;
  }
  return "no error";
};

const tests = [];
const test = (name, fn) => tests.push({name, fn});
const report = [];

test("switch off (default): registration refused", async () => {
  await setup({enabled: false});
  await account("u1");
  assert.strictEqual(await enrolCode(R.enrol(db, K1, input("u1", "B001", 1),
      {now: NOW})), "disabled");
});

test("only the unblinded role may register", async () => {
  await setup();
  await account("u1");
  for (const role of ["blinded", "pi", "researcher", null]) {
    assert.strictEqual(await enrolCode(R.enrol(db,
        {uid: "x", email: null, role}, input("u1", "B001", 1), {now: NOW})),
    "not_unblinded_researcher", String(role));
  }
});

test("input checks: score, ID, pairing, W0 date, confirmation", async () => {
  await setup();
  await account("u1");
  const cases = [
    [input("u1", "B001", 4), "invalid_score"],
    [input("u1", "B001", 1.5), "invalid_score"],
    [input("u1", "B001", "2"), "invalid_score"],
    [input("u1", "B 001", 1), "invalid_research_id"],
    [input("u1", "B001", 1, {companionVariant: "x"}), "invalid_variant"],
    [input("u1", "B001", 1, {w0Date: "2026-10-09"}), "invalid_w0_date"],
    [input("u1", "B001", 1, {confirmed: false}), "not_confirmed"],
    [input("ghost", "B001", 1), "account_not_found"],
    [input("keran", "B001", 1), "own_account"],
  ];
  for (const [inp, code] of cases) {
    assert.strictEqual(await enrolCode(R.enrol(db, K1, inp, {now: NOW})),
        code, JSON.stringify(inp));
  }
  assert.strictEqual((await db.collection("enrollments").get()).size, 0);
});

test("dry run: account shown, no arm, nothing written", async () => {
  await setup();
  await account("u1");
  const r = await R.enrol(db, K1, input("u1", "b001", 2,
      {dryRun: true, confirmed: false}), {now: NOW});
  assert.strictEqual(r.arm, null);
  assert.strictEqual(r.account.displayName, "Synthetic u1");
  assert.strictEqual(r.researchId, "B001");
  assert.strictEqual(r.stratum, "high");
  assert.strictEqual((await db.doc("randomization_state/high").get())
      .get("next"), 0);
  assert.strictEqual((await db.doc("users/u1").get()).get("arm"),
      undefined);
  assert.strictEqual((await db.collection("arm_assignment_log").get()).size,
      0);
});

test("72 synthetic participants, two researchers at the same time",
    async () => {
      await setup();
      // Seeded spread of W0 scores 0–3 (about half per stratum).
      const rand = R.seededRandomInt("score-spread", "t19");
      const people = [];
      for (let i = 1; i <= 72; i++) {
        const uid = `syn${String(i).padStart(2, "0")}`;
        await account(uid);
        people.push({uid, rid: `B${String(i).padStart(3, "0")}`,
          score: rand(4)});
      }
      // Pairs submitted together, one per researcher.
      const results = {};
      for (let i = 0; i < people.length; i += 2) {
        const pair = people.slice(i, i + 2);
        const out = await Promise.all(pair.map((p, j) =>
          R.enrol(db, j ? K2 : K1, input(p.uid, p.rid, p.score,
              {w0Date: "2026-10-06"}), {now: NOW})));
        pair.forEach((p, j) => results[p.uid] = out[j]);
      }

      const seqs = R.generateSequences(SEED);
      const enrolments = (await db.collection("enrollments").get()).docs
          .map((d) => d.data());
      assert.strictEqual(enrolments.length, 72);
      const stats = {};
      for (const s of R.STRATA) {
        const rows = enrolments.filter((e) => e.stratum === s)
            .sort((a, b) => a.sequencePosition - b.sequencePosition);
        const positions = rows.map((e) => e.sequencePosition);
        assert.deepStrictEqual(positions,
            positions.map((_, i) => i + 1), `${s}: positions 1..n, no gaps`);
        let a = 0;
        let b = 0;
        let maxGap = 0;
        for (const e of rows) {
          assert.strictEqual(e.arm, seqs[s].arms[e.sequencePosition - 1]);
          if (e.arm === "A") a++;
          else b++;
          maxGap = Math.max(maxGap, Math.abs(a - b));
        }
        assert.ok(maxGap <= 2, `${s}: gap ${maxGap} (blocks ≤ 4)`);
        const next = (await db.doc(`randomization_state/${s}`).get())
            .get("next");
        assert.strictEqual(next, rows.length);
        stats[s] = {n: rows.length, a, b, finalGap: Math.abs(a - b), maxGap};
      }
      for (const p of people) {
        const u = (await db.doc(`users/${p.uid}`).get()).data();
        assert.strictEqual(u.arm, results[p.uid].arm);
        assert.strictEqual(u.armAssignmentMode, "randomise");
        assert.strictEqual(u.armAssignedBy, "server");
        assert.strictEqual(u.w0Date, "2026-10-06");
        assert.strictEqual(u.strataCell, p.score <= 1 ? 0 : 1);
        assert.strictEqual(u.ahJanAhBakVariant,
            p.score % 2 ? "masculine" : "feminine");
        const map = (await db.doc(`research_id_map/${p.uid}`).get()).data();
        assert.strictEqual(map.researchId, p.rid);
        assert.strictEqual(map.via, "enrollment");
      }
      const logs = (await db.collection("arm_assignment_log").get()).docs
          .map((d) => d.data());
      assert.strictEqual(logs.filter((l) => l.action === "allocate").length,
          72);
      assert.ok(logs.every((l) => l.researchId && l.stratum &&
          l.sequencePosition && l.at && (l.by === "keran" ||
          l.by === "keran2")));
      const byK2 = logs.filter((l) => l.by === "keran2").length;
      assert.strictEqual(byK2, 36);
      report.push(["low", stats.low], ["high", stats.high]);
    });

test("resubmission returns the stored arm, logs it, uses no position",
    async () => {
      // Continues from the 72 above.
      const before = {
        low: (await db.doc("randomization_state/low").get()).get("next"),
        high: (await db.doc("randomization_state/high").get()).get("next"),
      };
      for (const uid of ["syn01", "syn02", "syn03", "syn04", "syn05"]) {
        const e = (await db.doc(`enrollments/${uid}`).get()).data();
        // Same input, then a different score: still the stored allocation.
        const same = await R.enrol(db, K1, input(uid, e.researchId,
            e.w0DjgEmotional), {now: NOW});
        const changed = await R.enrol(db, K2, input(uid, e.researchId,
            (e.w0DjgEmotional + 2) % 4), {now: NOW});
        for (const r of [same, changed]) {
          assert.strictEqual(r.alreadyEnrolled, true);
          assert.strictEqual(r.arm, e.arm);
          assert.strictEqual(r.stratum, e.stratum);
        }
        assert.strictEqual(same.sameInput, true);
        assert.strictEqual(changed.sameInput, false);
      }
      for (const s of R.STRATA) {
        assert.strictEqual((await db.doc(`randomization_state/${s}`).get())
            .get("next"), before[s]);
      }
      const resubmits = (await db.collection("arm_assignment_log")
          .where("action", "==", "resubmit").get()).size;
      assert.strictEqual(resubmits, 10);
    });

test("the same participant submitted twice at once: one allocation",
    async () => {
      await setup();
      await account("u1");
      const out = await Promise.all([K1, K2, K1, K2].map((k) =>
        R.enrol(db, k, input("u1", "B900", 0), {now: NOW})));
      assert.strictEqual(new Set(out.map((r) => r.arm)).size, 1);
      assert.strictEqual(out.filter((r) => !r.alreadyEnrolled).length, 1);
      assert.strictEqual((await db.doc("randomization_state/low").get())
          .get("next"), 1);
    });

test("two accounts, one research ID at once: one wins, one refused",
    async () => {
      await setup();
      await account("u1");
      await account("u2");
      const codes = await Promise.all(["u1", "u2"].map((uid) =>
        enrolCode(R.enrol(db, K1, input(uid, "B777", 3), {now: NOW}))));
      assert.deepStrictEqual(codes.sort(), ["no error", "research_id_taken"]);
      assert.strictEqual((await db.doc("randomization_state/high").get())
          .get("next"), 1);
    });

test("refused: account with an arm, tester, other research ID", async () => {
  await setup();
  await account("pilot", {arm: "A", armAssignmentMode: "force_a"});
  await account("tester", {isTester: true});
  await account("u3");
  await db.doc("research_id_map/u3").set({researchId: "P0ZAHP5"});
  assert.strictEqual(await enrolCode(R.enrol(db, K1,
      input("pilot", "B010", 1), {now: NOW})), "already_has_arm");
  assert.strictEqual(await enrolCode(R.enrol(db, K1,
      input("tester", "B011", 1), {now: NOW})), "tester_account");
  assert.strictEqual(await enrolCode(R.enrol(db, K1,
      input("u3", "B012", 1), {now: NOW})), "account_has_other_research_id");
  assert.strictEqual((await db.doc("randomization_state/low").get())
      .get("next"), 0);
});

test("sequence missing / exhausted", async () => {
  await setup({upload: false});
  await account("u1");
  assert.strictEqual(await enrolCode(R.enrol(db, K1, input("u1", "B001", 1),
      {now: NOW})), "sequence_missing");
  await db.doc("randomization_sequences/low").set({arms: ["B", "A"],
    blocks: [2], length: 2});
  await account("u2");
  await account("u3");
  await R.enrol(db, K1, input("u1", "B001", 1), {now: NOW});
  await R.enrol(db, K1, input("u2", "B002", 0), {now: NOW});
  assert.strictEqual(await enrolCode(R.enrol(db, K1, input("u3", "B003", 1),
      {now: NOW})), "sequence_exhausted");
});

test("correction: reason required, logged, position unchanged", async () => {
  await setup();
  await account("u1");
  const r = await R.enrol(db, K1, input("u1", "B001", 1), {now: NOW});
  const other = r.arm === "A" ? "B" : "A";
  assert.strictEqual(await enrolCode(R.correctArm(db, {uid: "u1",
    arm: other, reason: "short", operator: "k1"})), "reason_required");
  assert.strictEqual(await enrolCode(R.correctArm(db, {uid: "u1",
    arm: r.arm, reason: "a long enough reason", operator: "k1"})),
  "same_arm");
  await R.correctArm(db, {uid: "u1", arm: other,
    reason: "W0 score entered for the wrong person", operator: "k1"});
  assert.strictEqual((await db.doc("users/u1").get()).get("arm"), other);
  const e = (await db.doc("enrollments/u1").get()).data();
  assert.strictEqual(e.arm, other);
  assert.strictEqual(e.sequencePosition, 1);
  const log = (await db.collection("arm_assignment_log")
      .where("action", "==", "correction").get()).docs[0].data();
  assert.strictEqual(log.previousArm, r.arm);
  assert.strictEqual(log.arm, other);
  assert.match(log.reason, /wrong person/);
});

test("upload guard: no replace once uploaded or allocated", async () => {
  await setup();
  const again = await seqTool.upload(db, R.generateSequences(SEED), {});
  assert.strictEqual(again.ok, false);
  await account("u1");
  await R.enrol(db, K1, input("u1", "B001", 1), {now: NOW});
  const replace = await seqTool.upload(db,
      R.generateSequences("another-seed-0000001"), {replace: true});
  assert.strictEqual(replace.ok, false);
  assert.match(replace.lines.join("\n"), /already allocated/);
  const seq = (await db.doc("randomization_sequences/low").get()).data();
  assert.strictEqual(seq.sha256, R.generateSequences(SEED).low.sha256);
  assert.strictEqual(seq.seed, undefined, "the seed is never uploaded");
});

test("assignArm after registration returns the allocated arm", async () => {
  await setup();
  await account("u1");
  await account("u2");
  const r = await R.enrol(db, K1, input("u1", "B001", 2), {now: NOW});
  const a = await assignArm(db, "u1");
  assert.strictEqual(a.arm, r.arm);
  assert.strictEqual(a.assigned, false);
  const waiting = await assignArm(db, "u2");
  assert.strictEqual(waiting.arm, null);
});

test("blinded export of registered participants carries no arm",
    async () => {
      await setup();
      await db.doc(blinding.CONFIG_DOC).set({enabled: true});
      for (let i = 1; i <= 8; i++) {
        await account(`b${i}`);
        await R.enrol(db, K1, input(`b${i}`, `B10${i}`, i % 4),
            {now: NOW});
      }
      const built = await blinding.buildBlindedExport(db,
          {dateKey: "2026-10-11"});
      const rows = built.files.participants;
      assert.strictEqual(rows.length, 8);
      for (const row of rows) {
        assert.strictEqual(row.arm, undefined);
        assert.ok(/^B10\d$/.test(row.researchId), row.researchId);
        assert.ok(["Group_X", "Group_Y"].includes(row.groupCode));
      }
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t19-export-"));
      for (const name of Object.keys(built.files)) {
        if (!built.files[name].length) continue;
        fs.writeFileSync(path.join(dir, `${name}.ndjson`), built.files[name]
            .map((x) => JSON.stringify(x)).join("\n"));
      }
      const run = spawnSync("node", [CHECKER, dir], {encoding: "utf8"});
      assert.strictEqual(run.status, 0, run.stdout + run.stderr);
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
  for (const [s, v] of report) {
    console.log(`TABLE stratum=${s} n=${v.n} A=${v.a} B=${v.b} ` +
      `finalGap=${v.finalGap} maxGapDuring=${v.maxGap}`);
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();

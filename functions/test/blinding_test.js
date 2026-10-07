/**
 * T12 blinding — pure helpers and the export checker (no emulator).
 *   cd functions && node test/blinding_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const blinding = require("../blinding");
const checker = require("../../tool/check_blinded_export");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

function writeExport(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "blind-"));
  for (const name of Object.keys(files)) {
    fs.writeFileSync(path.join(dir, `${name}.ndjson`),
        files[name].map((r) => JSON.stringify(r)).join("\n"));
  }
  fs.writeFileSync(path.join(dir, "manifest.json"), "{}");
  return dir;
}

test("research IDs: P + 6 Crockford characters", () => {
  let i = 0;
  const seq = [0, 31, 10, 17, 22, 5];
  const rid = blinding.newResearchId(() => seq[i++ % seq.length]);
  assert.strictEqual(rid, "P0ZAHP5");
  assert.ok(blinding.RID_PATTERN.test(rid));
  for (let n = 0; n < 200; n++) {
    assert.ok(blinding.RID_PATTERN.test(
        blinding.newResearchId((k) => Math.floor(Math.random() * k))));
  }
});

test("only randomised, non-tester participants are exported", () => {
  const f = blinding.isBlindedParticipant;
  assert.strictEqual(f({arm: "A", armAssignmentMode: "randomise"}), true);
  assert.strictEqual(f({arm: "B", armAssignmentMode: "randomise"}), true);
  assert.strictEqual(f({arm: "A", armAssignmentMode: "force_a"}), false);
  assert.strictEqual(f({arm: null, armAssignmentMode: "randomise"}), false);
  assert.strictEqual(f({arm: "B", armAssignmentMode: "randomise",
    isTester: true}), false);
  // cohort (decision 0011) wins once it exists.
  assert.strictEqual(f({arm: "A", cohort: "phase_a",
    armAssignmentMode: "randomise"}), false);
  assert.strictEqual(f({arm: "B", cohort: "phase_b"}), true);
});

test("config defaults to off", () => {
  assert.deepStrictEqual(blinding.configFromSnap({exists: false}),
      {enabled: false, includeUsageSummary: false, includeBriefPr: false});
  assert.deepStrictEqual(blinding.configFromSnap({exists: true,
    data: () => ({enabled: "yes"})}),
  {enabled: false, includeUsageSummary: false, includeBriefPr: false});
  assert.deepStrictEqual(blinding.configFromSnap({exists: true,
    data: () => ({enabled: true, includeUsageSummary: true,
      includeBriefPr: true})}),
  {enabled: true, includeUsageSummary: true, includeBriefPr: true});
});

test("plain(): timestamps to ISO, references dropped", () => {
  const ts = {toDate: () => new Date("2026-10-07T01:02:03Z")};
  const ref = {path: "users/abc/turns/x", firestore: {}};
  assert.deepStrictEqual(blinding.plain({a: ts, b: ref, c: [1, {d: ts}]}),
      {a: "2026-10-07T01:02:03.000Z", b: null,
        c: [1, {d: "2026-10-07T01:02:03.000Z"}]});
});

test("isoWeekHk", () => {
  assert.strictEqual(blinding.isoWeekHk(new Date("2026-10-07T04:00:00Z")),
      "2026-W41");
  // Sunday 23:30 HKT is still that ISO week.
  assert.strictEqual(blinding.isoWeekHk(new Date("2026-10-11T15:30:00Z")),
      "2026-W41");
  // Monday 00:30 HKT = Sunday 16:30 UTC → next week.
  assert.strictEqual(blinding.isoWeekHk(new Date("2026-10-11T16:30:00Z")),
      "2026-W42");
  assert.strictEqual(blinding.isoWeekHk(new Date("2027-01-01T04:00:00Z")),
      "2026-W53");
});

test("exported field lists never contain a denied field", () => {
  const denied = {};
  for (const k of checker.DENY_KEYS) denied[k.toLowerCase()] = true;
  const lists = [blinding.PARTICIPANT_FIELDS, ["enrolledDate"]];
  for (const n of Object.keys(blinding.OUTCOME_COLLECTIONS)) {
    lists.push(blinding.OUTCOME_COLLECTIONS[n]);
    assert.ok(checker.ALLOWED_FILES.indexOf(n) >= 0, n);
    assert.ok(checker.HELD_BACK_FILES.indexOf(n) < 0, n);
  }
  for (const list of lists) {
    for (const f of list) assert.ok(!denied[f.toLowerCase()], f);
  }
  for (const n of blinding.HELD_BACK) {
    assert.ok(checker.ALLOWED_FILES.indexOf(n) < 0, n);
  }
});

test("checker passes a clean export", () => {
  const dir = writeExport({
    participants: [{researchId: "P0ZAHQ5", groupCode: "Group_X",
      strataCell: 2, ageGroup: "70-74", enrolledDate: "2026-10-01"}],
    brief_pr: [{researchId: "P0ZAHQ5", groupCode: "Group_X",
      agentId: "siu_yan", understanding: 6, status: "completed",
      respondedAt: "2026-10-07T01:02:03.000Z"}],
    djg_responses: [{researchId: "P0ZAHQ5", groupCode: "Group_X",
      timepoint: "W2", itemsVersion: "djg6_pkg3_v1",
      answers: {q1: "yes", q2: "mostly", q3: "no", q4: "no", q5: "skipped",
        q6: "yes"},
      status: "submitted", scores: {emotional: 2, social: null, total: null},
      scoringVersion: "djg6_pkg3_v1", outsideWindow: false,
      w0Date: "2026-10-01", windowStartDate: "2026-10-14",
      windowEndDate: "2026-10-20", pushSentAt: "2026-10-14T02:00:00.000Z",
      submittedAt: "2026-10-14T02:08:00.000Z"}],
  });
  assert.deepStrictEqual(checker.checkExport([dir]).findings, []);
});

test("checker flags every kind of leak", () => {
  const rid = {researchId: "P0ZAHQ5", groupCode: "Group_Y"};
  const dir = writeExport({
    llm_turn_features: [Object.assign({agentId: "siu_yan"}, rid)],
    turns: [Object.assign({llm: {status: "rule_based"}}, rid)],
    mem_facts: [rid],
    participants: [
      Object.assign({arm: "B"}, rid),
      {uidHash: "0123456789abcdef", groupCode: "Group_X"},
      {researchId: "P0ZAHQ5", groupCode: "B"},
    ],
    brief_pr: [
      Object.assign({sessionRef: "users/abc/sessions/s1"}, rid),
      Object.assign({status: "rule_based"}, rid),
      Object.assign({agentId: "a".repeat(28)}, rid),
    ],
    safety_events: [Object.assign({source: "gateway_output"}, rid)],
    agent_diff: [Object.assign({personality: {siu_yan: {x: "長".repeat(80)}}},
        rid)],
    djg_responses: [Object.assign({timepoint: "W2", arm: "A",
      source: "cf_djgW2Dispatch"}, rid)],
    random_new_collection: [rid],
  });
  const findings = checker.checkExport([dir]).findings;
  const has = (re) => assert.ok(findings.some((f) => re.test(f)),
      `expected ${re} in\n${findings.join("\n")}`);
  has(/llm_turn_features.*must not be exported/);
  has(/turns.*must not be exported/);
  has(/mem_facts.*must not be exported/);
  has(/random_new_collection.*not on the blinded-export allowlist/);
  has(/participants:1\.arm: field not allowed/);
  has(/participants:2: researchId missing/);
  has(/participants:2\.uidHash: field not allowed/);
  has(/participants:3: groupCode "B"/);
  has(/brief_pr:1\.sessionRef: field not allowed/);
  has(/brief_pr:1\.sessionRef: value .* raw uid/);
  has(/brief_pr:2\.status: value "rule_based" names the rule-based arm/);
  has(/brief_pr:3\.agentId: .* raw Firebase uid/);
  has(/safety_events:1\.source: field not allowed/);
  has(/agent_diff:1\.personality\.siu_yan\.x: 80-character string/);
  has(/djg_responses:1\.arm: field not allowed/);
  has(/djg_responses:1\.source: field not allowed/);
});

test("checker CLI: exit 0 clean, 1 on findings, 2 on nothing", () => {
  const {spawnSync} = require("child_process");
  const cli = path.join(__dirname, "..", "..", "tool",
      "check_blinded_export.js");
  const clean = writeExport({participants: [{researchId: "P0ZAHQ5",
    groupCode: "Group_X"}]});
  const dirty = writeExport({participants: [{researchId: "P0ZAHQ5",
    groupCode: "Group_X", arm: "A"}]});
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), "blind-"));
  assert.strictEqual(spawnSync("node", [cli, clean]).status, 0);
  assert.strictEqual(spawnSync("node", [cli, dirty]).status, 1);
  assert.strictEqual(spawnSync("node", [cli, empty]).status, 2);
  assert.strictEqual(spawnSync("node", [cli]).status, 2);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (e) {
      failed++;
      console.error(`not ok - ${t.name}\n${e.stack}`);
    }
  }
  if (failed) {
    console.error(`${failed} test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} blinding tests passed`);
})();

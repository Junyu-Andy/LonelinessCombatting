/**
 * T30 — pure logic: the DJG-ES definition matches the spec file word for
 * word and scores like the in-App W2; PHQ-9 mechanism; the sequence tool
 * builds a payload without the seed and talks to the callable.
 *
 * Run:  cd functions && node test/outcome_instruments_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const inst = require("../outcome_instruments");
const djgW2 = require("../djg_w2");
const assessor = require("../assessor");
const qs = require("../questionnaire_safety");
const seqTool = require("../../tool/randomization_sequence");
const R = require("../randomization");
const provision = require("../../tool/provision_researcher");
const analysis = require("../../tool/analysis_export");

let passed = 0;
const failures = [];
const pending = [];
function test(name, fn) {
  const run = async () => {
    try {
      await fn();
      passed++;
      console.log(`ok - ${name}`);
    } catch (err) {
      failures.push(name);
      console.log(`FAIL - ${name}\n      ${err.stack}`);
    }
  };
  pending.push(run);
}

const SPEC = fs.readFileSync(path.join(__dirname, "..", "..", "docs", "spec",
    "instruments", "djg_es.md"), "utf8");

function specItems() {
  return SPEC.split("\n").filter((l) => /^\| q\d \|/.test(l)).map((l) => {
    const c = l.split("|").map((x) => x.trim());
    return {id: c[1], subscale: c[2], text: c[3]};
  });
}

function specOptions() {
  return SPEC.split("\n").filter((l) => /^\| (yes|mostly|no) \|/.test(l))
      .map((l) => {
        const c = l.split("|").map((x) => x.trim());
        return [c[1], c[2]];
      });
}

test("DJG-ES items and options equal docs/spec/instruments/djg_es.md", () => {
  const items = specItems();
  assert.strictEqual(items.length, 6);
  assert.deepStrictEqual(inst.DJG_ES.items, items);
  assert.deepStrictEqual(inst.DJG_ES.options, specOptions());
  assert.ok(!inst.hasPlaceholderText(inst.DJG_ES));
});

test("DJG-ES scores exactly like functions/djg_w2.js", () => {
  const cases = [
    {q1: "yes", q2: "mostly", q3: "no", q4: "yes", q5: "mostly", q6: "no"},
    {q1: "no", q2: "no", q3: "no", q4: "yes", q5: "yes", q6: "yes"},
    {q1: "yes", q2: "yes", q3: "yes", q4: "no", q5: "no", q6: "no"},
    {q1: "skipped", q2: "yes", q3: "yes", q4: "no", q5: "no", q6: "no"},
    {q1: "yes", q2: "yes", q3: "yes", q4: "no", q5: "skipped", q6: "no"},
  ];
  for (const a of cases) {
    assert.deepStrictEqual(inst.DJG_ES.score(a), djgW2.scoreAnswers(a),
        JSON.stringify(a));
  }
  assert.deepStrictEqual(inst.DJG_ES.score(cases[2]),
      {emotional: 3, social: 3, total: 6});
  assert.deepStrictEqual(inst.DJG_ES.score(cases[3]),
      {emotional: null, social: 3, total: null});
});

test("answers are validated against the instrument", () => {
  const ok = inst.validateAnswers(inst.DJG_ES,
      {q1: "yes", q2: "no", q3: "mostly", q4: "yes", q5: "no"});
  assert.deepStrictEqual(ok.missingItems, ["q6"]);
  assert.strictEqual(ok.answers.q6, "skipped");
  assert.strictEqual(inst.validateAnswers(inst.DJG_ES, {q1: "maybe"}), null);
  assert.strictEqual(inst.validateAnswers(inst.DJG_ES, {q7: "yes"}), null);
  assert.strictEqual(inst.validateAnswers(inst.DJG_ES, null), null);
  assert.strictEqual(inst.validateAnswers(inst.DJG_ES, ["yes"]), null);
  assert.strictEqual(inst.instrumentFor("UCLA-3"), null);
});

test("PHQ-9: placeholder text, 0–3 raw, total only when complete, " +
    "item 9 is the T34 trigger", () => {
  assert.ok(inst.hasPlaceholderText(inst.PHQ_9));
  const full = {};
  for (let i = 1; i <= 9; i++) full[`q${i}`] = 1;
  assert.deepStrictEqual(inst.PHQ_9.score(full), {total: 9, answered: 9});
  const partial = Object.assign({}, full, {q3: "skipped"});
  assert.deepStrictEqual(inst.PHQ_9.score(
      inst.validateAnswers(inst.PHQ_9, partial).answers),
  {total: null, answered: 8});
  assert.strictEqual(inst.validateAnswers(inst.PHQ_9, {q1: 4}), null);
  assert.deepStrictEqual(inst.PHQ_9.safetyItem, {item: 9, answerId: "q9"});
  assert.ok(qs.triggers({instrument: "PHQ-9", item: 9, rawValue: 2}));
  assert.ok(!qs.triggers({instrument: "PHQ-9", item: 9, rawValue: 0}));
});

test("W4 window: day 25–31 from W0; before / open / after", () => {
  const w = assessor.w4Window("2026-11-01", "2026-11-26");
  assert.deepStrictEqual(w, {windowStartDate: "2026-11-26",
    windowEndDate: "2026-12-02", studyDay: 25, windowState: "open"});
  assert.strictEqual(assessor.w4Window("2026-11-01", "2026-11-25")
      .windowState, "before");
  assert.strictEqual(assessor.w4Window("2026-11-01", "2026-12-02")
      .windowState, "open");
  assert.strictEqual(assessor.w4Window("2026-11-01", "2026-12-03")
      .windowState, "after");
  assert.deepStrictEqual(assessor.W4_WINDOW, {start: 25, end: 31});
});

test("pooled completion row hides n < 5", () => {
  const r = assessor.summaryRow("DJG-ES", "W4", 4, 4);
  assert.strictEqual(r.suppressed, true);
  assert.strictEqual(r.n, null);
  assert.strictEqual(r.rate, null);
  const s = assessor.summaryRow("DJG-ES", "W4", 8, 6);
  assert.deepStrictEqual(s, {instrument: "DJG-ES", timepoint: "W4",
    suppressed: false, n: 8, completed: 6, rate: 0.75});
});

test("roles: sequence_uploader exists; legacy names stay legacy", () => {
  assert.deepStrictEqual(provision.ROLES,
      ["unblinded", "blinded", "sequence_uploader"]);
  assert.deepStrictEqual(provision.LEGACY_ROLES, ["pi", "researcher"]);
});

test("sequence tool: the payload carries arms, blocks and fingerprints — " +
    "never the seed", () => {
  const seed = "unit-test-seed-0000000001";
  const seqs = R.generateSequences(seed);
  const payload = seqTool.buildPayload(seqs, {replace: false});
  const json = JSON.stringify(payload);
  assert.ok(!json.includes(seed));
  assert.ok(!("seed" in payload));
  for (const s of R.STRATA) {
    assert.deepStrictEqual(Object.keys(payload.sequences[s]).sort(),
        ["arms", "blocks", "sha256"]);
    assert.strictEqual(payload.sequences[s].sha256, seqs[s].sha256);
  }
  assert.strictEqual(payload.replace, false);
});

test("sequence tool: target — emulator needs both hosts; production " +
    "needs --project and --production-confirm", () => {
  const emu = seqTool.callableTarget({FIREBASE_AUTH_EMULATOR_HOST: "h:9099",
    FUNCTIONS_EMULATOR_HOST: "h:5001"}, {project: "demo-x"});
  assert.ok(emu.ok);
  assert.match(emu.functionUrl,
      /^http:\/\/h:5001\/demo-x\/asia-east2\/uploadRandomizationSequence$/);
  assert.ok(!seqTool.callableTarget({FIREBASE_AUTH_EMULATOR_HOST: "h"}, {}).ok);
  assert.ok(!seqTool.callableTarget({}, {}).ok);
  assert.ok(!seqTool.callableTarget({}, {project: "real"}).ok);
  const prod = seqTool.callableTarget({}, {"project": "real",
    "production-confirm": "real", "api-key": "K"});
  assert.ok(prod.ok);
  assert.strictEqual(prod.functionUrl,
      "https://asia-east2-real.cloudfunctions.net/uploadRandomizationSequence");
  assert.ok(prod.authUrl.endsWith("key=K"));
});

test("sequence tool: signs in with the user's own login, then calls the " +
    "callable with the bearer token (no service account)", async () => {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({url, init});
    if (url.includes("signInWithPassword")) {
      return {ok: true, status: 200, json: async () => ({idToken: "ID-T"})};
    }
    return {ok: true, status: 200,
      json: async () => ({result: {uploaded: {low: {length: 60}}}})};
  };
  const r = await seqTool.uploadViaCallable({fetch,
    authUrl: "http://auth/signInWithPassword?key=k",
    functionUrl: "F", email: "calvin@x", password: "pw",
    payload: {sequences: {}, replace: false}});
  assert.ok(r.ok);
  assert.strictEqual(calls.length, 2);
  assert.strictEqual(JSON.parse(calls[0].init.body).email, "calvin@x");
  assert.strictEqual(calls[1].init.headers.Authorization, "Bearer ID-T");
  assert.deepStrictEqual(JSON.parse(calls[1].init.body),
      {data: {sequences: {}, replace: false}});
  const bad = await seqTool.uploadViaCallable({
    fetch: async () => ({ok: false, status: 400,
      json: async () => ({error: {message: "INVALID_PASSWORD"}})}),
    authUrl: "A", functionUrl: "F", email: "e", password: "p", payload: {}});
  assert.strictEqual(bad.ok, false);
  assert.strictEqual(bad.body.error, "INVALID_PASSWORD");
});

test("analysis export: synthetic set has 72 people, two arms, two strata, " +
    "missingness, every row labelled synthetic, no Firestore", () => {
  const built = analysis.generateSynthetic({seed: "unit"});
  assert.strictEqual(built.files.participants.length, 72);
  const arms = new Set(built.files.participants.map((p) => p.arm));
  assert.deepStrictEqual([...arms].sort(), ["A", "B"]);
  const strata = new Set(built.files.participants.map((p) => p.stratum));
  assert.deepStrictEqual([...strata].sort(), ["high", "low"]);
  assert.ok(built.files.outcome_entries.length < 72, "some W4 missing");
  assert.ok(built.files.outcome_entries.some((e) => e.missingItems.length),
      "some items skipped");
  for (const t of Object.keys(built.files)) {
    for (const r of built.files[t]) {
      assert.strictEqual(r.dataset, "synthetic", t);
      assert.deepStrictEqual(Object.keys(r), analysis.TABLES[t], t);
    }
  }
  assert.strictEqual(built.manifest.synthetic, true);
  // Same seed → same data (reproducible dry runs).
  assert.deepStrictEqual(analysis.generateSynthetic({seed: "unit"}).files
      .outcome_entries[0], built.files.outcome_entries[0]);
});

test("analysis export: no table has a text column", () => {
  const forbidden = new RegExp("^(text|message|content|reply|prompt|quote|" +
    "summary|matchedTerm|snippet|input|output)$");
  for (const t of Object.keys(analysis.TABLES)) {
    for (const c of analysis.TABLES[t]) {
      assert.ok(!forbidden.test(c), `${t}.${c}`);
    }
  }
  assert.ok(!analysis.TABLES.turns.includes("text"));
});

(async () => {
  for (const run of pending) await run();
  console.log(`\n${passed} passed, ${failures.length} failed.`);
  process.exit(failures.length ? 1 : 0);
})();

/**
 * T21 (registry v8 C01, dev-tasks-1010 §3 T21 item 2) — the enrolment
 * gate on the server, against the Firestore emulator.
 *
 * With app_config/feature_flags.enrollmentGateEnabled on, an account that
 * is neither enrolled (cohort phase_b / pilot) nor a tester is refused
 * every LLM call, and the refusal is logged in llm_denied_log with reason
 * "not_enrolled" (no text, no arm).  Off — the default — nothing changes.
 * Arm B is refused either way, as in T19.
 *
 * DeepSeek is a stub (global fetch replaced): no network, no API key.
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/enrollment_gate_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";

let modelCalls = 0;
global.fetch = async () => {
  modelCalls++;
  const resp = {
    model: "deepseek-flash",
    choices: [{message: {role: "assistant", content: "今日去咗飲茶呀？"}}],
    system_fingerprint: "fp_stub",
    usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
  };
  return {ok: true, status: 200, json: async () => resp,
    text: async () => ""};
};

const fns = require("../index");
const studyPeriod = require("../study_period");
const admin = require("firebase-admin");
const db = admin.firestore();

async function clear(name) {
  const docs = await db.collection(name).listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
}

async function reset(gate) {
  for (const n of ["users", "llm_calls", "llm_denied_log", "app_config"]) {
    await clear(n);
  }
  await db.doc("meta/memory_config").set({enabled: false});
  if (gate !== undefined) {
    await db.doc("app_config/feature_flags").set(
        {enrollmentGateEnabled: gate});
  }
  studyPeriod.resetGateCache();
  modelCalls = 0;
}

const chat = (uid) => fns.proxyDeepSeek.run({
  auth: {uid},
  data: {
    promptKey: "siu_yan_v1",
    agentId: "siu_yan",
    moduleId: "m2_check_in",
    messages: [{role: "user", content: "早晨"}],
  },
});

const denied = async () => (await db.collection("llm_denied_log").get())
    .docs.map((d) => d.data());

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("gate off (no flags doc): an unregistered account still chats",
    async () => {
      await reset();
      await db.doc("users/new1").set({displayName: "x"});
      const out = await chat("new1");
      assert.ok(out.text);
      assert.strictEqual(modelCalls, 1);
      assert.strictEqual((await denied()).length, 0);
    });

test("gate off (flag false or a string): no change", async () => {
  for (const v of [false, "true"]) {
    await reset(v);
    await db.doc("users/new1").set({arm: "A", armAssignmentMode: "force_a"});
    await chat("new1");
    assert.strictEqual(modelCalls, 1, String(v));
    assert.strictEqual((await denied()).length, 0, String(v));
  }
});

test("gate on: an unregistered account is refused and logged", async () => {
  await reset(true);
  await db.doc("users/new1").set({arm: "A", armAssignmentMode: "force_a",
    displayName: "x"});
  await assert.rejects(chat("new1"),
      /permission-denied|Not registered/);
  assert.strictEqual(modelCalls, 0);
  const rows = await denied();
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].uid, "new1");
  assert.strictEqual(rows[0].endpoint, "proxyDeepSeek");
  assert.strictEqual(rows[0].reason, "not_enrolled");
  assert.strictEqual(rows[0].arm, undefined);
  assert.strictEqual((await db.collection("llm_calls")
      .where("uid", "==", "new1").get()).size, 0);
});

test("gate on: no profile doc at all is refused too", async () => {
  await reset(true);
  await assert.rejects(chat("ghost"), /permission-denied|Not registered/);
  assert.strictEqual((await denied())[0].reason, "not_enrolled");
});

test("gate on: testers, Phase B and pilot Arm A accounts chat", async () => {
  await reset(true);
  await db.doc("users/tester").set({isTester: true});
  await db.doc("users/pb").set({arm: "A", armAssignmentMode: "randomise",
    cohort: "phase_b"});
  await db.doc("users/pilot").set({arm: "A",
    armAssignmentMode: "pilot_designated", cohort: "pilot"});
  for (const uid of ["tester", "pb", "pilot"]) {
    const out = await chat(uid);
    assert.ok(out.text, uid);
  }
  assert.strictEqual(modelCalls, 3);
  assert.strictEqual((await denied()).length, 0);
});

test("gate on or off: Arm B refused as in T19 (no reason field)",
    async () => {
      for (const gate of [true, false]) {
        await reset(gate);
        await db.doc("users/rb").set({arm: "B", cohort: "pilot",
          armAssignmentMode: "pilot_designated"});
        await assert.rejects(chat("rb"), /permission-denied|not part/);
        const rows = await denied();
        assert.strictEqual(rows.length, 1);
        assert.strictEqual(rows[0].reason, undefined);
        assert.strictEqual(modelCalls, 0);
      }
    });

test("registration takes effect at once (user doc read fresh)",
    async () => {
      await reset(true);
      await db.doc("users/late").set({displayName: "x"});
      await assert.rejects(chat("late"), /permission-denied|Not registered/);
      await db.doc("users/late").set({arm: "A",
        armAssignmentMode: "randomise", cohort: "phase_b"}, {merge: true});
      const out = await chat("late");
      assert.ok(out.text);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ok  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`  FAIL ${t.name}\n       ${err.stack}`);
    }
  }
  console.log(`enrollment_gate_emulator_test: ${tests.length - failed}/` +
    `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

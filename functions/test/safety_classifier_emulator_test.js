/**
 * T8 safety-classifier relay (`classifySafety`) — against the Firestore
 * emulator and a local fake model (a plain HTTP server on 127.0.0.1).
 *
 *   1. Switch off (default) → status "disabled", the model is never
 *      called, one log row.
 *   2. Normal → level + score + modelVersion; any text the model sends
 *      back is dropped; one log row without the text and without the arm.
 *   3. Timeout → status "timeout" within the server limit; one log row.
 *   4. Failure (HTTP 500, malformed answer) → status "error"; one log row.
 *   5. Both arms get the same answer; Arm B is still refused by
 *      proxyDeepSeek (assertLlmAllowed is untouched).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/safety_classifier_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const http = require("http");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";
process.env.SAFETY_CLASSIFIER_TOKEN = "fake-token";

// ---- fake model -----------------------------------------------------------
let mode = "ok";
let hits = [];
const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => {
    body += c;
  });
  req.on("end", () => {
    hits.push({auth: req.headers["authorization"], body: JSON.parse(body)});
    const send = (status, obj) => {
      res.writeHead(status, {"Content-Type": "application/json"});
      res.end(JSON.stringify(obj));
    };
    if (mode === "ok") {
      send(200, {level: "acute", score: 0.91, model_version: "lora-fake-1",
        text: "MODEL WROTE THIS", rationale: "should never leave"});
    } else if (mode === "slow") {
      setTimeout(() => send(200, {level: "acute", score: 0.9}), 1500);
    } else if (mode === "fail") {
      send(500, {error: "boom"});
    } else if (mode === "bad") {
      send(200, {level: "very_bad", score: 7});
    }
  });
});

// DeepSeek must never be reached from classifySafety.
let deepseekCalls = 0;
const realFetch = global.fetch;
global.fetch = async (url, init) => {
  if (String(url).indexOf("deepseek") >= 0) {
    deepseekCalls++;
    throw new Error("DeepSeek must not be called");
  }
  return realFetch(url, init);
};

const fns = require("../index");
const {resetSafetyConfigCache} = require("../safety_config");
const sc = require("../safety_classifier");
const admin = require("firebase-admin");
const db = admin.firestore();

let URL_BASE = "";

async function clear(name) {
  const docs = await db.collection(name).listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
}

async function reset(cfg) {
  await clear("safety_classifier_calls");
  await db.doc("users/arm_a_user").set({arm: "A"});
  await db.doc("users/arm_b_user").set({arm: "B"});
  if (cfg) {
    await db.doc("meta/safety_config").set(cfg);
  } else {
    await db.doc("meta/safety_config").delete();
  }
  resetSafetyConfigCache();
  hits = [];
  mode = "ok";
}

const on = () => ({classifierEnabled: true, classifierUrl: URL_BASE,
  classifierTimeoutMs: 400});

const classify = (uid, text) => fns.classifySafety.run({
  auth: {uid: uid},
  data: {text: text || "我想死咗佢", inputPoint: "check_in_note",
    source: "user_input", turnId: "turn-1"},
});

async function rows() {
  return (await db.collection("safety_classifier_calls").get()).docs
      .map((d) => d.data());
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off by default: disabled, model not called, one row",
    async () => {
      await reset();
      const out = await classify("arm_a_user");
      assert.deepStrictEqual(out, {status: "disabled", level: null,
        score: null, modelVersion: null});
      assert.strictEqual(hits.length, 0);
      const r = await rows();
      assert.strictEqual(r.length, 1);
      assert.strictEqual(r[0].status, "disabled");
    });

test("switch on but no address: disabled", async () => {
  await reset({classifierEnabled: true});
  const out = await classify("arm_a_user");
  assert.strictEqual(out.status, "disabled");
  assert.strictEqual(hits.length, 0);
});

test("normal: level + score only; model text dropped; row has no text",
    async () => {
      await reset(on());
      const out = await classify("arm_a_user", "我想死咗佢 電話 91234567");
      assert.deepStrictEqual(out, {status: "ok", level: "acute",
        score: 0.91, modelVersion: "lora-fake-1"});
      assert.strictEqual(hits.length, 1);
      assert.strictEqual(hits[0].auth, "Bearer fake-token");
      // Only {text}; personal numbers stripped before leaving the server.
      assert.deepStrictEqual(Object.keys(hits[0].body), ["text"]);
      assert.ok(!/91234567/.test(hits[0].body.text), hits[0].body.text);
      const r = await rows();
      assert.strictEqual(r.length, 1);
      const row = r[0];
      assert.strictEqual(row.writer, "server");
      assert.strictEqual(row.uid, "arm_a_user");
      assert.strictEqual(row.status, "ok");
      assert.strictEqual(row.level, "acute");
      assert.strictEqual(row.score, 0.91);
      assert.strictEqual(row.input_point, "check_in_note");
      assert.strictEqual(row.source, "user_input");
      assert.strictEqual(row.turn_id, "turn-1");
      assert.strictEqual(row.text_length, "我想死咗佢 電話 91234567".length);
      assert.ok(!("arm" in row), "no arm in the log");
      // Without the timestamp: its seconds / nanoseconds can contain the
      // digits being searched for (flaky "999" / "2382" hits).
      const noTs = Object.assign({}, row);
      delete noTs.ts;
      const flat = JSON.stringify(noTs);
      assert.ok(!/想死|91234567|MODEL WROTE|rationale/.test(flat), flat);
    });

test("timeout: status timeout within the server limit; one row",
    async () => {
      await reset(on());
      mode = "slow";
      const t0 = Date.now();
      const out = await classify("arm_a_user");
      const took = Date.now() - t0;
      assert.strictEqual(out.status, "timeout");
      assert.strictEqual(out.level, null);
      assert.ok(took < 1200, `took ${took} ms`);
      const r = await rows();
      assert.strictEqual(r.length, 1);
      assert.strictEqual(r[0].status, "timeout");
      assert.strictEqual(r[0].timeout_ms, 400);
    });

test("failure: HTTP 500 → error; one row", async () => {
  await reset(on());
  mode = "fail";
  const out = await classify("arm_a_user");
  assert.strictEqual(out.status, "error");
  assert.strictEqual(out.level, null);
  assert.strictEqual((await rows())[0].status, "error");
});

test("failure: malformed answer → error", async () => {
  await reset(on());
  mode = "bad";
  const out = await classify("arm_a_user");
  assert.strictEqual(out.status, "error");
});

test("failure: address unreachable → error", async () => {
  await reset({classifierEnabled: true,
    classifierUrl: "http://127.0.0.1:1/classify", classifierTimeoutMs: 400});
  const out = await classify("arm_a_user");
  assert.strictEqual(out.status, "error");
});

test("long text is cut to classifierMaxChars", async () => {
  await reset(Object.assign(on(), {classifierMaxChars: 50}));
  await classify("arm_a_user", "好".repeat(120));
  assert.strictEqual(hits[0].body.text.length, 50);
  const row = (await rows())[0];
  assert.strictEqual(row.truncated, true);
  assert.strictEqual(row.text_length, 120);
});

test("both arms: same answer; Arm B still refused by proxyDeepSeek",
    async () => {
      await reset(on());
      const a = await classify("arm_a_user");
      const b = await classify("arm_b_user");
      assert.deepStrictEqual(a, b);
      await assert.rejects(fns.proxyDeepSeek.run({
        auth: {uid: "arm_b_user"},
        data: {promptKey: "siu_yan_v1", moduleId: "m2_check_in",
          messages: [{role: "user", content: "hi"}]},
      }), /not part of this study arm/);
      assert.strictEqual(deepseekCalls, 0);
    });

test("signed-out callers are refused", async () => {
  await reset(on());
  await assert.rejects(fns.classifySafety.run({data: {text: "x"}}),
      /Sign in required/);
});

test("parseModelResponse keeps only level / score / version", () => {
  assert.deepStrictEqual(
      sc.parseModelResponse({level: "low", score: 0.2, modelVersion: "v",
        text: "x"}),
      {level: "low", score: 0.2, modelVersion: "v"});
  assert.strictEqual(sc.parseModelResponse({level: "LOW"}), null);
  assert.strictEqual(sc.parseModelResponse(null), null);
  assert.deepStrictEqual(sc.parseModelResponse({level: "none", score: 3}),
      {level: "none", score: null, modelVersion: null});
});

(async () => {
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  URL_BASE = `http://127.0.0.1:${server.address().port}/classify`;
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok   ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`FAIL ${t.name}\n${err.stack}`);
    }
  }
  server.close();
  console.log(`${tests.length - failed}/${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

/**
 * C04 model log — pure unit tests (no emulator, no network).
 *
 * Run: node test/llm_log_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const log = require("../llm_log");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

function fakeDb() {
  const rows = [];
  return {
    rows,
    collection(name) {
      return {add: async (row) => rows.push({name, row})};
    },
  };
}

function fakeFetch(status, body) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({url, init});
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
      text: async () => JSON.stringify(body),
    };
  };
  fn.calls = calls;
  return fn;
}

const OK_BODY = {
  model: "deepseek-flash", // what the live API returned on 2026-10-06
  choices: [{message: {content: "你好呀，今日點呀？"}}],
  system_fingerprint: "fp_test_0001",
  usage: {prompt_tokens: 120, completion_tokens: 15,
    completion_tokens_details: {reasoning_tokens: 0}},
};
const LOG = {callType: "chat", agentId: "siu_yan", uid: "u1"};

test("callTypeForModule covers every proxyDeepSeek moduleId", () => {
  const cases = {
    "m2_check_in": "chat",
    "tung_tung_chat": "chat",
    "reflective_dialogue": "chat",
    "m3_reminiscence_w2": "chat",
    "m3_reminiscence_w2_opener": "chat",
    "m6_suggestions": "suggestions",
    "rolling_summary_fold": "memory_summary",
    "m7_action_loop_followup": "chat",
    "greeting_siu_yan": "greeting",
    "m3_reminiscence_w2_summary": "session_summary",
    "m7_action_loop_summary": "session_summary",
    "m9_progress_summary": "weekly_summary",
    "m8_education_sleep": "article_qa",
    "unknown": "chat",
  };
  for (const [moduleId, want] of Object.entries(cases)) {
    assert.strictEqual(log.callTypeForModule(moduleId), want, moduleId);
  }
  assert.strictEqual(log.callTypeForModule(undefined), "chat");
  for (const v of Object.values(cases)) {
    assert.ok(log.CALL_TYPES.includes(v), v);
  }
});

test("success: one row with the returned model and token counts", async () => {
  const db = fakeDb();
  const f = fakeFetch(200, OK_BODY);
  const res = await log.deepSeekChat(db, {
    apiKey: "k", log: LOG, fetchImpl: f,
    headers: {"X-Session-Code": "abc"},
    body: {model: "deepseek-flash", messages: [{role: "user", content: "x"}]},
  });
  assert.strictEqual(res.ok, true);
  assert.deepStrictEqual(res.data, OK_BODY);
  assert.strictEqual(f.calls.length, 1);
  assert.strictEqual(f.calls[0].url, log.DEEPSEEK_URL);
  assert.strictEqual(f.calls[0].init.headers["X-Session-Code"], "abc");
  assert.strictEqual(f.calls[0].init.headers.Authorization, "Bearer k");
  assert.strictEqual(db.rows.length, 1);
  const {name, row} = db.rows[0];
  assert.strictEqual(name, "llm_calls");
  assert.deepStrictEqual(Object.keys(row).sort(), [
    "agent_id", "call_type", "completion_tokens", "error",
    "http_status", "latency_ms", "model_requested", "model_returned",
    "prompt_tokens", "reasoning_tokens", "system_fingerprint", "ts",
    "uid",
  ]);
  assert.strictEqual(row.call_type, "chat");
  assert.strictEqual(row.agent_id, "siu_yan");
  assert.strictEqual(row.uid, "u1");
  assert.strictEqual(row.model_requested, "deepseek-flash");
  assert.strictEqual(row.model_returned, "deepseek-flash");
  assert.strictEqual(row.prompt_tokens, 120);
  assert.strictEqual(row.completion_tokens, 15);
  assert.strictEqual(row.system_fingerprint, "fp_test_0001");
  assert.strictEqual(row.http_status, 200);
  assert.strictEqual(row.reasoning_tokens, 0);
  assert.strictEqual(row.error, false);
  assert.ok(row.latency_ms >= 0);
  assert.ok(Math.abs(row.ts.toMillis() - Date.now()) < 5000);
  // No prompt or completion text anywhere in the row.
  const flat = JSON.stringify(row);
  assert.ok(!flat.includes("今日點呀"), "completion text leaked");
});

test("non-2xx: logged as error, returned to the caller", async () => {
  const db = fakeDb();
  const res = await log.deepSeekChat(db, {
    apiKey: "k", log: LOG, fetchImpl: fakeFetch(429, {error: "rate"}),
    body: {model: "deepseek-flash"},
  });
  assert.strictEqual(res.ok, false);
  assert.strictEqual(res.status, 429);
  assert.ok(res.errorBody.includes("rate"));
  const row = db.rows[0].row;
  assert.strictEqual(row.error, true);
  assert.strictEqual(row.model_returned, null);
  assert.strictEqual(row.prompt_tokens, null);
  assert.strictEqual(row.system_fingerprint, null);
  assert.strictEqual(row.reasoning_tokens, null);
});

test("model_requested comes from the request body, not a constant",
    async () => {
      const db = fakeDb();
      await log.deepSeekChat(db, {
        apiKey: "k", log: LOG, fetchImpl: fakeFetch(200, {model: "x"}),
        body: {model: "some-future-model", thinking: {type: "disabled"}},
      });
      const row = db.rows[0].row;
      assert.strictEqual(row.model_requested, "some-future-model");
      // Optional fields absent from the response are stored as null.
      assert.strictEqual(row.system_fingerprint, null);
      assert.strictEqual(row.reasoning_tokens, null);
    });

test("network failure: logged as error, then rethrown", async () => {
  const db = fakeDb();
  const boom = async () => {
    throw new Error("ECONNRESET");
  };
  await assert.rejects(log.deepSeekChat(db, {
    apiKey: "k", log: LOG, fetchImpl: boom, body: {model: "deepseek-flash"},
  }), /ECONNRESET/);
  assert.strictEqual(db.rows.length, 1);
  assert.strictEqual(db.rows[0].row.error, true);
});

test("a failed log write never fails the call", async () => {
  const db = {collection: () => ({add: async () => {
    throw new Error("firestore down");
  }})};
  const res = await log.deepSeekChat(db, {
    apiKey: "k", log: LOG, fetchImpl: fakeFetch(200, OK_BODY),
    body: {model: "deepseek-flash"},
  });
  assert.strictEqual(res.ok, true);
});

test("200 whose body is not JSON: logged as error, then rethrown",
    async () => {
      const db = fakeDb();
      const badJson = async () => ({
        ok: true, status: 200,
        json: async () => {
          throw new SyntaxError("Unexpected token <");
        },
        text: async () => "<html>",
      });
      await assert.rejects(log.deepSeekChat(db, {
        apiKey: "k", log: LOG, fetchImpl: badJson,
        body: {model: "deepseek-flash"},
      }), /Unexpected token/);
      const row = db.rows[0].row;
      assert.strictEqual(row.error, true);
      assert.strictEqual(row.http_status, 200);
      assert.strictEqual(row.model_returned, null);
    });

test("timeoutMs aborts a hung request; logged as error, then rethrown",
    async () => {
      const db = fakeDb();
      const hang = (url, init) => new Promise((_, reject) => {
        init.signal.addEventListener("abort",
            () => reject(init.signal.reason));
      });
      const started = Date.now();
      await assert.rejects(log.deepSeekChat(db, {
        apiKey: "k", log: LOG, fetchImpl: hang, timeoutMs: 50,
        body: {model: "deepseek-flash"},
      }), (e) => e.name === "TimeoutError");
      assert.ok(Date.now() - started < 1000, "timeout not applied");
      const row = db.rows[0].row;
      assert.strictEqual(row.error, true);
      assert.strictEqual(row.http_status, null);
    });

test("a hung log write is abandoned after logTimeoutMs", async () => {
  const db = {collection: () => ({add: () => new Promise(() => {})})};
  const started = Date.now();
  const res = await log.deepSeekChat(db, {
    apiKey: "k", log: LOG, fetchImpl: fakeFetch(200, OK_BODY),
    logTimeoutMs: 50, body: {model: "deepseek-flash"},
  });
  assert.strictEqual(res.ok, true);
  assert.ok(Date.now() - started < 1000, "log write held up the reply");
  assert.strictEqual(log.LOG_WRITE_TIMEOUT_MS, 2000);
});

test("agent_id outside the three agents is stored as null", async () => {
  for (const agentId of ["siu_yan", "ah_jan_ah_bak", "tung_tung"]) {
    const db = fakeDb();
    await log.deepSeekChat(db, {
      apiKey: "k", log: {callType: "chat", agentId, uid: "u1"},
      fetchImpl: fakeFetch(200, OK_BODY), body: {model: "deepseek-flash"},
    });
    assert.strictEqual(db.rows[0].row.agent_id, agentId);
  }
  for (const agentId of ["evil<script>", "", undefined, 42]) {
    const db = fakeDb();
    await log.deepSeekChat(db, {
      apiKey: "k", log: {callType: "chat", agentId, uid: "u1"},
      fetchImpl: fakeFetch(200, OK_BODY), body: {model: "deepseek-flash"},
    });
    assert.strictEqual(db.rows[0].row.agent_id, null, String(agentId));
  }
});

(async () => {
  // AbortSignal.timeout's timer does not hold the event loop open; this
  // does, so the timeout test can finish.
  const keepAlive = setInterval(() => {}, 1000);
  let failed = 0;
  const origError = console.error;
  for (const t of tests) {
    console.error = () => {};
    try {
      await t.fn();
      console.error = origError;
      console.log(`ok   ${t.name}`);
    } catch (err) {
      console.error = origError;
      failed++;
      console.log(`FAIL ${t.name}\n     ${err.message}`);
    }
  }
  clearInterval(keepAlive);
  console.log(`\n${tests.length - failed}/${tests.length} passed`);
  if (failed) process.exit(1);
})();

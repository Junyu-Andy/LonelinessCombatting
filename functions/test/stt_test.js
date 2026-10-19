/**
 * T27 — server STT (SPEC:C18): request fields, no data-logging parameter,
 * one region only, retry once, failure categories, no audio / text in logs.
 *
 * Run:  cd functions && node test/stt_test.js
 *
 * Pure unit test: `recognize` is a fake, so no network, key or emulator.
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const stt = require("../stt");

const root = path.join(__dirname, "..");
const read = (f) => fs.readFileSync(path.join(root, f), "utf8");

// ---------------------------------------------------------------------------
// 1. The request object: exactly these fields, nothing else.
// ---------------------------------------------------------------------------
const content = Buffer.from("RIFF....WAVEfmt ", "utf8");
const req = stt.buildRecognizeRequest({projectId: "p-test", content});

assert.deepStrictEqual(Object.keys(req).sort(),
    ["config", "content", "recognizer"]);
assert.strictEqual(req.recognizer,
    "projects/p-test/locations/asia-southeast1/recognizers/_");
assert.deepStrictEqual(Object.keys(req.config).sort(),
    ["autoDecodingConfig", "features", "languageCodes", "model"]);
assert.deepStrictEqual(req.config.autoDecodingConfig, {});
assert.deepStrictEqual(req.config.languageCodes, ["yue-Hant-HK"]);
assert.strictEqual(req.config.model, "chirp_2");
assert.deepStrictEqual(req.config.features,
    {enableAutomaticPunctuation: true});
assert.ok(Buffer.isBuffer(req.content) && req.content.equals(content));
console.log("ok  request has exactly the documented fields");

// No data-logging style field anywhere in the request (deep scan).
const forbidden = new RegExp(["log", "logging", "datalogging",
  "enabledatalogging", "adaptation", "opt", "consent", "retain", "retention",
  "store", "storage", "output", "gcs"].join("|"), "i");
function scanKeys(obj, trail) {
  if (!obj || typeof obj !== "object" || Buffer.isBuffer(obj)) return;
  Object.keys(obj).forEach((k) => {
    const here = trail.concat(k).join(".");
    assert.ok(!forbidden.test(k),
        `request field "${here}" looks like a data-logging / storage option`);
    scanKeys(obj[k], trail.concat(k));
  });
}
scanKeys(req, []);
console.log("ok  no data-logging / storage field in the request");

// ---------------------------------------------------------------------------
// 2. One region, one model; the old global/long tier is gone and nothing in
//    the server reads a region or model from config or from the request.
// ---------------------------------------------------------------------------
const index = read("index.js");
const sttSrc = read("stt.js");
assert.strictEqual(stt.STT_LOCATION, "asia-southeast1");
assert.strictEqual(stt.STT_MODEL, "chirp_2");
assert.strictEqual(stt.STT_API_ENDPOINT,
    "asia-southeast1-speech.googleapis.com");
assert.ok(!index.includes("STT_TIERS"), "index.js still has STT_TIERS");
assert.ok(!/location:\s*"global"/.test(index) &&
  !/location:\s*"global"/.test(sttSrc), "a global tier is still defined");
assert.ok(!/model:\s*"long"/.test(index) && !/model:\s*"long"/.test(sttSrc),
    "the long model is still referenced");
assert.ok(!/payload\.model|payload\.languageCode|forcedModel/.test(index),
    "transcribeAudio must not take model / language from the request");
const code = (src) => src.split("\n").filter((l) => !/^\s*(\/\/|\*)/.test(l))
    .join("\n");
assert.ok(!/enableDataLogging|dataLogging/i.test(code(sttSrc)),
    "stt.js sets a data-logging field");
assert.ok(!/enableDataLogging|dataLogging/i.test(code(index)),
    "index.js sets a data-logging field");
console.log("ok  asia-southeast1 / chirp_2 only; no global tier; no override");

// ---------------------------------------------------------------------------
// 3. Nothing logs audio or transcript.  Every console.* call in stt.js and
//    in the transcribeAudio block of index.js is checked.
// ---------------------------------------------------------------------------
assert.ok(!/console\./.test(sttSrc), "stt.js should not log at all");
const block = index.slice(index.indexOf("exports.transcribeAudio"),
    index.indexOf("exports.", index.indexOf("exports.transcribeAudio") + 10));
const logs = block.split("\n").filter((l) => /console\./.test(l));
assert.ok(logs.length >= 1, "expected the ops warn line");
logs.forEach((l) => {
  assert.ok(!/transcript|content|audio|message|payload/.test(l),
      `log line mentions audio/text: ${l.trim()}`);
});
// Usage row never carries audio or text either.
const usageBlock = block.slice(block.indexOf("stt_usage"),
    block.indexOf("}, row));"));
assert.ok(!/transcript|content:|audioBase64/.test(usageBlock),
    "stt_usage row must not carry audio or text");
console.log("ok  no console.* or usage row with audio / transcript");

// ---------------------------------------------------------------------------
// 3b. 10/19: no spaces between Chinese characters; Latin / digits keep theirs.
// ---------------------------------------------------------------------------
assert.strictEqual(stt.tidyCantonese("我 今日 去 咗 飲茶 ， 好 開心 。"),
    "我今日去咗飲茶，好開心。");
assert.strictEqual(stt.tidyCantonese("我 book 咗 3 點 去 睇 醫生"),
    "我 book 咗 3 點去睇醫生");
assert.strictEqual(stt.tidyCantonese("OK 冇 問題"), "OK 冇問題");
assert.strictEqual(stt.readResponse({results: [
  {alternatives: [{transcript: "今日 天氣 ", confidence: 0.8}]},
  {alternatives: [{transcript: " 幾 好"}]},
]}).transcript, "今日天氣幾好");
console.log("ok  Chinese spaces removed; Latin / digit spacing kept");

// ---------------------------------------------------------------------------
// 4. Retry once on transient failure; categories.
// ---------------------------------------------------------------------------
const okResp = {
  results: [{alternatives: [{transcript: "你好", confidence: 0.9}]}],
};
const grpc = (codeNum, message) => {
  const e = new Error(message || "x");
  e.code = codeNum;
  return e;
};
const fake = (plan) => {
  const calls = [];
  const fn = async (r) => {
    calls.push(r);
    const step = plan.shift();
    if (step instanceof Error) throw step;
    return step;
  };
  fn.calls = calls;
  return fn;
};

(async () => {
  // fails once (UNAVAILABLE) then succeeds → 2 attempts, transcript back.
  let f = fake([grpc(14, "unavailable"), okResp]);
  const out = await stt.transcribeWithRetry(f, req);
  assert.strictEqual(out.transcript, "你好");
  assert.strictEqual(out.confidence, 0.9);
  assert.strictEqual(out.attempts, 2);
  assert.strictEqual(f.calls.length, 2);
  assert.strictEqual(f.calls[0], f.calls[1], "same request object re-sent");
  console.log("ok  transient failure → retried once → success");

  // fails twice → one retry only, then categorised error.
  f = fake([grpc(4, "Deadline exceeded"), grpc(4, "Deadline exceeded"),
    okResp]);
  await assert.rejects(stt.transcribeWithRetry(f, req), (e) => {
    assert.ok(e instanceof stt.SttError);
    assert.strictEqual(e.category, "timeout");
    assert.strictEqual(e.attempts, 2);
    assert.strictEqual(e.grpcCode, "4");
    return true;
  });
  assert.strictEqual(f.calls.length, 2, "never a third attempt");
  console.log("ok  two failures → exactly two attempts → timeout");

  // server error (code 13 INTERNAL) twice → server_error.
  f = fake([grpc(13, "internal"), grpc(13, "internal")]);
  await assert.rejects(stt.transcribeWithRetry(f, req),
      (e) => e.category === "server_error" && e.attempts === 2);
  console.log("ok  internal ×2 → server_error");

  // Google says nothing was recognised → no_speech, no retry.
  f = fake([{results: []}, okResp]);
  await assert.rejects(stt.transcribeWithRetry(f, req),
      (e) => e.category === "no_speech" && e.attempts === 1);
  assert.strictEqual(f.calls.length, 1, "empty transcript is not retried");
  console.log("ok  empty result → no_speech, not retried");

  // Too long (INVALID_ARGUMENT about duration) → too_long, no retry.
  f = fake([grpc(3, "Audio duration exceeds the 60s limit"), okResp]);
  await assert.rejects(stt.transcribeWithRetry(f, req),
      (e) => e.category === "too_long" && e.attempts === 1);
  assert.strictEqual(f.calls.length, 1);
  console.log("ok  too long → too_long, not retried");

  // Error objects never carry audio or text.
  const err = new stt.SttError("timeout", 2, "4");
  assert.deepStrictEqual(Object.keys(err).sort(),
      ["attempts", "category", "grpcCode"]);
  assert.ok(!JSON.stringify(err).includes("你好"));

  // Category → callable code mapping is complete.
  Object.keys(stt.CATEGORIES).forEach((k) => {
    const c = stt.CATEGORIES[k];
    assert.ok(stt.HTTPS_CODE[c], `no HttpsError code for ${c}`);
  });
  assert.deepStrictEqual(Object.values(stt.CATEGORIES).sort(),
      ["no_speech", "server_error", "timeout", "too_long", "unavailable"]);

  // Size guard.
  assert.strictEqual(stt.sizeProblem(Buffer.alloc(10)), null);
  assert.strictEqual(stt.sizeProblem(Buffer.alloc(stt.MAX_AUDIO_BYTES + 1)),
      "too_long");
  console.log("ok  categories, codes and size guard");

  console.log("stt_test: all passed");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

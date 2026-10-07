/**
 * C18 Phase B flags (decision 0019) — webSearch and transcribeAudio refuse
 * to run unless `app_config/feature_flags` turns them on.
 *
 * Runs the real callable handlers against the Firestore emulator.  Brave
 * is a stub (global fetch is replaced); Google Speech is never reached
 * (the "on" case sends empty audio and stops at input validation).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/feature_flags_emulator_test.js"
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
process.env.SEARCH_API_KEY = "test-key";

let fetchCalls = [];
global.fetch = async (url) => {
  fetchCalls.push(String(url));
  return {
    ok: true,
    status: 200,
    json: async () => ({web: {results: [
      {title: "STUB", description: "stub snippet", url: "https://x.test"},
    ]}}),
  };
};

const fns = require("../index");
const flags = require("../feature_flags");
const admin = require("firebase-admin");
const db = admin.firestore();

const UID_A = "flags_a";
const UID_B = "flags_b";

async function setFlags(data) {
  const ref = db.doc(flags.FLAGS_DOC);
  if (data === null) {
    await ref.delete();
  } else {
    await ref.set(data);
  }
}

async function expectCode(promise, code) {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code, `expected ${code}, got ${err.code}`);
    return;
  }
  assert.fail(`expected ${code}, call succeeded`);
}

const search = (uid) => fns.webSearch.run({
  auth: {uid}, data: {query: "今日天氣點"},
});
const transcribe = (uid) => fns.transcribeAudio.run({
  auth: {uid}, data: {audioBase64: ""},
});

async function main() {
  await db.doc(`users/${UID_A}`).set({arm: "A"});
  await db.doc(`users/${UID_B}`).set({arm: "B"});

  // 1. No config document → both off; nothing is sent to Brave.
  await setFlags(null);
  fetchCalls = [];
  await expectCode(search(UID_A), "failed-precondition");
  await expectCode(transcribe(UID_A), "failed-precondition");
  await expectCode(transcribe(UID_B), "failed-precondition");
  assert.strictEqual(fetchCalls.length, 0, "no Brave request when off");
  assert.strictEqual(await flags.isFeatureEnabled(db, "webSearchEnabled"),
      false);
  console.log("ok  missing doc → webSearch / transcribeAudio refused");

  // 2. Fields present but not literally true → still off.
  await setFlags({webSearchEnabled: "true", voiceInputEnabled: 1});
  await expectCode(search(UID_A), "failed-precondition");
  await expectCode(transcribe(UID_A), "failed-precondition");
  assert.strictEqual(fetchCalls.length, 0);
  console.log("ok  non-boolean values count as off");

  // 3. Explicit false → off.
  await setFlags({webSearchEnabled: false, voiceInputEnabled: false});
  await expectCode(search(UID_A), "failed-precondition");
  await expectCode(transcribe(UID_A), "failed-precondition");
  assert.strictEqual(fetchCalls.length, 0);
  console.log("ok  false → refused");

  // 4. On → Hybrid search reaches Brave; rule arm is still refused by the
  //    arm guard and sends nothing.
  await setFlags({webSearchEnabled: true, voiceInputEnabled: true});
  const out = await search(UID_A);
  assert.strictEqual(out.unavailable, false);
  assert.strictEqual(fetchCalls.length, 1);
  assert.ok(fetchCalls[0].startsWith("https://api.search.brave.com/"));
  await expectCode(search(UID_B), "permission-denied");
  assert.strictEqual(fetchCalls.length, 1, "rule arm never reaches Brave");
  // Voice on: passes the flag gate and stops at input validation.
  await expectCode(transcribe(UID_A), "invalid-argument");
  console.log("ok  on → search runs for Hybrid only; transcribe passes gate");

  // 5. Turning it off again takes effect on the next call (no cache).
  await setFlags({webSearchEnabled: false, voiceInputEnabled: false});
  await expectCode(search(UID_A), "failed-precondition");
  await expectCode(transcribe(UID_A), "failed-precondition");
  assert.strictEqual(fetchCalls.length, 1);
  console.log("ok  switching off applies immediately");

  await setFlags(null);
  console.log("feature_flags_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});

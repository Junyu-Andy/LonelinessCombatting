/**
 * T17b — Phase A ADA day-7 flow (functions/ada.js, decision 0030) against
 * the Firestore emulator: push at the chosen hour, 24 h reminder,
 * overdue after day 9, server status + research ID, researcher page and
 * phone completion (phone_by_staff).  Synthetic users, fake FCM sender.
 *
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/ada_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const ada = require("../ada");
const djg = require("../djg_w2");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const silent = () => {};

const W0 = "2026-10-01";
function hk(day, hour) {
  const key = djg.addDays(W0, day - 1);
  return new Date(`${key}T${String(hour).padStart(2, "0")}:00:00+08:00`);
}
const FINAL_COPY = {push: "（測試）第 7 日問卷", reminder: "（測試）提醒"};
const ON = {adaEnabled: true, day7OpenEndedEnabled: true};
const STAFF = {uid: "staff1", token: {role: "blinded"}};
const UNBLINDED = {uid: "keran1", token: {role: "unblinded"}};

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

async function reset(cfg) {
  for (const p of ["users", "app_config", "ada_status", "research_id_map",
    "safety_events"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (cfg) await db.doc(ada.CONFIG_DOC).set(cfg);
}

async function seedUser(uid, data) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {createdAt: `${W0}T09:00:00.000`, arm: "A"}, data));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
}

// pa: chose 19:00 at visit 1; pd: no choice (default 10:00); pb: Phase B;
// pt: tester.
async function seedCohort() {
  await seedUser("pa", {cohort: "phase_a", displayName: "陳生"});
  await db.doc("users/pa/ada_responses/visit1").set({uid: "pa",
    timepoint: "visit1", status: "submitted", channel: "app",
    day7ReminderTime: "19:00"});
  await seedUser("pd", {cohort: "phase_a"});
  await seedUser("pb", {cohort: "phase_b", arm: "B"});
  await seedUser("pt", {cohort: "phase_a", isTester: true});
}

const statusOf = async (uid) =>
  ((await db.doc(`ada_status/${uid}`).get()).data() || {});
const tokensOf = (m) => m.sent.map((s) => s.token).sort();
const run = (m, now, copy) => ada.dispatchAdaDay7(db, m,
    {now, log: silent, copy: copy === undefined ? FINAL_COPY : copy});

async function submitBoth(uid, channel) {
  await db.doc(`users/${uid}/ada_responses/day7`).set({uid, timepoint: "day7",
    status: "submitted", channel: channel || "app"});
  await db.doc(`users/${uid}/day7_open_responses/day7`).set({uid,
    timepoint: "day7", status: "submitted", channel: channel || "app"});
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switches off: nothing happens", async () => {
  await reset(null);
  await seedCohort();
  const m = fakeMessaging();
  assert.deepStrictEqual(await run(m, hk(7, 19)), {enabled: false});
  assert.strictEqual(m.sent.length, 0);
});

test("placeholder copy: nothing is sent", async () => {
  await reset(ON);
  await seedCohort();
  const m = fakeMessaging();
  const counts = await run(m, hk(7, 20), null);
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual(counts.blocked_placeholder, 2);
  assert.strictEqual((await statusOf("pa")).day7PushSentAt, undefined);
});

test("day 7: push at the chosen hour (19:00) and the default (10:00)",
    async () => {
      await reset(ON);
      await seedCohort();
      let m = fakeMessaging();
      await run(m, hk(6, 19));
      assert.strictEqual(m.sent.length, 0, "day 6");
      m = fakeMessaging();
      await run(m, hk(7, 9));
      assert.strictEqual(m.sent.length, 0, "09:00");
      m = fakeMessaging();
      await run(m, hk(7, 10));
      assert.deepStrictEqual(tokensOf(m), ["tok-pd"], "10:00 default only");
      m = fakeMessaging();
      await run(m, hk(7, 18));
      assert.strictEqual(m.sent.length, 0, "18:00");
      m = fakeMessaging();
      await run(m, hk(7, 19));
      assert.deepStrictEqual(tokensOf(m), ["tok-pa"], "19:00 chosen");
      m = fakeMessaging();
      await run(m, hk(7, 21));
      assert.strictEqual(m.sent.length, 0, "only once");
      assert.strictEqual(m.sent.length, 0);
      assert.strictEqual((await statusOf("pb")).uid, undefined, "Phase B");
      assert.strictEqual((await statusOf("pt")).uid, undefined, "tester");
    });

test("24 h later: one reminder, not for a completed flow", async () => {
  // continues from the previous test's state
  await submitBoth("pd");
  let m = fakeMessaging();
  await run(m, hk(8, 18));
  assert.strictEqual(m.sent.length, 0, "pa not due before 18:55");
  m = fakeMessaging();
  await run(m, hk(8, 19));
  assert.deepStrictEqual(tokensOf(m), ["tok-pa"]);
  assert.strictEqual(m.sent[0].notification.body, FINAL_COPY.reminder);
  m = fakeMessaging();
  await run(m, hk(9, 20));
  assert.strictEqual(m.sent.length, 0, "only one reminder");
  assert.strictEqual((await statusOf("pd")).day7Status, "completed");
});

test("day 10: overdue once; day 9 still open", async () => {
  await db.doc("users/pa/ada_responses/day7").set({uid: "pa",
    timepoint: "day7", status: "submitted", channel: "app"});
  await run(fakeMessaging(), hk(9, 21));
  assert.strictEqual((await statusOf("pa")).day7Status, "in_progress");
  await run(fakeMessaging(), hk(10, 8));
  const s = await statusOf("pa");
  assert.strictEqual(s.day7Status, "overdue");
  assert.strictEqual(s.day7Partial, true);
  assert.ok(s.day7OverdueAt);
  await run(fakeMessaging(), hk(10, 9));
  const ev = await db.collection("users/pa/events")
      .where("name", "==", "ada_day7_overdue").get();
  assert.strictEqual(ev.size, 1);
  assert.strictEqual((await statusOf("pd")).day7Status, "completed");
});

test("config change: window to day 12 → day 10 not overdue", async () => {
  await reset(Object.assign({}, ON, {adaTimepoints: [
    {id: "visit1", form: "short", dayFrom: 1, dayTo: 1},
    {id: "day7", form: "full", dayFrom: 7, dayTo: 12},
  ]}));
  await seedCohort();
  await run(fakeMessaging(), hk(10, 8));
  assert.notStrictEqual((await statusOf("pa")).day7Status, "overdue");
  await run(fakeMessaging(), hk(13, 8));
  assert.strictEqual((await statusOf("pa")).day7Status, "overdue");
});

test("trigger: status + research ID copied, never created", async () => {
  await reset(ON);
  await seedCohort();
  await ada.refreshStatus(db, "pd", {now: hk(7, 12)});
  assert.strictEqual((await statusOf("pd")).researchId, null);
  assert.strictEqual((await db.doc("research_id_map/pd").get()).exists,
      false);
  await db.doc("research_id_map/pa").set({researchId: "P7K3QX2"});
  await submitBoth("pa");
  const out = await ada.refreshStatus(db, "pa", {now: hk(8, 12)});
  assert.strictEqual(out.researchId, "P7K3QX2");
  assert.strictEqual(out.day7Status, "completed");
  assert.strictEqual(out.day7Channel, "app");
  assert.strictEqual(out.visit1Status, "submitted");
  assert.strictEqual(out.day7ReminderTime, "19:00");
  // Response docs never carry the research ID (decision 0021).
  const d = (await db.doc("users/pa/ada_responses/day7").get()).data();
  assert.strictEqual(d.researchId, undefined);
  assert.strictEqual(await ada.refreshStatus(db, "pb", {}), null, "Phase B");
});

test("researcher page: four states; research ID for the unblinded role only",
    async () => {
      await reset(ON);
      await seedCohort();
      await db.doc("research_id_map/pa").set({researchId: "P7K3QX2"});
      await seedUser("p2", {cohort: "phase_a",
        createdAt: "2026-10-03T09:00:00.000"});
      await db.doc("users/p2/ada_responses/day7").set({uid: "p2",
        timepoint: "day7", status: "in_progress", channel: "app"});
      await seedUser("p3", {cohort: "phase_a",
        createdAt: "2026-10-05T09:00:00.000"});
      await submitBoth("pd");
      await assert.rejects(ada.staffDay7Status(db, {uid: "x", token: {}}),
          /researcher role/);
      const now = hk(10, 12); // pa day 10, p2 day 8, p3 day 6
      const r = await ada.staffDay7Status(db, STAFF, {now});
      const by = Object.fromEntries(r.rows.map((x) => [x.uid, x]));
      assert.strictEqual(by.pa.status, "overdue");
      assert.strictEqual(by.pd.status, "completed");
      assert.strictEqual(by.p2.status, "in_progress");
      assert.strictEqual(by.p3.status, "not_started");
      assert.strictEqual(by.pb, undefined, "no Phase B rows");
      assert.strictEqual(by.pa.researchId, null, "blinded role: no ID");
      assert.strictEqual(by.pa.label, "陳生 · pa");
      const r2 = await ada.staffDay7Status(db, UNBLINDED, {now});
      assert.strictEqual(r2.rows.find((x) => x.uid === "pa").researchId,
          "P7K3QX2");
    });

test("phone completion: channel phone_by_staff, safety event, frozen",
    async () => {
      await reset(ON);
      await seedCohort();
      const call = (auth, collection, data) => ada.staffSave(db, auth,
          {uid: "pa", collection, docId: "day7", data}, {now: hk(10, 15)});
      await assert.rejects(call({uid: "pa", token: {}}, "ada_responses",
          {status: "in_progress"}), /researcher role/);
      await assert.rejects(ada.staffSave(db, STAFF, {uid: "pa",
        collection: "agent_diff", docId: "day7", data: {status: "x"}}),
      /collection/);
      await assert.rejects(ada.staffSave(db, STAFF, {uid: "pb",
        collection: "ada_responses", docId: "day7",
        data: {status: "in_progress"}}), /Phase A/);
      const r1 = await call(STAFF, "ada_responses", {status: "in_progress",
        formVersion: "full", traits: {warm: {siu_yan: 5}},
        channel: "app", uid: "evil", staffUid: "evil", researchId: "X",
        startedAt: "2026-10-10T07:00:00.000Z"});
      assert.strictEqual(r1.safetyEscalation, false);
      let d = (await db.doc("users/pa/ada_responses/day7").get()).data();
      assert.strictEqual(d.channel, "phone_by_staff");
      assert.strictEqual(d.staffUid, "staff1");
      assert.strictEqual(d.uid, "pa");
      assert.strictEqual(d.researchId, undefined);
      assert.strictEqual(d.traits.warm.siu_yan, 5);
      const r2 = await call(STAFF, "ada_responses", {status: "submitted",
        freeText: "用完一個禮拜，我仲係好想了結自己。"});
      assert.strictEqual(r2.safetyEscalation, true);
      d = (await db.doc("users/pa/ada_responses/day7").get()).data();
      assert.strictEqual(d.status, "submitted");
      assert.ok(d.submittedAt);
      const ev = await db.collection("safety_events")
          .where("uid", "==", "pa").get();
      assert.strictEqual(ev.size, 1);
      const e = ev.docs[0].data();
      assert.strictEqual(e.source, "form");
      assert.strictEqual(e.inputPoint, "ada_free_text");
      assert.strictEqual(e.channel, "phone_by_staff");
      assert.strictEqual(e.tier, "acute");
      assert.strictEqual(e.text, undefined, "no text stored");
      await assert.rejects(call(STAFF, "ada_responses",
          {status: "in_progress"}), /already submitted/);
      await call(STAFF, "day7_open_responses", {status: "submitted",
        answers: {q1: {text: "好", status: "answered"}}});
      const s = await statusOf("pa");
      assert.strictEqual(s.day7Status, "completed");
      assert.strictEqual(s.day7Channel, "phone_by_staff");
      const loaded = await ada.staffLoad(db, STAFF,
          {uid: "pa", collection: "ada_responses", docId: "day7"});
      assert.strictEqual(loaded.doc.channel, "phone_by_staff");
      assert.strictEqual(typeof loaded.doc.submittedAt, "string");
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`not ok - ${t.name}\n${err.stack}`);
    }
  }
  if (failed) {
    console.error(`${failed} ada emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} ada emulator tests passed`);
  process.exit(0);
})();

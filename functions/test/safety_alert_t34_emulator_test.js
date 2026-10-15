/**
 * T34 — safety alert e-mail, against the Firestore emulator.
 *
 *   dev-tasks-1010b §三 T34 §7:
 *   1. e-mail fields complete; no arm / wording / matched term; the two
 *      arms' e-mails have the same field set;
 *   2. recipients from meta/alert_config; a `blinded` address is dropped
 *      and logged; a tester account gets a row but no e-mail;
 *   3. acknowledged within the window → not escalated; not acknowledged →
 *      escalated once, only once, same fields;
 *   4. 確認處理 only for `unblinded`; who and when recorded;
 *   5. PHQ-9 item 9 = 0 → nothing; ≠ 0 → one event + alert whatever the
 *      level, source correct;
 *   6. the blinded export carries `sourceGroup` and counts per source.
 *   Plus: switch off (no meta/alert_config) = the T19 alert, unchanged.
 *
 * No real mail: pi_alert.setMailerForTests captures every message; Auth is
 * replaced by pi_alert.setAuthForTests.  Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/safety_alert_t34_emulator_test.js"
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
process.env.SMTP_HOST = "smtp.test.invalid";
process.env.SMTP_USER = "sender@test.invalid";
process.env.SMTP_PASS = "x";
process.env.PI_EMAIL = "legacy-pi@test.invalid";

const fns = require("../index");
const piAlert = require("../pi_alert");
const qs = require("../questionnaire_safety");
const blinding = require("../blinding");
const admin = require("firebase-admin");
const db = admin.firestore();

const PRIMARY = "junyu@test.invalid";
const BACKUP = "calvin@test.invalid";
const ASSESSOR = "assessor@test.invalid";

// Captured mail.
let sent = [];
piAlert.setMailerForTests(async (msg) => {
  sent.push(msg);
});
// Auth: the primary has an unblinded App account, the assessor a blinded
// one, the backup none.
piAlert.setAuthForTests({
  getUserByEmail: async (email) => {
    if (email === PRIMARY) return {customClaims: {role: "unblinded"}};
    if (email === ASSESSOR) return {customClaims: {role: "blinded"}};
    const e = new Error("not found");
    e.code = "auth/user-not-found";
    throw e;
  },
});

const UID_A = "t34_arm_a";
const UID_B = "t34_arm_b";
const UID_T = "t34_tester";
const UID_Q = "t34_questionnaire";

async function clear(name) {
  const docs = await db.collection(name).listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
}

async function reset(alertCfg) {
  for (const n of ["safety_events", "safety_event_dedup", "pi_alerts",
    "alert_audit_log", "research_id_map", "research_ids", "users"]) {
    await clear(n);
  }
  await db.doc(`users/${UID_A}`).set({arm: "A", cohort: "phase_b",
    armAssignmentMode: "randomise", w0Date: "2026-10-19",
    createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${UID_B}`).set({arm: "B", cohort: "phase_b",
    armAssignmentMode: "randomise", w0Date: "2026-10-19",
    createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`users/${UID_T}`).set({arm: "A", isTester: true,
    w0Date: "2026-10-19"});
  await db.doc(`users/${UID_Q}`).set({arm: "B", cohort: "pilot",
    armAssignmentMode: "pilot_designated"});
  await db.doc(`research_id_map/${UID_A}`).set({researchId: "PB-A01"});
  await db.doc(`research_id_map/${UID_B}`).set({researchId: "PB-B02"});
  await db.doc(`research_id_map/${UID_T}`).set({researchId: "PB-T99"});
  await db.doc(`research_id_map/${UID_Q}`).set({researchId: "PILOT-03"});
  if (alertCfg) await db.doc("meta/alert_config").set(alertCfg);
  else await db.doc("meta/alert_config").delete();
  sent = [];
}

const ON = {enabled: true, primaryEmail: PRIMARY, backupEmail: BACKUP,
  escalateAfterHours: 12};

async function fire(fields) {
  const ref = await db.collection("safety_events").add(Object.assign({
    uid: UID_A, source: "user_input", textHash: "h", level: "acute",
    tier: "acute", category: "ideation", lexiconVersion: "v5-2026-09",
    crisisPageShown: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, fields));
  const snap = await ref.get();
  await fns.onSafetyEventCreated.run({data: snap, params: {eventId: ref.id}});
  return {ref, data: (await ref.get()).data()};
}

const alerts = async () => (await db.collection("pi_alerts").get()).docs;
const audit = async (type) => (await db.collection("alert_audit_log")
    .where("type", "==", type).get()).docs.map((d) => d.data());

const FIELD_LABELS = ["研究编号 Research ID", "研究期 Study period",
  "陪伴者 Companion", "来源 Source", "级别和类别 Level and category",
  "词库版本 Lexicon version", "LoRA 是否参与判定 Classifier involved",
  "研究第几天 Study day", "是否显示危机页 Crisis page shown",
  "事件编号 Event ID", "告警编号 Alert ID", "时间（香港） Time (HKT)"];
const labelsOf = (text) => text.split("\n")
    .map((l) => l.split(": ")[0])
    .filter((l) => FIELD_LABELS.indexOf(l) >= 0);

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off (no meta/alert_config): the T19 alert and e-mail, unchanged",
    async () => {
      await reset(null);
      const {ref} = await fire({turnId: "off1", agentId: "siu_yan",
        source: "ai_output_scan", matchedTerm: "自殺"});
      const rows = await alerts();
      assert.strictEqual(rows.length, 1);
      const a = rows[0].data();
      assert.strictEqual(a.alertVersion, 2);
      assert.deepStrictEqual(Object.keys(a).sort(), ["alertVersion",
        "createdAt", "dedupKey", "eventPath", "isTester", "level",
        "researchId", "uid"]);
      assert.strictEqual(a.eventPath, ref.path);
      assert.strictEqual(sent.length, 1);
      assert.strictEqual(sent[0].to, "legacy-pi@test.invalid");
      assert.strictEqual(sent[0].subject,
          "[LonelinessCombatting] Acute distress alert");
      assert.ok(!sent[0].text.includes("siu_yan"));
      assert.strictEqual((await audit("email_sent")).length, 0,
          "no audit log while off");
    });

test("switch off: a moderate event sends nothing (as today)", async () => {
  await reset(null);
  await fire({turnId: "off2", level: "moderate", tier: "moderate_interrupt"});
  assert.strictEqual((await alerts()).length, 0);
  assert.strictEqual(sent.length, 0);
});

test("switch on: both arms → v3 row, e-mail to the primary, same fields",
    async () => {
      await reset(ON);
      const a = await fire({uid: UID_A, turnId: "on-a",
        source: "ai_output_scan", inputPoint: "chat_reflective",
        agentId: "siu_yan", matchedTerm: "自殺", detector: "both",
        classifierStatus: "ok"});
      const b = await fire({uid: UID_B, turnId: "on-b", source: "rule_turn",
        inputPoint: "check_in_note", agentId: "tung_tung", matchedTerm: "想死"});
      const rows = (await alerts()).map((d) => Object.assign({id: d.id},
          d.data()));
      assert.strictEqual(rows.length, 2);
      for (const r of rows) {
        assert.strictEqual(r.alertVersion, 3);
        assert.ok(r.emailSentAt, "emailSentAt set");
        assert.deepStrictEqual(r.emailSentTo, [PRIMARY]);
        assert.strictEqual(r.escalationPending, true);
        assert.strictEqual(r.acknowledgedAt, null);
        assert.strictEqual(r.studyPeriod, "B");
        assert.strictEqual(typeof r.studyDay, "number");
        assert.strictEqual(r.crisisPageShown, true);
        for (const k of ["matchedTerm", "textHash", "inputPoint", "arm"]) {
          assert.strictEqual(r[k], undefined, k);
        }
      }
      assert.deepStrictEqual(Object.keys(rows[0]).sort(),
          Object.keys(rows[1]).sort(), "same row fields for both arms");
      assert.strictEqual(sent.length, 2);
      for (const m of sent) {
        assert.strictEqual(m.to, PRIMARY);
        assert.deepStrictEqual(labelsOf(m.text), FIELD_LABELS);
        for (const bad of ["自殺", "想死", UID_A, UID_B, "chat_reflective",
          "check_in_note", "Arm A", "Arm B", "Hybrid"]) {
          assert.ok(!m.text.includes(bad) && !m.subject.includes(bad), bad);
        }
      }
      const byEvent = {};
      for (const m of sent) byEvent[m.text.match(/Event ID: (\S+)/)[1]] = m;
      assert.ok(byEvent[a.ref.path].text.includes(
          "来源 Source: AI 回复扫描 AI reply scan"));
      assert.ok(byEvent[a.ref.path].text.includes(
          "LoRA 是否参与判定 Classifier involved: 是 Yes"));
      assert.ok(byEvent[b.ref.path].text.includes(
          "来源 Source: 老人输入 Participant input"));
      assert.ok(byEvent[b.ref.path].text.includes(
          "陪伴者 Companion: 通通 Tung Tung (tung_tung)"));
      assert.ok(byEvent[b.ref.path].text.includes(
          "研究编号 Research ID: PB-B02"));
      assert.strictEqual((await audit("email_sent")).length, 2);
      // The primary has an account; the backup is not looked up yet.
      assert.strictEqual((await audit("recipient_dropped")).length, 0);
    });

test("switch on: moderate events still send nothing", async () => {
  await reset(ON);
  await fire({turnId: "on-mod", level: "moderate",
    tier: "moderate_interrupt", crisisPageShown: false});
  assert.strictEqual((await alerts()).length, 0);
  assert.strictEqual(sent.length, 0);
});

test("one turn, input then AI output: one alert, one e-mail", async () => {
  await reset(ON);
  await fire({turnId: "dup", source: "user_input", textHash: "in"});
  await fire({turnId: "dup", source: "ai_output_scan", textHash: "out"});
  assert.strictEqual((await alerts()).length, 1);
  assert.strictEqual(sent.length, 1);
});

test("tester account: row written and tagged, no e-mail, no escalation",
    async () => {
      await reset(ON);
      await fire({uid: UID_T, turnId: "tester1"});
      const rows = await alerts();
      assert.strictEqual(rows.length, 1);
      assert.strictEqual(rows[0].data().isTester, true);
      assert.strictEqual(rows[0].data().escalationPending, false);
      assert.strictEqual(sent.length, 0);
      assert.strictEqual((await audit("tester_no_email")).length, 1);
      const out = await piAlert.escalateDue(db, {
        now: new Date(Date.now() + 48 * 3600 * 1000), smtp: smtp(),
        serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
      });
      assert.strictEqual(out.due, 0);
    });

test("a blinded address in the list is dropped and logged", async () => {
  await reset(Object.assign({}, ON, {primaryEmail: ASSESSOR}));
  await fire({turnId: "blinded1"});
  assert.strictEqual(sent.length, 0, "nobody left to send to");
  const dropped = await audit("recipient_dropped");
  assert.strictEqual(dropped.length, 1);
  assert.strictEqual(dropped[0].email, ASSESSOR);
  assert.strictEqual(dropped[0].reason, "blinded_role");
  assert.strictEqual((await audit("no_recipients")).length, 1);
  const row = (await alerts())[0].data();
  assert.strictEqual(row.emailSentAt, null);
  // 10/14 fix: nobody could be mailed, so the row is queued for the backup
  // at once instead of sitting in Firestore only.
  assert.strictEqual(row.escalationPending, true);
  assert.strictEqual(row.primaryFailedReason, "no_recipients");
  assert.ok(row.primaryFailedAt);
  // The next sweep sends it to the backup without waiting 12 h.
  const out = await piAlert.escalateDue(db, {
    now: new Date(), smtp: smtp(),
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
  assert.strictEqual(out.due, 1);
  assert.strictEqual(out.escalated, 1);
  assert.strictEqual(sent.length, 1);
  assert.deepStrictEqual([].concat(sent[0].to), [ON.backupEmail]);
});

test("no primary in the config: the PI_EMAIL secret is used and logged",
    async () => {
      await reset({enabled: true, backupEmail: BACKUP});
      await fire({turnId: "nopri"});
      assert.strictEqual(sent.length, 1);
      assert.strictEqual(sent[0].to, "legacy-pi@test.invalid");
      assert.strictEqual(
          (await audit("primary_missing_fallback_secret")).length, 1);
    });

function smtp() {
  return {host: "h", user: "sender@test.invalid", pass: "p"};
}

const deps = (now) => ({
  now, smtp: smtp(),
  serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
});

async function backdate(alertId, hoursAgo) {
  await db.doc(`pi_alerts/${alertId}`).update({
    emailSentAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - hoursAgo * 3600 * 1000)),
  });
}

test("escalation: not due within 12 h; due → backup once, only once, " +
  "same fields", async () => {
  await reset(ON);
  await fire({uid: UID_B, turnId: "esc1", source: "rule_turn",
    agentId: "tung_tung"});
  const id = (await alerts())[0].id;
  const primaryMail = sent[0];
  sent = [];

  await backdate(id, 11);
  let out = await piAlert.escalateDue(db, deps(new Date()));
  assert.strictEqual(out.due, 0);
  assert.strictEqual(sent.length, 0, "11 h: not yet");

  await backdate(id, 13);
  out = await piAlert.escalateDue(db, deps(new Date()));
  assert.strictEqual(out.due, 1);
  assert.strictEqual(out.escalated, 1);
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].to, BACKUP);
  assert.ok(sent[0].subject.startsWith("【转后备 Escalated】"));
  assert.ok(sent[0].text.includes("【转后备】"));
  assert.deepStrictEqual(labelsOf(sent[0].text), labelsOf(primaryMail.text));
  const fieldLines = (t) => t.split("\n").filter((l) =>
    FIELD_LABELS.indexOf(l.split(": ")[0]) >= 0 &&
    !l.startsWith("时间（香港）"));
  assert.deepStrictEqual(fieldLines(sent[0].text),
      fieldLines(primaryMail.text), "same field values");
  const row = (await db.doc(`pi_alerts/${id}`).get()).data();
  assert.ok(row.escalatedAt);
  assert.deepStrictEqual(row.escalatedTo, [BACKUP]);
  assert.strictEqual(row.escalationPending, false);
  assert.strictEqual((await audit("escalated")).length, 1);

  // Second run: nothing more.
  out = await piAlert.escalateDue(db, deps(new Date()));
  assert.strictEqual(out.due, 0);
  assert.strictEqual(sent.length, 1, "escalated once only");
});

test("escalation: configurable hours; disabled switch does nothing",
    async () => {
      await reset(Object.assign({}, ON, {escalateAfterHours: 2}));
      await fire({turnId: "esc2"});
      const id = (await alerts())[0].id;
      sent = [];
      await backdate(id, 3);
      const out = await piAlert.escalateDue(db, deps(new Date()));
      assert.strictEqual(out.escalated, 1);
      // Switch off afterwards: the scheduler is inert.
      await reset({enabled: false, primaryEmail: PRIMARY, backupEmail: BACKUP});
      const off = await piAlert.escalateDue(db, deps(new Date()));
      assert.strictEqual(off.skipped, "disabled");
    });

test("1014e §2.4: no backup recipient → escalation does nothing: rows stay " +
    "pending, a failed primary keeps its flag, no claim, no audit row",
async () => {
  await reset({enabled: true, primaryEmail: PRIMARY});
  await fire({turnId: "nobk1"});
  const id = (await alerts())[0].id;
  await backdate(id, 13);
  // A second alert whose primary send failed (SMTP error path).
  await fire({turnId: "nobk2"});
  const id2 = (await alerts()).map((d) => d.id).find((x) => x !== id);
  await db.doc(`pi_alerts/${id2}`).update(
      piAlert.primaryFailedPatch(new Date(), "email_failed"));
  sent = [];
  const before = (await db.collection("alert_audit_log").get()).size;
  const out = await piAlert.escalateDue(db, deps(new Date()));
  assert.strictEqual(out.skipped, "no_backup_email");
  assert.strictEqual(out.due, 0);
  assert.strictEqual(sent.length, 0);
  const r1 = (await db.doc(`pi_alerts/${id}`).get()).data();
  assert.strictEqual(r1.escalationPending, true, "not claimed");
  assert.strictEqual(r1.escalatedAt, null);
  const r2 = (await db.doc(`pi_alerts/${id2}`).get()).data();
  assert.strictEqual(r2.escalationPending, true);
  assert.ok(r2.primaryFailedAt, "the dashboard flag stays");
  assert.strictEqual(r2.primaryFailedReason, "email_failed");
  assert.strictEqual((await db.collection("alert_audit_log").get()).size,
      before, "no audit row every sweep");
  // Filling backupEmail turns escalation back on.
  await db.doc("meta/alert_config").update({backupEmail: BACKUP});
  const on = await piAlert.escalateDue(db, deps(new Date()));
  assert.strictEqual(on.skipped, null);
  assert.strictEqual(on.due, 2);
  assert.strictEqual(on.escalated, 2);
});

test("escalation: a blinded backup is dropped and logged, nothing sent",
    async () => {
      await reset(Object.assign({}, ON, {backupEmail: ASSESSOR}));
      await fire({turnId: "esc3"});
      const id = (await alerts())[0].id;
      sent = [];
      await backdate(id, 13);
      const out = await piAlert.escalateDue(db, deps(new Date()));
      assert.strictEqual(out.due, 1);
      assert.strictEqual(out.noBackup, 1);
      assert.strictEqual(sent.length, 0);
      const dropped = (await audit("recipient_dropped"))
          .filter((d) => d.stage === "escalation");
      assert.strictEqual(dropped.length, 1);
      assert.strictEqual(dropped[0].email, ASSESSOR);
      const row = (await db.doc(`pi_alerts/${id}`).get()).data();
      assert.strictEqual(row.escalationSkipped, "backup_dropped");
      assert.strictEqual(row.escalationPending, false, "claimed once");
    });

const ackDeps = () => ({now: new Date(),
  serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp()});

test("確認處理: unblinded only; who and when recorded; acked never escalates",
    async () => {
      await reset(ON);
      await fire({turnId: "ack1"});
      const id = (await alerts())[0].id;
      sent = [];

      await assert.rejects(piAlert.acknowledge(db, {alertId: id}, null,
          ackDeps()), (e) => e.ackCode === "unauthenticated");
      await assert.rejects(piAlert.acknowledge(db, {alertId: id},
          {uid: "p1", token: {}}, ackDeps()),
      (e) => e.ackCode === "permission-denied");
      await assert.rejects(piAlert.acknowledge(db, {alertId: id},
          {uid: "as1", token: {role: "blinded"}}, ackDeps()),
      (e) => e.ackCode === "permission-denied");
      await assert.rejects(piAlert.acknowledge(db, {alertId: id},
          {uid: "as1", token: {role: "pi"}}, ackDeps()),
      (e) => e.ackCode === "permission-denied");
      await assert.rejects(piAlert.acknowledge(db, {alertId: "nope"},
          {uid: "ju", token: {role: "unblinded"}}, ackDeps()),
      (e) => e.ackCode === "not-found");
      await assert.rejects(piAlert.acknowledge(db, {},
          {uid: "ju", token: {role: "unblinded"}}, ackDeps()),
      (e) => e.ackCode === "invalid-argument");
      assert.strictEqual((await db.doc(`pi_alerts/${id}`).get()).data()
          .acknowledgedAt, null, "nothing recorded by the refused calls");

      const r = await piAlert.acknowledge(db, {alertId: id},
          {uid: "junyu-uid", token: {role: "unblinded", email: PRIMARY}},
          ackDeps());
      assert.strictEqual(r.ok, true);
      assert.strictEqual(r.alreadyAcknowledged, false);
      const row = (await db.doc(`pi_alerts/${id}`).get()).data();
      assert.ok(row.acknowledgedAt);
      assert.strictEqual(row.acknowledgedBy, "junyu-uid");
      assert.strictEqual(row.acknowledgedByEmail, PRIMARY);
      assert.strictEqual(row.escalationPending, false);
      const log = await audit("acknowledged");
      assert.strictEqual(log.length, 1);
      assert.strictEqual(log[0].by, "junyu-uid");
      assert.strictEqual(log[0].alertId, id);

      // A second acknowledgement keeps the first.
      const again = await piAlert.acknowledge(db, {alertId: id},
          {uid: "other", token: {role: "unblinded"}}, ackDeps());
      assert.strictEqual(again.alreadyAcknowledged, true);
      assert.strictEqual(again.acknowledgedBy, "junyu-uid");
      assert.strictEqual((await audit("acknowledged")).length, 1);

      // Even 13 h later, an acknowledged alert is not escalated.
      await backdate(id, 13);
      const out = await piAlert.escalateDue(db, deps(new Date()));
      assert.strictEqual(out.due, 0);
      assert.strictEqual(sent.length, 0);
    });

test("acknowledgeAlert callable maps the role check to HttpsError",
    async () => {
      await reset(ON);
      await fire({turnId: "ack2"});
      const id = (await alerts())[0].id;
      await assert.rejects(fns.acknowledgeAlert.run({data: {alertId: id},
        auth: {uid: "b", token: {role: "blinded"}}}),
      (e) => e.code === "functions/permission-denied" ||
        e.code === "permission-denied");
      const ok = await fns.acknowledgeAlert.run({data: {alertId: id},
        auth: {uid: "u", token: {role: "unblinded"}}});
      assert.strictEqual(ok.ok, true);
    });

test("questionnaire entry: PHQ-9 item 9 = 0 → nothing; ≠ 0 → event + alert " +
  "whatever the level, source assessor_entry", async () => {
  await reset(ON);
  const none = await qs.recordQuestionnaireSafetyEvent(db, {uid: UID_Q,
    source: "assessor_entry", instrument: "PHQ-9", item: 9, rawValue: 0,
    enteredBy: "assessor-uid", researchId: "PILOT-03"});
  assert.strictEqual(none, null);
  assert.strictEqual((await db.collection("safety_events").get()).size, 0);

  const made = await qs.recordQuestionnaireSafetyEvent(db, {uid: UID_Q,
    source: "assessor_entry", instrument: "PHQ-9", item: 9, rawValue: 1,
    enteredBy: "assessor-uid", researchId: "PILOT-03",
    level: "moderate_review"});
  assert.ok(made && made.id);
  const ref = db.doc(made.path);
  const ev = (await ref.get()).data();
  assert.strictEqual(ev.source, "assessor_entry");
  assert.strictEqual(ev.instrument, "PHQ-9");
  assert.strictEqual(ev.item, 9);
  assert.strictEqual(ev.rawValue, 1);
  assert.strictEqual(ev.alwaysAlert, true);
  assert.strictEqual(ev.level, "moderate", "caller lowered the level");
  assert.strictEqual(ev.textHash, null);
  // The trigger alerts although the level is below acute.
  await fns.onSafetyEventCreated.run({data: await ref.get(),
    params: {eventId: made.id}});
  const rows = await alerts();
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].data().sourceGroup, "assessor_entry");
  assert.strictEqual(rows[0].data().alwaysAlert, true);
  assert.strictEqual(rows[0].data().instrument, "PHQ-9");
  assert.strictEqual(sent.length, 1);
  const t = sent[0].text;
  assert.ok(t.includes("来源 Source: 评估员录入 Assessor entry"), t);
  assert.ok(t.includes("研究期 Study period: 试跑 Pilot run"));
  assert.ok(t.includes("PHQ-9 第 9 题 item 9"));
  assert.ok(t.includes("研究第几天 Study day: 未知 Unknown"), "no w0Date");
  assert.ok(t.includes("是否显示危机页 Crisis page shown: 未知 Unknown"));
  assert.ok(!t.includes("rawValue"));

  // Default level (acute) and the in-App source.
  const q2 = await qs.recordQuestionnaireSafetyEvent(db, {uid: UID_Q,
    source: "questionnaire", instrument: "PHQ-9", item: 9, rawValue: 3});
  assert.strictEqual(q2.tier, "acute");
  const ev2 = (await db.doc(q2.path).get()).data();
  assert.strictEqual(ev2.source, "questionnaire");
  assert.strictEqual(ev2.inputPoint, "in_app_questionnaire");
});

test("switch off: a questionnaire event still alerts (T19 e-mail, level " +
  "named)", async () => {
  await reset(null);
  const made = await qs.recordQuestionnaireSafetyEvent(db, {uid: UID_Q,
    source: "assessor_entry", instrument: "PHQ-9", item: 9, rawValue: 2,
    level: "moderate_review"});
  await fns.onSafetyEventCreated.run({data: await db.doc(made.path).get(),
    params: {eventId: made.id}});
  assert.strictEqual((await alerts()).length, 1);
  assert.strictEqual(sent.length, 1);
  assert.ok(sent[0].text.includes("level: moderate_review"), sent[0].text);
});

test("export: safety rows carry sourceGroup; per-source counts; AI-reply " +
  "rows stay out of the blinded export", async () => {
  await reset(ON);
  await db.doc("meta/blinding_config").set({enabled: true});
  const add = (uid, source, extra) => db.collection("safety_events").add(
      Object.assign({uid, source, textHash: "h", level: "acute", tier: "acute",
        lexiconVersion: "v5", isDuplicate: false,
        createdAt: admin.firestore.Timestamp.now()}, extra || {}));
  await add(UID_A, "user_input", {crisisPageShown: true});
  await add(UID_A, "ai_output_scan", {crisisPageShown: true});
  await add(UID_B, "rule_turn", {crisisPageShown: false});
  await add(UID_B, "questionnaire", {instrument: "PHQ-9", item: 9,
    rawValue: 2, alwaysAlert: true});
  await add(UID_A, "assessor_entry", {instrument: "PHQ-9", item: 9,
    rawValue: 1, alwaysAlert: true});
  const out = await blinding.buildBlindedExport(db, {});
  const rows = out.files.safety_events;
  assert.strictEqual(rows.length, 4, "ai_output_scan dropped");
  const groups = rows.map((r) => r.sourceGroup).sort();
  assert.deepStrictEqual(groups, ["assessor_entry", "participant_input",
    "participant_input", "questionnaire"]);
  assert.deepStrictEqual(out.manifest.safetyEventsBySource,
      {participant_input: 2, questionnaire: 1, assessor_entry: 1});
  assert.strictEqual(out.manifest.safetyEventsNotFromUserInput, 1);
  for (const r of rows) {
    assert.strictEqual(r.source, undefined, "raw source never leaves");
    assert.strictEqual(r.rawValue, undefined, "the answer never leaves");
    assert.strictEqual(r.uid, undefined);
    assert.ok(typeof r.crisisPageShown === "boolean" ||
      r.crisisPageShown === undefined);
  }
  const q = rows.find((r) => r.sourceGroup === "questionnaire");
  assert.strictEqual(q.instrument, "PHQ-9");
  assert.strictEqual(q.item, 9);
  // v1 export helper: every source maps to one of the four buckets.
  assert.strictEqual(piAlert.sourceGroupFor("ai_output_scan"),
      "ai_reply_scan");
  await db.doc("meta/blinding_config").delete();
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
  // Leave the emulator as the next test file expects it: no alert
  // config (switch off), no blinding config, no T34 rows.
  await db.doc("meta/alert_config").delete();
  await db.doc("meta/blinding_config").delete();
  for (const n of ["safety_events", "safety_event_dedup", "pi_alerts",
    "alert_audit_log", "research_id_map", "research_ids", "users"]) {
    await clear(n);
  }
  console.log(`safety_alert_t34_emulator_test: ${tests.length - failed}/` +
    `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

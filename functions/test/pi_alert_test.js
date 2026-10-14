/**
 * T34 — safety alert e-mail: pure helpers of functions/pi_alert.js and
 * functions/questionnaire_safety.js (no Firestore, no network).
 *
 *   dev-tasks-1010b §三 T34 §7 items 1 (fields, nothing arm-revealing,
 *   both arms the same field set), 2 (recipient role check), 5 (PHQ-9
 *   item 9 rule), plus the switch-off e-mail staying as it was.
 *
 * Run: node functions/test/pi_alert_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const piAlert = require("../pi_alert");
const qs = require("../questionnaire_safety");
const blinding = require("../blinding");

const AT = new Date("2026-10-20T02:30:00Z"); // 10:30 HKT
const STAMP = "server-timestamp";

// Two synthetic events of one acute turn, one per arm.  Everything that
// differs by arm is present on purpose so the test can prove it never
// reaches the e-mail.
const ARM_A_EVENT = {
  uid: "uid-a", source: "ai_output_scan", inputPoint: "chat_reflective",
  turnId: "ta", textHash: "deadbeef", level: "acute", tier: "acute",
  category: "ideation", lexiconVersion: "v5-2026-09", matchedTerm: "自殺",
  agentId: "siu_yan", sessionId: "s1", detector: "both",
  classifierStatus: "ok", crisisPageShown: true, arm: "A",
};
const ARM_B_EVENT = {
  uid: "uid-b", source: "rule_turn", inputPoint: "check_in_note",
  turnId: "tb", textHash: "cafebabe", level: "acute", tier: "acute",
  category: "ideation", lexiconVersion: "v5-2026-09", matchedTerm: "想死",
  agentId: "tung_tung", sessionId: "s2", crisisPageShown: true, arm: "B",
};

function row(event, over) {
  return piAlert.buildAlertRow(Object.assign({
    event, eventPath: `safety_events/${event.turnId}`, uid: event.uid,
    researchId: "PB-A01", user: {w0Date: "2026-10-19"}, isTester: false,
    dedupKey: "k", level: event.level, at: AT,
  }, over || {}), STAMP);
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch config: missing doc = off, defaults", () => {
  const off = piAlert.configFromData(null);
  assert.strictEqual(off.enabled, false);
  assert.strictEqual(off.primaryEmail, null);
  assert.strictEqual(off.backupEmail, null);
  assert.strictEqual(off.escalateAfterHours, 12);
  assert.strictEqual(piAlert.configFromData({enabled: "true"}).enabled,
      false, "only literal true turns it on");
  const on = piAlert.configFromData({enabled: true, primaryEmail: " a@x.hk ",
    backupEmail: "b@x.hk", escalateAfterHours: 6});
  assert.strictEqual(on.enabled, true);
  assert.strictEqual(on.primaryEmail, "a@x.hk");
  assert.strictEqual(on.escalateAfterHours, 6);
  assert.strictEqual(piAlert.configFromData({escalateAfterHours: -1})
      .escalateAfterHours, 12);
});

test("source → four analysis buckets; questionnaire sources server-only",
    () => {
      const g = piAlert.sourceGroupFor;
      for (const s of ["user_input", "form", "gateway_input", "rule_turn",
        "m3_turn"]) {
        assert.strictEqual(g(s), "participant_input", s);
      }
      assert.strictEqual(g("ai_output_scan"), "ai_reply_scan");
      assert.strictEqual(g("gateway_output"), "ai_reply_scan");
      assert.strictEqual(g("questionnaire"), "questionnaire");
      assert.strictEqual(g("assessor_entry"), "assessor_entry");
      assert.strictEqual(g("whatever"), null);
      assert.strictEqual(g(undefined), null);
      assert.deepStrictEqual(piAlert.SERVER_ONLY_SOURCES,
          ["questionnaire", "assessor_entry"]);
      // The blinded v2 export uses the same grouping.
      for (const s of Object.keys(blinding.SAFETY_SOURCE_GROUP)) {
        assert.strictEqual(blinding.SAFETY_SOURCE_GROUP[s], g(s), s);
      }
    });

test("alwaysAlerts only for a server-only source with alwaysAlert: true",
    () => {
      assert.strictEqual(piAlert.alwaysAlerts({source: "assessor_entry",
        alwaysAlert: true}), true);
      assert.strictEqual(piAlert.alwaysAlerts({source: "questionnaire",
        alwaysAlert: true}), true);
      assert.strictEqual(piAlert.alwaysAlerts({source: "user_input",
        alwaysAlert: true}), false, "a client cannot force an alert");
      assert.strictEqual(piAlert.alwaysAlerts({source: "assessor_entry"}),
          false);
    });

test("study period from the research-ID prefix (T21 rule)", () => {
  assert.strictEqual(piAlert.periodCodeFor("PB-A01"), "B");
  assert.strictEqual(piAlert.periodCodeFor("PILOT-07"), "PILOT");
  assert.strictEqual(piAlert.periodCodeFor("PA-01"), null);
  assert.strictEqual(piAlert.periodCodeFor(null), null);
});

test("study day: W0 = day 0, Hong Kong calendar days, unknown without w0Date",
    () => {
      const d = piAlert.studyDay;
      // 2026-10-20 02:30Z is 10:30 HKT on 10-20.
      assert.strictEqual(d({w0Date: "2026-10-20"}, AT), 0);
      assert.strictEqual(d({w0Date: "2026-10-19"}, AT), 1);
      assert.strictEqual(d({w0Date: "2026-10-13"}, AT), 7);
      // 2026-10-19 17:00Z is 01:00 HKT on 10-20: still day 1, not day 0.
      assert.strictEqual(d({w0Date: "2026-10-19"},
          new Date("2026-10-19T17:00:00Z")), 1);
      assert.strictEqual(d({w0Date: "2026-10-21"}, AT), -1);
      assert.strictEqual(d({}, AT), null);
      assert.strictEqual(d(null, AT), null);
      assert.strictEqual(d({w0Date: "20261019"}, AT), null);
    });

test("classifier involved: from detector / classifierStatus", () => {
  const c = piAlert.classifierInvolved;
  assert.strictEqual(c({detector: "both"}), "yes");
  assert.strictEqual(c({detector: "classifier"}), "yes");
  assert.strictEqual(c({detector: "lexicon"}), "no");
  assert.strictEqual(c({}), "no", "no classifier field at all = lexicon");
  assert.strictEqual(c({classifierStatus: "ok"}), "yes");
  assert.strictEqual(c({detector: "odd"}), "unknown");
});

test("e-mail: fixed field order, zh + en, every required field", () => {
  const r = row(ARM_A_EVENT);
  const mail = piAlert.buildAlertEmail(r, {alertId: "AL1", at: AT,
    escalation: false, escalateAfterHours: 12});
  const labels = piAlert.emailFields(r, {alertId: "AL1", at: AT})
      .map((f) => f[0]);
  assert.deepStrictEqual(labels, [
    "研究编号 Research ID", "研究期 Study period", "陪伴者 Companion",
    "来源 Source", "级别和类别 Level and category", "词库版本 Lexicon version",
    "LoRA 是否参与判定 Classifier involved", "研究第几天 Study day",
    "是否显示危机页 Crisis page shown", "事件编号 Event ID",
    "告警编号 Alert ID", "时间（香港） Time (HKT)",
  ]);
  const t = mail.text;
  assert.ok(t.includes("研究编号 Research ID: PB-A01"), t);
  assert.ok(t.includes("研究期 Study period: Phase B"));
  assert.ok(t.includes("陪伴者 Companion: 小欣 Siu Yan (siu_yan)"));
  assert.ok(t.includes("来源 Source: AI 回复扫描 AI reply scan"));
  assert.ok(t.includes("级别和类别 Level and category: 急性 acute / ideation"));
  assert.ok(t.includes("词库版本 Lexicon version: v5-2026-09"));
  assert.ok(t.includes("LoRA 是否参与判定 Classifier involved: 是 Yes"));
  assert.ok(t.includes("研究第几天 Study day: 1"));
  assert.ok(t.includes("是否显示危机页 Crisis page shown: 是 Yes"));
  assert.ok(t.includes("事件编号 Event ID: safety_events/ta"));
  assert.ok(t.includes("告警编号 Alert ID: pi_alerts/AL1"));
  assert.ok(t.includes("时间（香港） Time (HKT): 2026-10-20 10:30"));
  assert.ok(mail.subject.includes("急性 acute"), mail.subject);
  assert.ok(mail.subject.includes("PB-A01"));
  assert.ok(!mail.subject.includes("转后备"));
});

test("e-mail: never arm, matched term, text hash, uid or wording", () => {
  for (const ev of [ARM_A_EVENT, ARM_B_EVENT]) {
    const r = row(ev);
    for (const k of ["arm", "matchedTerm", "textHash", "inputPoint",
      "sessionId"]) {
      assert.strictEqual(r[k], undefined, `row has no ${k}`);
    }
    const mail = piAlert.buildAlertEmail(r, {alertId: "AL", at: AT,
      escalation: true, escalateAfterHours: 12});
    const all = mail.subject + "\n" + mail.text;
    for (const bad of ["Arm", "arm:", "組別", "组别: ", ev.matchedTerm,
      ev.textHash, ev.uid, ev.inputPoint, "Hybrid", "规则组"]) {
      assert.ok(!all.includes(bad), `e-mail must not contain ${bad}`);
    }
  }
});

test("both arms: same field set, same labels, same length of row keys",
    () => {
      const a = row(ARM_A_EVENT);
      const b = row(ARM_B_EVENT);
      assert.deepStrictEqual(Object.keys(a).sort(), Object.keys(b).sort());
      const la = piAlert.emailFields(a, {alertId: "x", at: AT})
          .map((f) => f[0]);
      const lb = piAlert.emailFields(b, {alertId: "x", at: AT})
          .map((f) => f[0]);
      assert.deepStrictEqual(la, lb);
      const mb = piAlert.buildAlertEmail(b, {alertId: "x", at: AT,
        escalation: false, escalateAfterHours: 12}).text;
      assert.ok(mb.includes("来源 Source: 老人输入 Participant input"));
      assert.ok(mb.includes("陪伴者 Companion: 通通 Tung Tung (tung_tung)"));
      assert.ok(mb.includes("LoRA 是否参与判定 Classifier involved: 否 No"));
    });

test("e-mail: unknowns and the escalation header", () => {
  const r = row(Object.assign({}, ARM_B_EVENT, {agentId: null,
    lexiconVersion: null, crisisPageShown: undefined}),
  {researchId: "X-01", user: null});
  const text = piAlert.buildAlertEmail(r, {alertId: "AL2", at: AT,
    escalation: true, escalateAfterHours: 12}).text;
  assert.ok(text.includes("研究期 Study period: 未知 Unknown"), text);
  assert.ok(text.includes("陪伴者 Companion: —"));
  assert.ok(text.includes("词库版本 Lexicon version: —"));
  assert.ok(text.includes("研究第几天 Study day: 未知 Unknown"));
  assert.ok(text.includes("是否显示危机页 Crisis page shown: 未知 Unknown"));
  assert.ok(text.includes("【转后备】"));
  assert.ok(text.includes("Escalated: nobody acknowledged"));
  // Primary and escalation e-mails carry the same field lines.
  const primary = piAlert.buildAlertEmail(r, {alertId: "AL2", at: AT,
    escalation: false, escalateAfterHours: 12}).text;
  const fieldLines = (s) => s.split("\n").filter((l) => /^[^ ]+ .*: /.test(l) &&
    !l.startsWith("【") && !l.startsWith("Escalated"));
  assert.deepStrictEqual(fieldLines(text), fieldLines(primary));
});

test("pilot period, questionnaire event fields", () => {
  const ev = {uid: "u", source: "assessor_entry", instrument: "PHQ-9",
    item: 9, rawValue: 2, level: "acute", tier: "acute", category: "ideation",
    alwaysAlert: true, researchId: "PILOT-03"};
  const r = row(ev, {researchId: "PILOT-03", user: {w0Date: "2026-09-25"}});
  assert.strictEqual(r.studyPeriod, "PILOT");
  assert.strictEqual(r.alwaysAlert, true);
  assert.strictEqual(r.instrument, "PHQ-9");
  const text = piAlert.buildAlertEmail(r, {alertId: "Q", at: AT,
    escalation: false, escalateAfterHours: 12}).text;
  assert.ok(text.includes("研究期 Study period: 试跑 Pilot run"), text);
  assert.ok(text.includes("来源 Source: 评估员录入 Assessor entry"));
  assert.ok(text.includes("PHQ-9 第 9 题 item 9"));
  assert.ok(!text.includes("rawValue") && !/: 2$/m.test(text),
      "the raw answer is not in the e-mail");
});

test("recipients: blinded dropped, unknown address kept, duplicates once",
    async () => {
      const auth = {
        getUserByEmail: async (email) => {
          if (email === "assessor@x.hk") {
            return {customClaims: {role: "blinded"}};
          }
          if (email === "junyu@x.hk") {
            return {customClaims: {role: "unblinded"}};
          }
          const e = new Error("nf");
          e.code = "auth/user-not-found";
          throw e;
        },
      };
      const r = await piAlert.resolveRecipients(auth,
          ["junyu@x.hk", "Assessor@x.hk", "calvin@x.hk", "junyu@x.hk", "",
            null]);
      assert.deepStrictEqual(r.to, ["junyu@x.hk", "calvin@x.hk"]);
      assert.deepStrictEqual(r.dropped,
          [{email: "assessor@x.hk", reason: "blinded_role"}]);
      assert.deepStrictEqual(r.notes,
          [{email: "calvin@x.hk", note: "no_app_account"}]);
      const failing = {getUserByEmail: async () => {
        throw new Error("boom");
      }};
      const f = await piAlert.resolveRecipients(failing, ["a@x.hk"]);
      assert.deepStrictEqual(f.to, ["a@x.hk"], "lookup error keeps it");
      assert.strictEqual(f.notes[0].note, "lookup_failed");
    });

test("switch off: the T19 row and e-mail are unchanged", () => {
  const r = piAlert.buildPiAlert({uid: "u", researchId: "PB-A01",
    level: "acute", dedupKey: "k", isTester: false,
    eventPath: "safety_events/e"}, STAMP);
  assert.deepStrictEqual(Object.keys(r).sort(), ["alertVersion", "createdAt",
    "dedupKey", "eventPath", "isTester", "level", "researchId", "uid"]);
  assert.strictEqual(r.alertVersion, 2);
  const m = piAlert.buildPiEmail({researchId: "PB-A01", alertId: "A",
    at: AT});
  assert.strictEqual(m.subject, "[LonelinessCombatting] Acute distress alert");
  assert.ok(m.text.startsWith("An acute distress event was detected."));
  assert.ok(m.text.includes("Research ID: PB-A01"));
  assert.ok(!m.text.includes("Source") || m.text.includes("left out"));
});

test("questionnaire rule: PHQ-9 item 9 = 0 → nothing; ≠ 0 → event", () => {
  const t = qs.triggers;
  assert.strictEqual(t({instrument: "PHQ-9", item: 9, rawValue: 0}), false);
  assert.strictEqual(t({instrument: "PHQ-9", item: 9, rawValue: "0"}), false);
  for (const v of [1, 2, 3, "3"]) {
    assert.strictEqual(t({instrument: "PHQ-9", item: 9, rawValue: v}), true);
  }
  assert.strictEqual(t({instrument: "PHQ-9", item: 8, rawValue: 3}), false);
  assert.strictEqual(t({instrument: "GAD-7", item: 9, rawValue: 3}), false);
  assert.strictEqual(t({instrument: "PHQ-9", item: 9, rawValue: "x"}), false);
  assert.strictEqual(t(null), false);
});

test("questionnaire entry refuses bad input before the db", async () => {
  const db = {collection: () => {
    throw new Error("must not be called");
  }};
  for (const p of [
    {uid: "", source: "assessor_entry", instrument: "PHQ-9", item: 9,
      rawValue: 1},
    {uid: "u", source: "user_input", instrument: "PHQ-9", item: 9,
      rawValue: 1},
    {uid: "u", source: "assessor_entry", instrument: "", item: 9,
      rawValue: 1},
    {uid: "u", source: "assessor_entry", instrument: "PHQ-9", item: "9",
      rawValue: 1},
  ]) {
    await assert.rejects(qs.recordQuestionnaireSafetyEvent(db, p));
  }
  // Non-trigger: null, no write.
  const r = await qs.recordQuestionnaireSafetyEvent(db, {uid: "u",
    source: "assessor_entry", instrument: "PHQ-9", item: 9, rawValue: 0});
  assert.strictEqual(r, null);
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
  console.log(`pi_alert_test: ${tests.length - failed}/${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

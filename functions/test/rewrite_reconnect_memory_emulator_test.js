/**
 * 1020e 二.13 (2) — tool/rewrite_reconnect_memory.js on the emulator:
 * intake facts written before the 「可以講」 rule carry every
 * 想重新聯絡嘅人 name; the dry run writes nothing, --apply re-seeds the
 * intake facts so only the shared names stay, a fact with no shared name
 * left goes away, conversation facts and already-right accounts are not
 * touched, and nothing printed contains a name.
 */
/* eslint-disable require-jsdoc */
"use strict";

const assert = require("assert");
const path = require("path");
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}

admin.initializeApp({projectId: "demo-rewrite-reconnect"});
const db = admin.firestore();
const ri = require("../researcher_intake");
const tool = require(path.join(__dirname, "..", "..", "tool",
    "rewrite_reconnect_memory"));

const NOW = new Date("2026-10-20T04:00:00Z");
const KEY = "想重新聯絡嘅人";

async function reset() {
  const cols = await db.listCollections();
  for (const c of cols) await db.recursiveDelete(c);
}

// The pre-1020e write: every reconnect name, shared or not.
async function seedOld(uid, rid, reconnect, extra) {
  await db.doc(`enrollments/${uid}`).set({researchId: rid});
  await db.doc(ri.intakeDocPath(uid)).set(Object.assign({
    mainGoals: ["companionship"], reconnectPeople: reconnect,
    importantPeople: [],
  }, extra || {}));
  const col = db.collection(`users/${uid}/mem_facts`);
  const all = reconnect.map((p) => `${p.name}（${p.relationship}）`)
      .join("、");
  await col.add({agent_id: "siu_yan", category: "family", key: KEY,
    value: all, status: "active", source_session_id: ri.INTAKE_SOURCE,
    visibility: "shared", sensitivity: "normal"});
  await col.add({agent_id: "siu_yan", category: "preference",
    key: "嚟呢度主要想", value: "想有人陪下傾偈", status: "active",
    source_session_id: ri.INTAKE_SOURCE, visibility: "shared",
    sensitivity: "normal"});
  // A fact 小欣 heard in a chat — never touched.
  await col.add({agent_id: "siu_yan", category: "family", key: "孫",
    value: "孫仔叫阿明", status: "active", source_session_id: "s1",
    visibility: "shared", sensitivity: "normal"});
}

async function active(uid) {
  return (await db.collection(`users/${uid}/mem_facts`)
      .where("status", "==", "active").get()).docs.map((d) => d.data());
}

const results = [];
async function test(name, fn) {
  try {
    await fn();
    results.push(true);
    console.log(`ok  ${name}`);
  } catch (e) {
    results.push(false);
    console.log(`FAIL ${name}\n     ${e.stack}`);
  }
}

(async () => {
  await test("dry run lists the change without names and writes nothing",
      async () => {
        await reset();
        await seedOld("u1", "RCT-001", [
          {name: "阿強", relationship: "舊同事", share: true},
          {name: "陳生", relationship: "舊街坊", share: false},
        ]);
        const lines = [];
        const out = await tool.run(db, {apply: false, now: NOW,
          log: (s) => lines.push(s)});
        assert.deepStrictEqual(out, {checked: 1, changed: 1});
        assert.strictEqual(lines.length, 1);
        assert.ok(lines[0].includes("RCT-001"));
        assert.ok(lines[0].includes("2 个名 → 1 个名"));
        for (const n of ["阿強", "陳生", "舊同事", "舊街坊"]) {
          assert.ok(!lines[0].includes(n), "no name printed");
        }
        const f = (await active("u1")).find((x) => x.key === KEY);
        assert.strictEqual(f.value, "阿強（舊同事）、陳生（舊街坊）",
            "dry run left it as it was");
      });

  await test("--apply keeps only the shared names; chat facts untouched",
      async () => {
        await tool.run(db, {apply: true, now: NOW, log: () => {}});
        const facts = await active("u1");
        const f = facts.filter((x) => x.key === KEY);
        assert.strictEqual(f.length, 1);
        assert.strictEqual(f[0].value, "阿強（舊同事）");
        assert.ok(facts.some((x) => x.key === "孫" &&
          x.source_session_id === "s1"), "conversation fact kept");
        const all = (await db.collection("users/u1/mem_facts").get()).docs;
        assert.ok(all.some((d) => d.get("status") === "superseded" &&
          d.get("key") === KEY), "old fact superseded, not deleted");
        // Run again: nothing left to change.
        const again = await tool.run(db, {apply: true, now: NOW,
          log: () => {}});
        assert.strictEqual(again.changed, 0);
      });

  await test("nobody shared → the fact goes; other accounts untouched",
      async () => {
        await reset();
        await seedOld("u2", "PB-01", [
          {name: "黃太", relationship: "舊鄰居"}, // old row: no `share`
        ]);
        await db.doc("enrollments/u3").set({researchId: "PILOT-01"});
        const out = await tool.run(db, {apply: true, now: NOW,
          log: () => {}});
        assert.deepStrictEqual(out, {checked: 2, changed: 1});
        const facts = await active("u2");
        assert.ok(!facts.some((x) => x.key === KEY));
        assert.ok(facts.some((x) => x.key === "嚟呢度主要想"));
        assert.strictEqual((await db.collection("users/u3/mem_facts")
            .get()).size, 0);
      });

  const passed = results.filter(Boolean).length;
  console.log(`rewrite_reconnect_memory_emulator_test: ${passed}/` +
    `${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
})();

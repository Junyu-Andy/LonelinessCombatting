/**
 * T40 — usage events against the Firestore emulator (dev-tasks-1014d T40
 * acceptance 1–2, server side): rows written by a synthetic enrolled
 * participant are stamped with the research ID, the Hong Kong day, the
 * study day and uploadedLate; three rows written 'offline' (client time
 * well before the server's receipt) are marked late with their client
 * time unchanged; a fresh row is not; a second run changes nothing.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/usage_events_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const UE = require("../usage_events");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const UID = "usage_pilot_01";
const NOW = new Date("2026-10-20T04:00:00Z"); // 12:00 HKT, study day 5

async function reset() {
  await db.recursiveDelete(db.collection("users").doc(UID));
  await db.collection("research_id_map").doc(UID).delete();
}

async function write(type, clientAt, receivedAt) {
  const ref = db.collection("users").doc(UID).collection(UE.COLLECTION).doc();
  await ref.set({
    type, clientAt: new Date(clientAt), receivedAt: new Date(receivedAt),
    appVersion: "1.0.0", buildNumber: "3", platform: "android",
    schemaVersion: 1,
  });
  return ref;
}

async function stamp(ref) {
  const snap = await ref.get();
  return UE.stampCreated(db, UID, ref.id, snap.data(), {now: NOW});
}

async function main() {
  await reset();
  await db.collection("users").doc(UID).set({
    uid: UID, cohort: "pilot", arm: "B", w0Date: "2026-10-15",
  });
  await db.collection("research_id_map").doc(UID).set({
    uid: UID, researchId: "PILOT-03",
  });

  // 1. An online pair: stamped, not late.
  const fg = await write("foreground", "2026-10-20T03:59:58Z",
      "2026-10-20T04:00:00Z");
  const bg = await write("background", "2026-10-20T04:05:00Z",
      "2026-10-20T04:05:01Z");
  for (const ref of [fg, bg]) {
    const s = await stamp(ref);
    assert.ok(s, "stamped");
    const d = (await ref.get()).data();
    assert.strictEqual(d.researchId, "PILOT-03");
    assert.strictEqual(d.dayKey, "2026-10-20");
    assert.strictEqual(d.studyDay, 5);
    assert.strictEqual(d.uploadedLate, false);
    assert.strictEqual(d.clockSkew, false);
    assert.strictEqual(d.appVersion, "1.0.0");
    assert.strictEqual(d.buildNumber, "3");
  }
  console.log("ok - online pair stamped: research ID, HK day, study day");

  // 2. Three rows cached offline (client times 10:00, 10:20, 10:40 HKT)
  //    and uploaded together at 12:00 HKT: all late, client time kept.
  const late = [];
  for (const t of ["02:00:00", "02:20:00", "02:40:00"]) {
    late.push(await write("foreground", `2026-10-20T${t}Z`,
        "2026-10-20T04:00:00Z"));
  }
  const kept = [];
  for (const ref of late) {
    await stamp(ref);
    const d = (await ref.get()).data();
    assert.strictEqual(d.uploadedLate, true);
    assert.ok(d.lateByMs >= 80 * 60 * 1000);
    kept.push(d.clientAt.toDate().toISOString());
  }
  assert.deepStrictEqual(kept, ["2026-10-20T02:00:00.000Z",
    "2026-10-20T02:20:00.000Z", "2026-10-20T02:40:00.000Z"]);
  console.log("ok - three offline rows: uploadedLate, client time unchanged");

  // 3. Idempotent: a second run writes nothing.
  assert.strictEqual(await stamp(fg), null);
  const again = (await fg.get()).data();
  assert.strictEqual(again.stampedAt.toDate().toISOString(),
      NOW.toISOString());
  console.log("ok - second run leaves a stamped row alone");

  // 4. The row count is what was written: 5 (2 online + 3 late).
  const all = await db.collection("users").doc(UID)
      .collection(UE.COLLECTION).get();
  assert.strictEqual(all.size, 5);
  for (const doc of all.docs) {
    const d = doc.data();
    assert.ok(["foreground", "background"].indexOf(d.type) >= 0);
    for (const k of Object.keys(d)) {
      assert.ok(["type", "clientAt", "receivedAt", "appVersion",
        "buildNumber", "platform", "schemaVersion"]
          .concat(UE.SERVER_FIELDS).indexOf(k) >= 0, `unexpected field ${k}`);
    }
  }
  console.log("ok - rows hold only the client fields and the server stamp");

  await reset();
  console.log("all usage_events emulator tests passed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

/**
 * T35 — the W8 questionnaire in the App, server side (handover
 * 1021-W8; decision 0036).  Both arms identical; no LLM anywhere here;
 * no switch (decisions-log 10/20 item 87): it ships with the Functions
 * deploy and changes nothing before study day 56.
 *
 * Who: every registered, non-tester account (studyPeriod.isEnrolled:
 * RCT-, PB- run-in and PILOT- alike).  Testers never get a W8 push or
 * an e-mail line (switched testers included); they preview W8 in the
 * tester tools.
 *
 * When (study days, W0 = day 0, Hong Kong dates; study_week.js):
 *   window       day 56 00:00 → end of day 63 (23:59:59)
 *   pushes       day 56 at weeklyPushHour (app_config/phase_b, default
 *                10) to everyone; day 58 and day 60 at the same hour only
 *                to whoever has not finished the five parts.  No day-62
 *                reminder.  Quiet hours do not apply (handover 一 (6)).
 *   e-mail       day 60 at the same hour: the research lead gets the
 *                research IDs and study day of everyone still not done —
 *                never the arm, the cohort or an answer.
 *   late         after day 63 the home card stays until the end of day
 *                70; answers are accepted and stamped outOfWindow: true.
 *   close        from day 71 the dispatcher writes a `missed` record for
 *                every part not submitted and the final status.
 *
 * Records (one document per part, id "W8", the weekly bundle's layout):
 *   users/{uid}/djg_responses/W8     DJG-ES 6 (T18 schema + answeredAt)
 *   users/{uid}/ucla3_responses/W8   UCLA-3, 1–3
 *   users/{uid}/pgic/W8              PGIC, value 1–7 (existing format)
 *   users/{uid}/ci_responses/W8      continuance intention CI1–CI3, 1–5
 *   users/{uid}/lsns6_responses/W8   LSNS-6, 0–5
 *   users/{uid}/aimhs_responses/W8   AIMHS 5, 1–5, optional (may be
 *                                    `declined`; item 1 reversed only at
 *                                    analysis)
 * A skipped item is stored as "skipped" (DJG's convention).  The App
 * writes answers, per-item answer times (`answeredAt`), status and
 * times; this module (trigger onW8PartWritten) stamps studyWeek 8,
 * studyDay 56, submittedStudyDay, outOfWindow, the window and the scores
 * (DJG-ES as T18, UCLA-3 total, LSNS-6 family / friends / total).
 * firestore.rules refuses all of those from a client.
 *
 * Whole-questionnaire status (server only, never an answer):
 *   weekly_status/{uid}.bundles.W8   pushedAt, remind1SentAt,
 *                                    remind2SentAt, parts (state per
 *                                    part), partsSubmitted, completedAt,
 *                                    completedOutOfWindow, aimhs, status,
 *                                    closedAt, missedParts
 * The operations dashboard reads only this (ops_dashboard.js w8Status).
 */

"use strict";

const studyWeek = require("./study_week");
const studyPeriod = require("./study_period");
const weeklySchedule = require("./weekly_schedule");
const djgW2 = require("./djg_w2");
const piAlert = require("./pi_alert");

const BUNDLE_ID = "W8";
const STUDY_WEEK = 8;
/** Study days (W0 = 0). */
const OPEN_DAY = 56;
const CLOSE_DAY = 63;
const LAST_CARD_DAY = 70;
const REMIND1_DAY = 58;
const REMIND2_DAY = 60;
const EMAIL_DAY = 60;
/** Missed marks only within a week after the late period ends. */
const CLOSE_LOOKBACK_MS = 7 * 86400000;

const PUSH_TITLE = "陪住";
/** Handover 1021-W8 §三, word for word (the same on days 56, 58, 60). */
const PUSH_BODY = "最後一份問卷開咗，請喺一個禮拜內入嚟答埋佢。多謝你！";
const KIND_OPEN = "w8_open";
const KIND_REMINDER = "w8_reminder";

const EMAIL_SUBJECT = "陪住：最後一份問卷（W8）未完成名單";
const AUDIT_PREFIX = "w8_incomplete_";
const WEEKDAY_ZH = ["日", "一", "二", "三", "四", "五", "六"];

/**
 * @param {number} n
 * @return {string[]} q1…qn
 */
function ids(n) {
  const out = [];
  for (let i = 1; i <= n; i++) out.push(`q${i}`);
  return out;
}

/**
 * @param {number} from
 * @param {number} to
 * @return {number[]} from…to
 */
function range(from, to) {
  const out = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
}

/**
 * @param {?object} answers
 * @param {string[]} items
 * @param {number[]} values
 * @return {?number} sum, null when any item is skipped or missing
 */
function sumOrNull(answers, items, values) {
  const a = answers || {};
  let sum = 0;
  for (const k of items) {
    if (values.indexOf(a[k]) < 0) return null;
    sum += a[k];
  }
  return sum;
}

/**
 * UCLA-3: 很少 1, 有時 2, 經常 3; total 3–9, null with a skipped item.
 * @param {?object} answers
 * @return {{total: ?number}}
 */
function scoreUcla3(answers) {
  return {total: sumOrNull(answers, ids(3), [1, 2, 3])};
}

/**
 * LSNS-6: 沒有 0 … 九個或以上 5; family q1–q3, friends q4–q6 (0–15
 * each), total 0–30; a subscale with a skipped item is null, and so is
 * the total.
 * @param {?object} answers
 * @return {{family: ?number, friends: ?number, total: ?number}}
 */
function scoreLsns6(answers) {
  const v = range(0, 5);
  const family = sumOrNull(answers, ["q1", "q2", "q3"], v);
  const friends = sumOrNull(answers, ["q4", "q5", "q6"], v);
  return {family, friends,
    total: family === null || friends === null ? null : family + friends};
}

/**
 * The parts, in the App's fixed order (handover 二 (1)), then the
 * optional AIMHS.  `score` / `scoringVersion` only where the server
 * scores.
 */
const PARTS = [
  {id: "djg", collection: "djg_responses", items: ids(6),
    values: ["yes", "mostly", "no"], score: djgW2.scoreAnswers,
    scoringVersion: djgW2.SCORING_VERSION},
  {id: "ucla3", collection: "ucla3_responses", items: ids(3),
    values: [1, 2, 3], score: scoreUcla3, scoringVersion: "ucla3_v1"},
  {id: "pgic", collection: "pgic", items: ["value"], values: range(1, 7)},
  {id: "ci", collection: "ci_responses", items: ids(3), values: range(1, 5)},
  {id: "lsns6", collection: "lsns6_responses", items: ids(6),
    values: range(0, 5), score: scoreLsns6, scoringVersion: "lsns6_v1"},
];
const AIMHS = {id: "aimhs", collection: "aimhs_responses", items: ids(5),
  values: range(1, 5), optional: true};
const ALL_PARTS = PARTS.concat([AIMHS]);
/** The four collections only W8 writes (firestore.rules w8Collections). */
const NEW_COLLECTIONS = ["ucla3_responses", "ci_responses",
  "lsns6_responses", "aimhs_responses"];

/** Server-written fields on a W8 part record (firestore.rules). */
const SERVER_ONLY_FIELDS = ["studyWeek", "studyDay", "submittedStudyDay",
  "outOfWindow", "windowStart", "windowEnd", "acceptUntil", "scores",
  "scoringVersion", "scoredAt", "stampedAt", "missed", "missedAt"];

/**
 * @param {string} collection
 * @return {?object} the W8 part stored in that collection
 */
function partByCollection(collection) {
  for (const p of ALL_PARTS) if (p.collection === collection) return p;
  return null;
}

// ---------------------------------------------------------------------------
// Dates (pure).  Mirrored in lib/features/w8/data/w8_schedule.dart.
// ---------------------------------------------------------------------------

/**
 * Every W8 date of one participant.
 * @param {string} w0Key YYYY-MM-DD
 * @return {{w0: string, openKey: string, remind1Key: string,
 *     remind2Key: string, emailKey: string, closeKey: string,
 *     lastCardKey: string, windowStart: Date, windowEnd: Date,
 *     acceptUntil: Date}} windowEnd / acceptUntil are exclusive (the
 *     next day's 00:00)
 */
function datesFor(w0Key) {
  const day = (n) => studyWeek.addDays(w0Key, n);
  return {
    w0: w0Key,
    openKey: day(OPEN_DAY),
    remind1Key: day(REMIND1_DAY),
    remind2Key: day(REMIND2_DAY),
    emailKey: day(EMAIL_DAY),
    closeKey: day(CLOSE_DAY),
    lastCardKey: day(LAST_CARD_DAY),
    windowStart: studyWeek.hkInstant(day(OPEN_DAY), 0),
    windowEnd: studyWeek.hkEndOfDay(day(CLOSE_DAY)),
    acceptUntil: studyWeek.hkEndOfDay(day(LAST_CARD_DAY)),
  };
}

/**
 * The three pushes, in order.  `all`: to everyone; otherwise only to
 * whoever has not submitted all five parts.  `field`: where
 * weekly_status.bundles.W8 records it.
 * @param {string} w0Key
 * @return {Array<{step: string, day: number, dateKey: string,
 *     field: string, kind: string, all: boolean}>}
 */
function stepsFor(w0Key) {
  const s = (step, day, field, kind, all) => ({step, day,
    dateKey: studyWeek.addDays(w0Key, day), field, kind, all});
  return [
    s("open", OPEN_DAY, "pushedAt", KIND_OPEN, true),
    s("remind1", REMIND1_DAY, "remind1SentAt", KIND_REMINDER, false),
    s("remind2", REMIND2_DAY, "remind2SentAt", KIND_REMINDER, false),
  ];
}

/**
 * Pushed and e-mailed: registered (RCT-, PB-, PILOT-), not a tester,
 * with a W0 date.
 * @param {?object} user users/{uid} data
 * @return {boolean}
 */
function isTarget(user) {
  return !!user && user.isTester !== true && studyPeriod.isEnrolled(user) &&
    studyWeek.w0DateKey(user) !== null;
}

/**
 * Was a moment outside the window [windowStart, windowEnd)?
 * @param {Date} at
 * @param {{windowStart: Date, windowEnd: Date}} dates
 * @return {boolean}
 */
function outOfWindowAt(at, dates) {
  return at < dates.windowStart || at >= dates.windowEnd;
}

// ---------------------------------------------------------------------------
// Part state and the whole-questionnaire summary (pure)
// ---------------------------------------------------------------------------

/**
 * @param {?object} data a part record
 * @return {?string} null (no record) | in_progress | submitted | declined
 *     (AIMHS only) | missed
 */
function partState(data) {
  if (!data) return null;
  const s = data.status;
  if (s === "submitted" || s === "declined" || s === "missed") return s;
  return "in_progress";
}

/**
 * @param {?object} data
 * @return {?Date} when the participant submitted the record
 */
function submittedAtOf(data) {
  if (!data) return null;
  return studyWeek.toDate(data.submittedAt) ||
    studyWeek.toDate(data.answeredAt);
}

/**
 * The whole-questionnaire status from the six records.  Completion only:
 * no answer, no score.
 * @param {Object<string, ?object>} docs part id → record data
 * @param {{windowStart: Date, windowEnd: Date}} dates
 * @return {{parts: Object<string, ?string>, partsSubmitted: number,
 *     completedAt: ?Date, completedOutOfWindow: ?boolean, aimhs: ?string,
 *     status: string}} status: completed | in_progress | not_started
 */
function summarize(docs, dates) {
  const parts = {};
  let submitted = 0;
  let started = false;
  let last = null;
  for (const p of PARTS) {
    const st = partState(docs[p.id]);
    parts[p.id] = st;
    if (st === "submitted") {
      submitted++;
      const at = submittedAtOf(docs[p.id]);
      if (at && (!last || at > last)) last = at;
    }
    if (st === "submitted" || st === "in_progress") started = true;
  }
  const done = submitted === PARTS.length;
  const completedAt = done ? last : null;
  return {
    parts,
    partsSubmitted: submitted,
    completedAt,
    completedOutOfWindow: completedAt ?
      outOfWindowAt(completedAt, dates) : null,
    aimhs: partState(docs[AIMHS.id]),
    status: done ? "completed" : (started ? "in_progress" : "not_started"),
  };
}

/**
 * The operations dashboard's W8 cell (completion only).
 * @param {?object} w8 weekly_status.bundles.W8
 * @param {number} studyDay today's study day
 * @return {string} not_yet | open | in_progress | late | done | missed
 */
function cellFor(w8, studyDay) {
  const s = w8 || {};
  if (s.completedAt) return "done";
  if (s.closedAt || studyDay > LAST_CARD_DAY) return "missed";
  if (studyDay < OPEN_DAY) return "not_yet";
  if (s.status === "in_progress") return "in_progress";
  return studyDay > CLOSE_DAY ? "late" : "open";
}

// ---------------------------------------------------------------------------
// Firestore: records, stamps, summary
// ---------------------------------------------------------------------------

/**
 * @param {object} userRef users/{uid}
 * @return {Promise<Object<string, ?object>>} part id → record data
 */
async function readParts(userRef) {
  const out = {};
  for (const p of ALL_PARTS) {
    const snap = await userRef.collection(p.collection).doc(BUNDLE_ID).get();
    out[p.id] = snap.exists ? (snap.data() || {}) : null;
  }
  return out;
}

/**
 * The fields every W8 record and the status carry.
 * @param {object} dates datesFor()
 * @return {object}
 */
function baseStamp(dates) {
  return {studyWeek: STUDY_WEEK, studyDay: OPEN_DAY,
    windowStart: dates.windowStart, windowEnd: dates.windowEnd,
    acceptUntil: dates.acceptUntil};
}

/**
 * Write the whole-questionnaire status for one participant
 * (weekly_status/{uid}.bundles.W8, merged).
 * @param {object} db
 * @param {string} uid
 * @param {string} w0Key
 * @param {Date} now
 * @param {?object} extra more W8 fields (push stamps, close)
 * @return {Promise<object>} the summary written
 */
async function refreshSummary(db, uid, w0Key, now, extra) {
  const dates = datesFor(w0Key);
  const userRef = db.collection("users").doc(uid);
  const summary = summarize(await readParts(userRef), dates);
  const statusRef = db.collection(weeklySchedule.STATUS_COLLECTION).doc(uid);
  const st = await statusRef.get();
  const rid = (st.exists && st.get("researchId")) ||
    await weeklySchedule.lookupResearchId(db, uid);
  const w8 = Object.assign({}, baseStamp(dates), summary,
      {summaryAt: now}, extra || {});
  await statusRef.set({uid, w0Date: w0Key, researchId: rid || null,
    updatedAt: now, bundles: {W8: w8}}, {merge: true});
  return w8;
}

/**
 * Trigger body (onW8PartWritten, users/{uid}/{collection}/W8): stamp the
 * server fields on a W8 record once, score it on submission, then update
 * the whole-questionnaire status.  Idempotent: a record already stamped
 * returns null and writes nothing.
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {string} collection
 * @param {string} docId
 * @param {?object} before record data before the write
 * @param {?object} after record data after the write
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<?object>} fields stamped (may be empty), or null when
 *     the record is not a W8 record or nothing changed
 */
async function stampW8Part(db, uid, collection, docId, before, after, opts) {
  const o = opts || {};
  if (docId !== BUNDLE_ID || !after) return null;
  const part = partByCollection(collection);
  if (!part || after.status === "missed") return null;
  const now = o.now || new Date();
  const userSnap = await db.collection("users").doc(uid).get();
  const w0Key = studyWeek.w0DateKey(userSnap.exists ? userSnap.data() : null);
  if (!w0Key) return null;
  const dates = datesFor(w0Key);
  const patch = {};
  if (after.studyWeek === undefined) Object.assign(patch, baseStamp(dates));
  if (after.status === "submitted") {
    if (typeof after.outOfWindow !== "boolean") {
      const at = submittedAtOf(after) || now;
      patch.submittedStudyDay = studyWeek.studyDayAt(w0Key, at);
      patch.outOfWindow = outOfWindowAt(at, dates);
    }
    if (part.score && !after.scoredAt) {
      patch.scores = part.score(after.answers);
      patch.scoringVersion = part.scoringVersion;
      patch.scoredAt = now;
    }
  }
  const stamped = Object.keys(patch).length > 0;
  if (stamped) {
    patch.stampedAt = now;
    await db.collection("users").doc(uid).collection(collection)
        .doc(BUNDLE_ID).set(patch, {merge: true});
  }
  const changed = !before || before.status !== after.status;
  if (!stamped && !changed) return null;
  await refreshSummary(db, uid, w0Key, now, null);
  return patch;
}

// ---------------------------------------------------------------------------
// Dispatcher (hourly 08:00–21:00 HKT, index.js w8Dispatch)
// ---------------------------------------------------------------------------

/**
 * One W8 push to every device of the participant.
 * @param {object} messaging
 * @param {object} userDoc
 * @param {string} kind
 * @return {Promise<{tokens: number, delivered: number}>}
 */
function sendPush(messaging, userDoc, kind) {
  return weeklySchedule.sendToDevices(messaging, userDoc, PUSH_BODY, kind);
}

/**
 * From day 71: a `missed` record for every part not submitted, and the
 * final status.  AIMHS is optional: never marked missed.
 * @param {object} db
 * @param {object} userDoc
 * @param {string} w0Key
 * @param {Date} now
 * @return {Promise<string[]>} parts marked missed
 */
async function closeFor(db, userDoc, w0Key, now) {
  const dates = datesFor(w0Key);
  const docs = await readParts(userDoc.ref);
  const missed = [];
  for (const p of PARTS) {
    if (partState(docs[p.id]) === "submitted") continue;
    const rec = Object.assign({bundle: BUNDLE_ID}, baseStamp(dates), {
      status: "missed", missed: true, missedAt: now, stampedAt: now,
    });
    if (p.collection !== "pgic") rec.timepoint = BUNDLE_ID;
    await userDoc.ref.collection(p.collection).doc(BUNDLE_ID)
        .set(rec, {merge: true});
    missed.push(p.id);
  }
  const w8 = await refreshSummary(db, userDoc.id, w0Key, now,
      {closedAt: now, missedParts: missed});
  await userDoc.ref.collection("events").add({
    name: "w8_closed",
    params: {bundle: BUNDLE_ID, parts: missed, status: w8.status},
    source: "cf_w8Dispatch",
    timestamp: now,
  });
  return missed;
}

/**
 * Hourly job: the day-56 push to everyone, the day-58 / day-60 reminders
 * to whoever has not finished, from day 71 the missed marks.  Pushes go
 * at the first run at or after weeklyPushHour on their day, once (the
 * time is stamped in weekly_status.bundles.W8).  No switch, no quiet
 * hours, no arm check.
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     pushHour: (number|undefined)}} opts pushHour overrides
 *     app_config/phase_b.weeklyPushHour (tests only)
 * @return {Promise<object>} counts per outcome
 */
async function dispatchW8(db, messaging, opts) {
  const o = opts || {};
  const now = o.now || new Date();
  const log = o.log || console.log;
  const pushHour = typeof o.pushHour === "number" ? o.pushHour :
    (await weeklySchedule.readConfig(db)).pushHour;
  const counts = {};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  const todayKey = studyWeek.hkDateKey(now);
  const hour = studyWeek.hkHour(now);
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (!isTarget(u)) continue;
    const w0Key = studyWeek.w0DateKey(u);
    const day = studyWeek.studyDayOf(w0Key, todayKey);
    if (day < OPEN_DAY) continue;
    const dates = datesFor(w0Key);
    // Long past (closed and a week on): nothing left to do, no read.
    if (now.getTime() > dates.acceptUntil.getTime() + CLOSE_LOOKBACK_MS) {
      continue;
    }
    try {
      const statusSnap = await db.collection(weeklySchedule.STATUS_COLLECTION)
          .doc(userDoc.id).get();
      const w8 = ((statusSnap.exists ? statusSnap.get("bundles") : null) ||
        {})[BUNDLE_ID] || {};
      if (now >= dates.acceptUntil) {
        if (w8.closedAt ||
            now.getTime() > dates.acceptUntil.getTime() + CLOSE_LOOKBACK_MS) {
          continue;
        }
        const missed = await closeFor(db, userDoc, w0Key, now);
        bump(missed.length > 0 ? "closed_missed" : "closed_complete");
        continue;
      }
      const step = stepsFor(w0Key).filter((s) => s.dateKey === todayKey)[0];
      if (!step || hour < pushHour || w8[step.field]) continue;
      let open = null;
      if (!step.all) {
        const docs = await readParts(userDoc.ref);
        open = PARTS.filter((p) => partState(docs[p.id]) !== "submitted")
            .map((p) => p.id);
        if (open.length === 0) {
          bump("done_no_reminder");
          continue;
        }
      }
      const res = await sendPush(messaging, userDoc, step.kind);
      const extra = {};
      extra[step.field] = now;
      await refreshSummary(db, userDoc.id, w0Key, now, extra);
      const params = {bundle: BUNDLE_ID, step: step.step, studyDay: day,
        dateKey: todayKey, tokens: res.tokens, delivered: res.delivered};
      if (open) params.parts = open;
      await userDoc.ref.collection("events").add({
        name: `${step.kind}_sent`,
        params,
        source: "cf_w8Dispatch",
        timestamp: now,
      });
      bump(step.step === "open" ? "pushed" : "reminded");
    } catch (err) {
      bump("error");
      log(`w8Dispatch ${userDoc.id} failed: ${err.message}`);
    }
  }
  log(`dispatchW8: ${JSON.stringify(counts)}`);
  return counts;
}

// ---------------------------------------------------------------------------
// The research lead's e-mail on day 60 (handover 一 (4))
// ---------------------------------------------------------------------------

/**
 * Participants on study day 60 today who have not submitted all five
 * parts.  Read only.  Research ID and study day only.
 * @param {object} db
 * @param {Date} now
 * @return {Promise<Array<{researchId: ?string, studyDay: number}>>}
 *     sorted by research ID
 */
async function incompleteToday(db, now) {
  const todayKey = studyWeek.hkDateKey(now);
  const rows = [];
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (!isTarget(u)) continue;
    const w0Key = studyWeek.w0DateKey(u);
    const day = studyWeek.studyDayOf(w0Key, todayKey);
    if (day !== EMAIL_DAY) continue;
    const docs = await readParts(userDoc.ref);
    if (PARTS.every((p) => partState(docs[p.id]) === "submitted")) continue;
    rows.push({
      researchId: await weeklySchedule.lookupResearchId(db, userDoc.id),
      studyDay: day,
    });
  }
  rows.sort((a, b) => String(a.researchId || "~")
      .localeCompare(String(b.researchId || "~")));
  return rows;
}

/**
 * The e-mail.  One line per person: research ID and study day.  Never the
 * arm, the cohort label or an answer.
 * @param {Array<{researchId: ?string, studyDay: number}>} rows
 * @param {Date} now
 * @param {number} pushHour
 * @return {{subject: string, text: string}}
 */
function buildEmail(rows, now, pushHour) {
  const dateKey = studyWeek.hkDateKey(now);
  const weekday = WEEKDAY_ZH[new Date(now.getTime() + 8 * 3600 * 1000)
      .getUTCDay()];
  const hh = String(pushHour).padStart(2, "0");
  const lines = [
    `${dateKey}（星期${weekday}）${hh}:00，以下研究编号的最后一份问卷（W8）` +
      "还没有做完五个部分。今天是他们的研究第 60 天：窗口第 63 天 23:59 关，" +
      "之后到第 70 天仍可以补答（记超窗）。",
    "",
    "研究编号 ｜ 研究第几天",
  ];
  for (const r of rows) {
    lines.push(`${r.researchId || "（研究编号缺失）"} ｜ 第 ${r.studyDay} 天`);
  }
  lines.push("", `共 ${rows.length} 人。`, "",
      "本邮件不含组别、cohort 和任何答案。PILOT-、PB-（run-in）、" +
      "RCT- 由编号前缀区分。",
      "自动邮件，请勿回复。");
  return {subject: EMAIL_SUBJECT, text: lines.join("\n")};
}

/**
 * The recipients the safety alert uses (meta/alert_config.primaryEmail;
 * a `blinded` address is dropped; without one, the PI_EMAIL secret).
 * @param {object} db
 * @param {object} auth
 * @param {{piEmail: string}} smtp
 * @param {Date} now
 * @param {string} auditId
 * @return {Promise<Array<string>>}
 */
async function recipients(db, auth, smtp, now, auditId) {
  const cfg = await piAlert.readAlertConfig(db);
  const candidates = [cfg.primaryEmail];
  if (!cfg.primaryEmail) {
    candidates.push(smtp.piEmail);
    await piAlert.audit(db, {type: "primary_missing_fallback_secret",
      alertId: auditId}, now);
  }
  const r = await piAlert.resolveRecipients(auth, candidates);
  for (const x of r.dropped) {
    await piAlert.audit(db, {type: "recipient_dropped", alertId: auditId,
      email: x.email, reason: x.reason, stage: "w8_incomplete"}, now);
  }
  return r.to;
}

/**
 * Run after each dispatch: from weeklyPushHour on, once per Hong Kong day
 * (alert_audit_log/w8_incomplete_<date>, claimed in a transaction), the
 * list of day-60 participants still not done, if there is anyone.
 * Nobody on day 60 still open → nothing is written or sent.
 * @param {object} db
 * @param {{now: (Date|undefined), smtp: ?object, auth: object,
 *     pushHour: (number|undefined)}} deps
 * @return {Promise<{status: string, count: number}>} status: not_yet |
 *     none | already_done | sent | no_smtp | no_recipients | failed
 */
async function sendIncompleteEmail(db, deps) {
  const d = deps || {};
  const now = d.now || new Date();
  const pushHour = typeof d.pushHour === "number" ? d.pushHour :
    (await weeklySchedule.readConfig(db)).pushHour;
  if (studyWeek.hkHour(now) < pushHour) return {status: "not_yet", count: 0};
  const dateKey = studyWeek.hkDateKey(now);
  const auditId = AUDIT_PREFIX + dateKey;
  const ref = db.collection(piAlert.AUDIT_LOG).doc(auditId);
  const prior = await ref.get();
  const priorStatus = prior.exists ? prior.get("status") : null;
  const retry = ["failed", "no_smtp", "no_recipients"];
  if (priorStatus && retry.indexOf(priorStatus) < 0) {
    return {status: "already_done", count: 0};
  }
  const rows = await incompleteToday(db, now);
  if (rows.length === 0) return {status: "none", count: 0};
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const s = snap.exists ? (snap.data() || {}).status : null;
    if (s && retry.indexOf(s) < 0) return false;
    tx.set(ref, {type: "w8_incomplete_email", dateKey, status: "running",
      at: now}, {merge: true});
    return true;
  });
  if (!claimed) return {status: "already_done", count: 0};
  const finish = async (status, extra) => {
    await ref.set(Object.assign({status, finishedAt: now}, extra || {}),
        {merge: true});
    return Object.assign({status}, extra || {});
  };
  if (!d.smtp) return finish("no_smtp", {count: rows.length});
  const to = await recipients(db, d.auth, d.smtp, now, auditId);
  if (to.length === 0) return finish("no_recipients", {count: rows.length});
  const mail = buildEmail(rows, now, pushHour);
  try {
    await piAlert.sendMail(d.smtp, {to, subject: mail.subject,
      text: mail.text});
  } catch (err) {
    console.error("W8 incomplete e-mail failed:", err && err.message);
    return finish("failed", {count: rows.length, to,
      error: String(err && err.message)});
  }
  return finish("sent", {count: rows.length, to});
}

module.exports = {
  BUNDLE_ID, STUDY_WEEK, OPEN_DAY, CLOSE_DAY, LAST_CARD_DAY, REMIND1_DAY,
  REMIND2_DAY, EMAIL_DAY, PUSH_TITLE, PUSH_BODY, KIND_OPEN, KIND_REMINDER,
  EMAIL_SUBJECT, AUDIT_PREFIX, PARTS, AIMHS, ALL_PARTS, NEW_COLLECTIONS,
  SERVER_ONLY_FIELDS,
  scoreUcla3, scoreLsns6, partByCollection, datesFor, stepsFor, isTarget,
  outOfWindowAt, partState, submittedAtOf, summarize, cellFor, readParts,
  refreshSummary, stampW8Part, closeFor, dispatchW8, incompleteToday,
  buildEmail, sendIncompleteEmail,
};

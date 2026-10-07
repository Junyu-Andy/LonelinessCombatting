/**
 * T17b — Phase A ADA day-7 flow on the server (SPEC:C22, decision 0030;
 * docs/spec/instruments/ada.md §5–7).  Phase A only, no LLM.
 *
 * Data the App writes (owner only, firestore.rules):
 *   users/{uid}/ada_responses/{timepoint}       visit1 (short) / day7 (full)
 *   users/{uid}/day7_open_responses/day7        open questions
 * The visit-1 document carries day7ReminderTime ("HH:00", chosen at the
 * end of visit 1).
 *
 * Server only:
 *   ada_status/{uid}   researchId (copied from research_id_map — the
 *                      response documents stay ID-free, decision 0021),
 *                      day-7 status, push / reminder / overdue times.
 *                      No client reads or writes it.
 *
 * Config: app_config/phaseA_schedule (same document the App reads).
 *   adaEnabled / day7OpenEndedEnabled   parts of the day-7 flow
 *   adaTimepoints[id == "day7"]         window (default days 7–9)
 *   adaDay7ReminderDefaultTime          "10:00"
 *   adaDay7ReminderHours                24
 *
 * Day counting is the App's: W0 (account creation) is day 1
 * (djg_w2.w0DateKey; T19 replaces it).
 */

"use strict";

const crypto = require("crypto");
const djg = require("./djg_w2");
const lexicon = require("./safety_lexicon");

const CONFIG_DOC = "app_config/phaseA_schedule";
const STATUS_COLLECTION = "ada_status";
const ADA_COLLECTION = "ada_responses";
const OPEN_COLLECTION = "day7_open_responses";
const DAY7 = "day7";
const VISIT1 = "visit1";
const CHANNEL_APP = "app";
const CHANNEL_PHONE = "phone_by_staff";

const STATUS = {
  notStarted: "not_started",
  inProgress: "in_progress",
  completed: "completed",
  overdue: "overdue",
};

const DEFAULTS = {
  adaEnabled: false,
  openEnabled: false,
  dayFrom: 7,
  dayTo: 9,
  reminderTime: "10:00",
  reminderHours: 24,
};

// Overdue is stamped only in the first days after the window closes, so
// switching the flow on late does not mark everyone enrolled long ago.
const OVERDUE_LOOKBACK_DAYS = 7;
const REMINDER_SLACK_MS = 5 * 60 * 1000;

// Draft copy.  While it carries the placeholder mark nothing is sent.
const PUSH_TITLE = "陪住";
const PUSH_BODY = "【占位】第 7 日問卷開咗，得閒入嚟做。可以分幾次做。";
const REMINDER_BODY = "【占位】第 7 日問卷仲未做完，得閒入嚟做埋佢。";

const STAFF_ROLES = ["researcher", "pi"];

// Fields a researcher's phone completion may carry (same as the App's).
const STAFF_DATA_KEYS = {
  ada_responses: [
    "schemaVersion", "instrument", "studyPhase", "formVersion",
    "itemsVersion", "allowSkip", "ahJanAhBakVariant", "enrolmentDay",
    "screenCount", "lastScreen", "usage", "traits", "scenarios", "freeText",
    "freeTextStatus", "freeTextInputMode", "freeTextVoiceMs", "status",
    "startedAt",
  ],
  day7_open_responses: [
    "schemaVersion", "instrument", "studyPhase", "itemsVersion", "allowSkip",
    "enrolmentDay", "lastScreen", "answers", "status", "startedAt",
  ],
};

/**
 * "HH:00" between 08:00 and 21:00 → hour; anything else → null.  Mirrors
 * PhaseAScheduleConfig.validReminderTime in the App.
 * @param {*} v
 * @return {?number}
 */
function parseReminderTime(v) {
  if (typeof v !== "string") return null;
  const m = /^([01]\d|2[0-3]):00$/.exec(v);
  if (!m) return null;
  const h = parseInt(m[1], 10);
  return h >= 8 && h <= 21 ? h : null;
}

/**
 * @param {object} data app_config/phaseA_schedule fields
 * @return {object} merged config
 */
function configFromData(data) {
  const d = data || {};
  const num = (v, def, min) =>
    (typeof v === "number" && isFinite(v) && v >= min ? Math.floor(v) : def);
  const cfg = {
    adaEnabled: d.adaEnabled === true,
    openEnabled: d.day7OpenEndedEnabled === true,
    dayFrom: num(d.day7OpenEndedDayFrom, DEFAULTS.dayFrom, 1),
    dayTo: num(d.day7OpenEndedDayTo, DEFAULTS.dayTo, 1),
    hasDay7Timepoint: false,
    reminderTime: parseReminderTime(d.adaDay7ReminderDefaultTime) === null ?
      DEFAULTS.reminderTime : d.adaDay7ReminderDefaultTime,
    reminderHours: num(d.adaDay7ReminderHours, DEFAULTS.reminderHours, 1),
  };
  const tps = Array.isArray(d.adaTimepoints) ? d.adaTimepoints : null;
  if (tps === null) {
    cfg.hasDay7Timepoint = true; // App default list holds day7 7–9
  } else {
    for (const t of tps) {
      if (t && t.id === DAY7 && typeof t.dayFrom === "number" &&
          typeof t.dayTo === "number") {
        cfg.hasDay7Timepoint = true;
        cfg.dayFrom = Math.floor(t.dayFrom);
        cfg.dayTo = Math.floor(t.dayTo);
        break;
      }
    }
  }
  return cfg;
}

/**
 * @param {object} db
 * @return {Promise<object>} configFromData() result; defaults (off) on error
 */
async function readConfig(db) {
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFromData(snap.exists ? snap.data() : {});
  } catch (err) {
    console.warn("phaseA_schedule read failed; ADA day 7 off",
        {err: err && err.message});
    return configFromData({});
  }
}

/**
 * Parts of the day-7 flow (same rule as AdaGate.day7Parts in the App).
 * @param {object} cfg
 * @return {Array<string>} "ada" and / or "open"
 */
function day7Parts(cfg) {
  const out = [];
  if (cfg.adaEnabled && cfg.hasDay7Timepoint) out.push("ada");
  if (cfg.openEnabled) out.push("open");
  return out;
}

/**
 * Phase A participant?  cohort "phase_a"; before cohort exists (decision
 * 0011 not implemented yet) anyone who is not Phase B and not pilot.
 * T21 replaces this with the participant's study-phase field.
 * @param {object} u users/{uid} data
 * @return {boolean}
 */
function isPhaseAParticipant(u) {
  if (!u) return false;
  if (typeof u.cohort === "string") return u.cohort === "phase_a";
  return !djg.isPhaseBParticipant(u) && u.armAssignmentMode !== "randomise";
}

/**
 * Day-7 status from the part documents (ada.md §6.7).
 * @param {Array<string>} parts day7Parts()
 * @param {{ada: ?object, open: ?object}} docs
 * @param {?number} day enrolment day today (null = unknown)
 * @param {object} cfg
 * @return {{status: string, partial: boolean, channel: ?string}}
 */
function day7Status(parts, docs, day, cfg) {
  const list = parts.map((p) => (p === "ada" ? docs.ada : docs.open));
  const submitted = list.filter((d) => d && d.status === "submitted");
  const started = list.filter((d) => d && (d.status === "submitted" ||
    d.status === "in_progress"));
  if (parts.length > 0 && submitted.length === parts.length) {
    const phone = submitted.some((d) => d.channel === CHANNEL_PHONE);
    return {status: STATUS.completed, partial: false,
      channel: phone ? CHANNEL_PHONE : CHANNEL_APP};
  }
  const partial = started.length > 0;
  if (typeof day === "number" && day > cfg.dayTo) {
    return {status: STATUS.overdue, partial, channel: null};
  }
  return {status: partial ? STATUS.inProgress : STATUS.notStarted,
    partial: false, channel: null};
}

/**
 * @param {object} userRef users/{uid} DocumentReference
 * @return {Promise<{ada: ?object, open: ?object, visit1: ?object}>}
 */
async function readDocs(userRef) {
  const [ada, open, visit1] = await Promise.all([
    userRef.collection(ADA_COLLECTION).doc(DAY7).get(),
    userRef.collection(OPEN_COLLECTION).doc(DAY7).get(),
    userRef.collection(ADA_COLLECTION).doc(VISIT1).get(),
  ]);
  const data = (s) => (s.exists ? (s.data() || {}) : null);
  return {ada: data(ada), open: data(open), visit1: data(visit1)};
}

/**
 * Research ID from research_id_map (read only — never created here;
 * T12 / T19 issue them).
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?string>}
 */
async function lookupResearchId(db, uid) {
  try {
    const snap = await db.collection("research_id_map").doc(uid).get();
    const rid = snap.exists ? snap.get("researchId") : null;
    return typeof rid === "string" && rid.length > 0 ? rid : null;
  } catch (err) {
    return null;
  }
}

/**
 * Enrolment day today for [u], or null.
 * @param {object} u
 * @param {Date} now
 * @return {?number}
 */
function enrolmentDay(u, now) {
  const w0 = djg.w0DateKey(u);
  if (!w0) return null;
  return djg.daysBetween(w0, djg.hkDateKey(now)) + 1;
}

/**
 * Hour (HKT) the participant's day-7 push goes out.
 * @param {?object} visit1 visit-1 ADA doc
 * @param {object} cfg
 * @return {number}
 */
function pushHourFor(visit1, cfg) {
  const chosen = visit1 ? parseReminderTime(visit1.day7ReminderTime) : null;
  return chosen === null ? parseReminderTime(cfg.reminderTime) : chosen;
}

/**
 * Recompute ada_status/{uid} (status, research ID).  Called by the
 * response trigger and the hourly job.
 * @param {object} db
 * @param {string} uid
 * @param {{now: (Date|undefined), cfg: (object|undefined)}} opts
 * @return {Promise<?object>} the fields written
 */
async function refreshStatus(db, uid, opts = {}) {
  const now = opts.now || new Date();
  const cfg = opts.cfg || await readConfig(db);
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return null;
  const u = userSnap.data() || {};
  if (!isPhaseAParticipant(u)) return null;
  const docs = await readDocs(userRef);
  const day = enrolmentDay(u, now);
  const st = day7Status(day7Parts(cfg), docs, day, cfg);
  const statusRef = db.collection(STATUS_COLLECTION).doc(uid);
  const prev = await statusRef.get();
  const p = prev.exists ? (prev.data() || {}) : {};
  const out = {
    uid,
    studyPhase: "A",
    researchId: p.researchId || await lookupResearchId(db, uid),
    day7Status: st.status,
    day7Partial: st.partial,
    day7Channel: st.channel,
    visit1Status: docs.visit1 ? (docs.visit1.status || null) : null,
    visit1Channel: docs.visit1 ? (docs.visit1.channel || CHANNEL_APP) : null,
    day7ReminderTime: docs.visit1 &&
      parseReminderTime(docs.visit1.day7ReminderTime) !== null ?
      docs.visit1.day7ReminderTime : null,
    updatedAt: now,
  };
  if (st.status === STATUS.completed && !p.day7CompletedAt) {
    out.day7CompletedAt = now;
  }
  await statusRef.set(out, {merge: true});
  return out;
}

/**
 * @param {object} messaging
 * @param {object} userDoc
 * @param {string} body
 * @param {string} kind
 * @return {Promise<{tokens: number, delivered: number}>}
 */
async function sendToDevices(messaging, userDoc, body, kind) {
  const tokensSnap = await userDoc.ref.collection("fcm_tokens").get();
  const tokens = tokensSnap.docs
      .map((t) => (t.data() || {}).token)
      .filter((t) => typeof t === "string" && t.length > 0);
  let delivered = 0;
  for (const token of tokens) {
    try {
      await messaging.send({
        token,
        notification: {title: PUSH_TITLE, body},
        android: {priority: "normal"},
        data: {kind},
      });
      delivered++;
    } catch (err) {
      console.warn(`adaDay7 ${kind} send failed for ${userDoc.id}: ` +
        `${err.code || err.message}`);
    }
  }
  return {tokens: tokens.length, delivered};
}

/**
 * Hourly job (ada.md §6.1): the day-7 push at the chosen hour, one more
 * after adaDay7ReminderHours if the flow is not completed, and the
 * overdue mark once the window has closed.  Safe with the switches off.
 * @param {object} db
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     copy: (object|undefined)}} opts copy overrides the draft text
 *     (tests only)
 * @return {Promise<object>} counts per outcome
 */
async function dispatchAdaDay7(db, messaging, opts = {}) {
  const now = opts.now || new Date();
  const log = opts.log || console.log;
  const copy = Object.assign({push: PUSH_BODY, reminder: REMINDER_BODY},
      opts.copy || {});
  const cfg = await readConfig(db);
  const parts = day7Parts(cfg);
  const counts = {enabled: parts.length > 0};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  if (parts.length === 0) return counts;

  const hour = djg.hkHour(now);
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (u.isTester === true || !isPhaseAParticipant(u)) continue;
    const day = enrolmentDay(u, now);
    if (day === null || day < cfg.dayFrom) continue;
    if (day > cfg.dayTo + OVERDUE_LOOKBACK_DAYS) continue;
    try {
      const docs = await readDocs(userDoc.ref);
      const st = day7Status(parts, docs, day, cfg);
      const statusRef = db.collection(STATUS_COLLECTION).doc(userDoc.id);
      const prevSnap = await statusRef.get();
      const p = prevSnap.exists ? (prevSnap.data() || {}) : {};
      const base = {
        uid: userDoc.id, studyPhase: "A",
        researchId: p.researchId || await lookupResearchId(db, userDoc.id),
        day7Status: st.status, day7Partial: st.partial,
        day7Channel: st.channel, updatedAt: now,
      };
      if (st.status === STATUS.completed && !p.day7CompletedAt) {
        base.day7CompletedAt = now;
      }
      await statusRef.set(base, {merge: true});
      if (st.status === STATUS.completed) {
        bump("completed");
        continue;
      }
      if (st.status === STATUS.overdue) {
        if (!p.day7OverdueAt) {
          await statusRef.set({day7OverdueAt: now}, {merge: true});
          await userDoc.ref.collection("events").add({
            name: "ada_day7_overdue",
            params: {enrolmentDay: day, partial: st.partial},
            source: "cf_adaDay7Dispatch",
            timestamp: now,
          });
          bump("overdue");
        }
        continue;
      }

      if (!p.day7PushSentAt) {
        if (hour < pushHourFor(docs.visit1, cfg)) continue;
        if (djg.isPlaceholder(copy.push)) {
          bump("blocked_placeholder");
          continue;
        }
        const res = await sendToDevices(messaging, userDoc, copy.push,
            "ada_day7_push");
        await statusRef.set({day7PushSentAt: now}, {merge: true});
        await userDoc.ref.collection("events").add({
          name: "ada_day7_push_sent",
          params: {enrolmentDay: day, tokens: res.tokens,
            delivered: res.delivered},
          source: "cf_adaDay7Dispatch",
          timestamp: now,
        });
        bump("pushed");
        continue;
      }

      if (p.day7ReminderSentAt) continue;
      const pushedAt = typeof p.day7PushSentAt.toDate === "function" ?
        p.day7PushSentAt.toDate() : new Date(p.day7PushSentAt);
      const due = pushedAt.getTime() + cfg.reminderHours * 3600 * 1000 -
        REMINDER_SLACK_MS;
      if (now.getTime() < due) continue;
      if (djg.isPlaceholder(copy.reminder)) {
        bump("blocked_placeholder");
        continue;
      }
      const res = await sendToDevices(messaging, userDoc, copy.reminder,
          "ada_day7_reminder");
      await statusRef.set({day7ReminderSentAt: now}, {merge: true});
      await userDoc.ref.collection("events").add({
        name: "ada_day7_reminder_sent",
        params: {enrolmentDay: day, tokens: res.tokens,
          delivered: res.delivered},
        source: "cf_adaDay7Dispatch",
        timestamp: now,
      });
      bump("reminded");
    } catch (err) {
      bump("error");
      log(`adaDay7 ${userDoc.id} failed: ${err.message}`);
    }
  }
  log(`dispatchAdaDay7: ${JSON.stringify(counts)}`);
  return counts;
}

// ---------------------------------------------------------------------------
// Staff (ada.md §6.6–6.7).  Every call checks the Auth role.
// ---------------------------------------------------------------------------

/**
 * Error with an HttpsError-style code (index.js maps it).
 * @param {string} code
 * @param {string} message
 * @return {Error}
 */
function staffError(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

/**
 * @param {?object} auth request.auth
 * @return {string} the role
 */
function assertStaff(auth) {
  const role = auth && auth.token ? auth.token.role : null;
  if (!auth || STAFF_ROLES.indexOf(role) < 0) {
    throw staffError("permission-denied", "researcher role required");
  }
  return role;
}

/**
 * @param {*} v Timestamp | Date | null
 * @return {?string} "YYYY-MM-DD HH:MM" Hong Kong
 */
function hkStamp(v) {
  if (!v) return null;
  const d = typeof v.toDate === "function" ? v.toDate() : new Date(v);
  if (isNaN(d.getTime())) return null;
  return d.toLocaleString("sv-SE", {timeZone: "Asia/Hong_Kong"}).slice(0, 16);
}

/**
 * Rows for the researcher page: every Phase A participant's day-7 status.
 * Research IDs only for the unblinded role (as research_id_map's rule).
 * @param {object} db
 * @param {?object} auth
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<{rows: Array<object>, parts: Array<string>}>}
 */
async function staffDay7Status(db, auth, opts = {}) {
  const role = assertStaff(auth);
  const now = opts.now || new Date();
  const cfg = await readConfig(db);
  const parts = day7Parts(cfg);
  const users = await db.collection("users").get();
  const rows = [];
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (!isPhaseAParticipant(u)) continue;
    const day = enrolmentDay(u, now);
    const docs = await readDocs(userDoc.ref);
    const st = day7Status(parts, docs, day, cfg);
    const s = await db.collection(STATUS_COLLECTION).doc(userDoc.id).get();
    const p = s.exists ? (s.data() || {}) : {};
    const rid = role === "pi" ?
      (p.researchId || await lookupResearchId(db, userDoc.id)) : null;
    rows.push({
      uid: userDoc.id,
      label: (typeof u.displayName === "string" && u.displayName) ?
        `${u.displayName} · ${userDoc.id.slice(0, 6)}` :
        userDoc.id.slice(0, 6),
      researchId: rid,
      enrolmentDay: day,
      status: st.status,
      partial: st.partial,
      channel: st.channel,
      pushSentAt: hkStamp(p.day7PushSentAt),
      reminderSentAt: hkStamp(p.day7ReminderSentAt),
      ahJanAhBakVariant: typeof u.ahJanAhBakVariant === "string" ?
        u.ahJanAhBakVariant : null,
      isTester: u.isTester === true,
    });
  }
  const order = {overdue: 0, in_progress: 1, not_started: 2, completed: 3};
  rows.sort((a, b) => order[a.status] - order[b.status] ||
    (b.enrolmentDay || 0) - (a.enrolmentDay || 0));
  return {rows, parts};
}

/**
 * @param {object} data {uid, collection, docId}
 * @return {{uid: string, collection: string, docId: string}}
 */
function staffTarget(data) {
  const d = data || {};
  if (typeof d.uid !== "string" || !d.uid || d.uid.indexOf("/") >= 0) {
    throw staffError("invalid-argument", "uid");
  }
  if (!Object.prototype.hasOwnProperty.call(STAFF_DATA_KEYS, d.collection)) {
    throw staffError("invalid-argument", "collection");
  }
  // Phone completion is the day-7 follow-up (ada.md §6.6).
  if (d.docId !== DAY7) throw staffError("invalid-argument", "docId");
  return {uid: d.uid, collection: d.collection, docId: d.docId};
}

/**
 * Plain JSON copy (Timestamps → ISO strings) for the callable reply.
 * @param {*} v
 * @return {*}
 */
function plainJson(v) {
  if (v === null || v === undefined) return null;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  if (Array.isArray(v)) return v.map(plainJson);
  if (typeof v === "object") {
    const out = {};
    for (const k of Object.keys(v)) out[k] = plainJson(v[k]);
    return out;
  }
  return v;
}

/**
 * @param {object} db
 * @param {?object} auth
 * @param {object} data {uid, collection, docId}
 * @return {Promise<{doc: ?object}>}
 */
async function staffLoad(db, auth, data) {
  assertStaff(auth);
  const t = staffTarget(data);
  const snap = await db.collection("users").doc(t.uid)
      .collection(t.collection).doc(t.docId).get();
  return {doc: snap.exists ? plainJson(snap.data()) : null};
}

/**
 * Free texts in a response, keyed by input point / question.
 * @param {string} collection
 * @param {?object} d
 * @return {Object<string, string>}
 */
function freeTexts(collection, d) {
  const out = {};
  if (!d) return out;
  if (collection === ADA_COLLECTION) {
    if (typeof d.freeText === "string" && d.freeText.trim()) {
      out.ada_free_text = d.freeText.trim();
    }
    return out;
  }
  const answers = d.answers && typeof d.answers === "object" ? d.answers : {};
  for (const q of Object.keys(answers)) {
    const a = answers[q];
    if (a && typeof a.text === "string" && a.text.trim()) {
      out[`day7_open_ended:${q}`] = a.text.trim();
    }
  }
  return out;
}

/**
 * Researcher saves a phone completion.  The server sets the channel, the
 * staff uid, the owner fields and the times; refuses a submitted
 * document; scans any new free text with the App's lexicon and writes a
 * safety_events row exactly like the App does (the onSafetyEventCreated
 * trigger then dedups and alerts the PI for acute).
 * @param {object} db
 * @param {?object} auth
 * @param {object} data {uid, collection, docId, data}
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<{ok: boolean, safetyEscalation: boolean}>}
 */
async function staffSave(db, auth, data, opts = {}) {
  assertStaff(auth);
  const now = opts.now || new Date();
  const t = staffTarget(data);
  const payload = data && data.data && typeof data.data === "object" ?
    data.data : null;
  if (!payload) throw staffError("invalid-argument", "data");
  const status = payload.status;
  if (status !== "in_progress" && status !== "submitted") {
    throw staffError("invalid-argument", "status");
  }
  const userRef = db.collection("users").doc(t.uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists || !isPhaseAParticipant(userSnap.data())) {
    throw staffError("failed-precondition", "not a Phase A participant");
  }
  const ref = userRef.collection(t.collection).doc(t.docId);
  const prevSnap = await ref.get();
  const prev = prevSnap.exists ? (prevSnap.data() || {}) : null;
  if (prev && prev.status === "submitted") {
    throw staffError("failed-precondition", "already submitted");
  }
  const clean = {};
  for (const k of STAFF_DATA_KEYS[t.collection]) {
    if (Object.prototype.hasOwnProperty.call(payload, k)) clean[k] = payload[k];
  }
  delete clean.startedAt;
  const doc = Object.assign(clean, {
    uid: t.uid,
    timepoint: t.docId,
    channel: CHANNEL_PHONE,
    staffUid: auth.uid,
    updatedAt: now,
  });
  if (!prev || !prev.startedAt) {
    const s = payload.startedAt ? new Date(payload.startedAt) : now;
    doc.startedAt = isNaN(s.getTime()) ? now : s;
  }
  if (!prev || !prev.staffStartedAt) doc.staffStartedAt = now;
  if (status === "submitted") doc.submittedAt = now;
  await ref.set(doc, {merge: true});

  // Safety (ada.md §7): new or changed free text only.
  const before = freeTexts(t.collection, prev);
  const after = freeTexts(t.collection, Object.assign({}, prev || {}, doc));
  let escalation = false;
  for (const key of Object.keys(after)) {
    if (before[key] === after[key]) continue;
    const m = lexicon.analyze(after[key]);
    if (!lexicon.isEscalation(after[key])) continue;
    escalation = true;
    const inputPoint = key.split(":")[0];
    await db.collection("safety_events").add({
      uid: t.uid,
      source: "form",
      inputPoint,
      turnId: `staff-${t.docId}-${key}-${now.getTime()}`,
      textHash: crypto.createHash("sha256").update(after[key], "utf8")
          .digest("hex"),
      level: m.tier === "moderate_review" || m.tier === "moderate_interrupt" ?
        "moderate" : m.tier,
      tier: m.tier,
      category: m.category,
      lexiconVersion: lexicon.WORDLIST_VERSION,
      matchedTerm: m.term,
      channel: CHANNEL_PHONE,
      enteredByStaffUid: auth.uid,
      createdAt: now,
    });
  }
  await refreshStatus(db, t.uid, {now});
  return {ok: true, safetyEscalation: escalation};
}

module.exports = {
  CONFIG_DOC, STATUS_COLLECTION, ADA_COLLECTION, OPEN_COLLECTION, DAY7,
  VISIT1, CHANNEL_APP, CHANNEL_PHONE, STATUS, DEFAULTS, PUSH_TITLE,
  PUSH_BODY, REMINDER_BODY, STAFF_ROLES, STAFF_DATA_KEYS,
  OVERDUE_LOOKBACK_DAYS,
  parseReminderTime, configFromData, readConfig, day7Parts,
  isPhaseAParticipant, day7Status, enrolmentDay, pushHourFor,
  lookupResearchId, refreshStatus, dispatchAdaDay7, assertStaff,
  staffDay7Status, staffLoad, staffSave, freeTexts,
};

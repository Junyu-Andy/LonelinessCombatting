/**
 * T19 (decision 0029) — Phase B enrolment and arm allocation.
 *
 * Replaces the minimisation in arm.js.  The unblinded researcher (role
 * "unblinded", tool/provision_researcher.js) registers a participant whose
 * account already exists: research ID, W0 paper DJG emotional subscale
 * (0–3) and the Ah Jan / Ah Bak pairing.  In one transaction the server
 *   - takes the stratum's next unused position of a pre-generated
 *     permuted-block sequence (1:1, blocks of 2 and 4 mixed at random);
 *   - writes the arm (write-once), the stratum, the W0 date and the
 *     pairing to users/{uid};
 *   - writes the enrolment record, the research-ID lookup and one row of
 *     the allocation log (research ID, stratum, position, time, who).
 *
 * Strata: emotional 0–1 = "low", 2–3 = "high".
 *
 * Collections (firestore.rules: no client reads or writes):
 *   randomization_sequences/{low|high}  arms[], blocks[], length, sha256
 *   randomization_state/{low|high}      next (0-based index of next unused)
 *   enrollments/{uid}                   the registration record
 *   arm_assignment_log/{auto}           allocation / resubmit / correction
 *   meta/randomization_config           {enabled} — off by default
 *
 * Sequences are generated offline by the unblinded researcher with her own
 * seed (tool/randomization_sequence.js); the seed never reaches Firestore
 * or the repository.
 *
 * T21 (registry v8 C01, dev-tasks-1010b): the research-ID prefix decides
 * the study period (functions/study_period.js).  "PB-…" takes the path
 * above and is marked cohort "phase_b".  "PILOT-…" is the pilot run: no
 * W0 score, no sequence; the researcher picks the version (Arm A Hybrid or
 * Arm B rule-based) on the registration page, the study day starts on the
 * registration date, and the choice is logged in pilot_assignment_log.
 * "PA-…" (Phase A is paused, decision 0034) and IDs without a prefix are
 * refused.
 */

"use strict";

const crypto = require("crypto");
const studyPeriod = require("./study_period");

const CONFIG_DOC = "meta/randomization_config";
const SEQ_COLLECTION = "randomization_sequences";
const STATE_COLLECTION = "randomization_state";
const ENROLL_COLLECTION = "enrollments";
const LOG_COLLECTION = "arm_assignment_log";
// T21: the pilot run's version choices (no stratum, no sequence position).
const PILOT_LOG_COLLECTION = "pilot_assignment_log";
const STRATA = ["low", "high"];
const MIN_SEQUENCE_LENGTH = 60;
const BLOCK_SIZES = [2, 4];
const METHOD = "permuted_block_v1";
const GENERATOR_VERSION = "permuted_block_v1";
// Research IDs typed by the researcher: upper case letters, digits and
// hyphens, 2–12 characters (e.g. "B001", "PB-017").  Also accepted by
// functions/blinding.js and tool/check_blinded_export.js.
const RESEARCH_ID_PATTERN = /^[A-Z0-9][A-Z0-9-]{1,11}$/;
const VARIANTS = ["feminine", "masculine"];

/**
 * T47: the pairing the elder chose in the App's onboarding (null until
 * they have).  Recorded on the enrolment; never overwritten by the
 * researcher.
 * @param {object} u users/{uid} data
 * @return {?string} "feminine" | "masculine" | null
 */
function elderVariant(u) {
  const v = u && u.ahJanAhBakVariant;
  return VARIANTS.indexOf(v) >= 0 ? v : null;
}
const UNBLINDED_ROLE = "unblinded";

/**
 * @param {?object} snap meta/randomization_config snapshot
 * @return {{enabled: boolean}}
 */
function configFromSnap(snap) {
  const d = (snap && snap.exists && snap.data()) || {};
  return {enabled: d.enabled === true};
}

/**
 * @param {*} score W0 DJG emotional subscale
 * @return {?string} "low" | "high", or null when not an integer 0–3
 */
function stratumFor(score) {
  if (typeof score !== "number" || !Number.isInteger(score)) return null;
  if (score < 0 || score > 3) return null;
  return score <= 1 ? "low" : "high";
}

/**
 * @param {*} raw
 * @return {?string} normalised research ID, or null when invalid
 */
function normaliseResearchId(raw) {
  if (typeof raw !== "string") return null;
  const id = raw.trim().toUpperCase();
  return RESEARCH_ID_PATTERN.test(id) ? id : null;
}

/**
 * YYYY-MM-DD in Hong Kong time.
 * @param {Date} d
 * @return {string}
 */
function hkDateKey(d) {
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

/**
 * @param {*} raw
 * @param {Date} now
 * @return {?string} a real calendar date not after today (HK), or null
 */
function validW0Date(raw, now) {
  if (typeof raw !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return null;
  }
  const d = new Date(`${raw}T00:00:00Z`);
  if (isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== raw) return null;
  return raw <= hkDateKey(now) ? raw : null;
}

/**
 * Deterministic integer source from a seed (HMAC-SHA256 counter mode,
 * rejection sampling — no modulo bias).
 * @param {string} seed
 * @param {string} label separates the two strata
 * @return {function(number): number} n → 0..n-1
 */
function seededRandomInt(seed, label) {
  let counter = 0;
  return (n) => {
    const limit = Math.floor(0x100000000 / n) * n;
    for (;;) {
      const h = crypto.createHmac("sha256", seed)
          .update(`${label}|${counter++}`).digest();
      const v = h.readUInt32BE(0);
      if (v < limit) return v % n;
    }
  };
}

/**
 * One stratum's sequence: whole permuted blocks (size 2 or 4, chosen at
 * random), each with equal A and B in random order, until at least
 * [minLength] positions.
 * @param {string} seed
 * @param {string} stratum
 * @param {number} minLength
 * @return {{arms: Array<string>, blocks: Array<number>}}
 */
function generateStratum(seed, stratum, minLength) {
  const rand = seededRandomInt(seed, `${GENERATOR_VERSION}|${stratum}`);
  const arms = [];
  const blocks = [];
  while (arms.length < minLength) {
    const size = BLOCK_SIZES[rand(BLOCK_SIZES.length)];
    const block = [];
    for (let i = 0; i < size / 2; i++) block.push("A", "B");
    for (let i = block.length - 1; i > 0; i--) {
      const j = rand(i + 1);
      const t = block[i];
      block[i] = block[j];
      block[j] = t;
    }
    blocks.push(size);
    for (const a of block) arms.push(a);
  }
  return {arms, blocks};
}

/**
 * @param {Array<string>} arms
 * @return {string} hex sha256 of the arms joined (for the offline copy)
 */
function sequenceHash(arms) {
  return crypto.createHash("sha256").update(arms.join(""), "utf8")
      .digest("hex");
}

/**
 * Both strata from one seed.
 * @param {string} seed
 * @param {number=} minLength
 * @return {Object<string, {arms: Array<string>, blocks: Array<number>,
 *     length: number, sha256: string}>}
 */
function generateSequences(seed, minLength) {
  const len = minLength || MIN_SEQUENCE_LENGTH;
  if (typeof seed !== "string" || seed.length < 16) {
    throw new Error("seed_too_short");
  }
  if (len < MIN_SEQUENCE_LENGTH) throw new Error("length_below_minimum");
  const out = {};
  for (const s of STRATA) {
    const g = generateStratum(seed, s, len);
    out[s] = {arms: g.arms, blocks: g.blocks, length: g.arms.length,
      sha256: sequenceHash(g.arms)};
  }
  return out;
}

/**
 * Is [seq] a valid permuted-block sequence (blocks of 2/4, each balanced)?
 * @param {{arms: Array<string>, blocks: Array<number>}} seq
 * @return {boolean}
 */
function sequenceValid(seq) {
  if (!seq || !Array.isArray(seq.arms) || !Array.isArray(seq.blocks)) {
    return false;
  }
  let i = 0;
  for (const size of seq.blocks) {
    if (BLOCK_SIZES.indexOf(size) < 0) return false;
    const block = seq.arms.slice(i, i + size);
    if (block.length !== size) return false;
    const a = block.filter((x) => x === "A").length;
    const b = block.filter((x) => x === "B").length;
    if (a !== size / 2 || b !== size / 2) return false;
    i += size;
  }
  return i === seq.arms.length && i >= MIN_SEQUENCE_LENGTH;
}

/**
 * An error the caller turns into an HttpsError with this code.
 * @param {string} code
 * @param {object=} detail
 * @return {Error}
 */
function enrolError(code, detail) {
  const e = new Error(code);
  e.enrolCode = code;
  if (detail) e.detail = detail;
  return e;
}

/**
 * Register one participant and allocate the arm (or, with dryRun, only
 * check and describe the account — never the next arm).
 *
 * Idempotent: an already-enrolled account returns its stored allocation
 * and nothing is re-randomised (the resubmission is logged).
 *
 * @param {object} db admin.firestore()
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{uid: string, researchId: *, w0DjgEmotional: *,
 *     w0Date: *, pilotArm: *, confirmed: *, dryRun: *}} input
 *     `uid` is the participant's account (resolved from the email by the
 *     callable wrapper).  `pilotArm` ("A" | "B") only for a PILOT- ID,
 *     which needs no score or W0 date (T21).  T47: a `companionVariant`
 *     in the input is ignored; the elder's own choice is recorded
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<object>}
 */
async function enrol(db, caller, input, opts) {
  const now = (opts && opts.now) || new Date();
  if (!caller || caller.role !== UNBLINDED_ROLE) {
    throw enrolError("not_unblinded_researcher");
  }
  const cfgSnap = await db.doc(CONFIG_DOC).get();
  if (!configFromSnap(cfgSnap).enabled) throw enrolError("disabled");

  const uid = typeof input.uid === "string" ? input.uid : "";
  if (!uid) throw enrolError("account_not_found");
  if (uid === caller.uid) throw enrolError("own_account");
  const researchId = normaliseResearchId(input.researchId);
  if (!researchId) throw enrolError("invalid_research_id");
  // T21: PB- or PILOT- only; PA- (Phase A paused) and no prefix refused.
  const period = studyPeriod.periodForResearchId(researchId);
  if (!period) throw enrolError("research_id_prefix");
  if (period.studyPeriod === "PILOT") {
    return enrolPilot(db, caller, uid, researchId, input, now);
  }
  const score = input.w0DjgEmotional;
  const stratum = stratumFor(score);
  if (!stratum) throw enrolError("invalid_score");
  // T47: the pairing is the elder's own choice (users/{uid}.ahJanAhBakVariant
  // from the App's onboarding); the researcher only records it.  A variant
  // in the input is ignored.
  const w0Date = input.w0Date == null ? hkDateKey(now) :
    validW0Date(input.w0Date, now);
  if (!w0Date) throw enrolError("invalid_w0_date");
  const dryRun = input.dryRun === true;
  if (!dryRun && input.confirmed !== true) {
    throw enrolError("not_confirmed");
  }

  const userRef = db.collection("users").doc(uid);
  const enrolRef = db.collection(ENROLL_COLLECTION).doc(uid);
  const ridRef = db.collection("research_ids").doc(researchId);
  const mapRef = db.collection("research_id_map").doc(uid);
  const seqRef = db.collection(SEQ_COLLECTION).doc(stratum);
  const stateRef = db.collection(STATE_COLLECTION).doc(stratum);
  const logRef = db.collection(LOG_COLLECTION).doc();

  return db.runTransaction(async (tx) => {
    const [user, existing, rid, map, seq, state] = await Promise.all([
      tx.get(userRef), tx.get(enrolRef), tx.get(ridRef), tx.get(mapRef),
      tx.get(seqRef), tx.get(stateRef),
    ]);
    if (!user.exists) throw enrolError("account_not_found");
    const u = user.data() || {};
    const account = {
      displayName: u.displayName || null,
      createdAt: toIso(u.createdAt),
    };
    const variant = elderVariant(u);

    if (existing.exists) {
      const same = existing.get("researchId") === researchId &&
        existing.get("w0DjgEmotional") === score;
      return resubmission(tx, db, caller, uid, existing, same, account,
          dryRun, now);
    }

    if (u.arm === "A" || u.arm === "B") throw enrolError("already_has_arm");
    if (u.isTester === true) throw enrolError("tester_account");
    if (rid.exists && rid.get("uid") !== uid) {
      throw enrolError("research_id_taken");
    }
    if (map.exists && map.get("researchId") !== researchId) {
      throw enrolError("account_has_other_research_id");
    }
    if (!seq.exists) throw enrolError("sequence_missing");
    const arms = seq.get("arms") || [];
    const next = state.exists ? Number(state.get("next")) || 0 : 0;
    if (next >= arms.length) throw enrolError("sequence_exhausted");

    if (dryRun) {
      return {alreadyEnrolled: false, account, researchId,
        studyPeriod: period.studyPeriod, stratum,
        w0DjgEmotional: score, companionVariant: variant, w0Date,
        arm: null};
    }

    const arm = arms[next];
    if (arm !== "A" && arm !== "B") throw enrolError("sequence_corrupt");
    const position = next + 1; // 1-based in records and the log

    tx.set(stateRef, {next: next + 1, updatedAt: now}, {merge: true});
    tx.set(userRef, {
      arm,
      strataCell: stratum === "low" ? 0 : 1,
      armAssignmentMode: "randomise",
      armAssignmentMethod: METHOD,
      armAssignedBy: "server",
      armAssignedAt: now,
      w0Date,
      // T21: the study period, from the PB- prefix (decision 0011 label).
      cohort: period.cohort,
    }, {merge: true});
    tx.create(enrolRef, {
      uid, researchId, w0DjgEmotional: score, stratum, companionVariant:
        variant, w0Date, arm, sequencePosition: position,
      sequenceSha256: seq.get("sha256") || null,
      // T21: from the research-ID prefix; the sequence path is PB- only.
      studyPeriod: period.studyPeriod,
      enrolledAt: now, enrolledBy: caller.uid,
      enrolledByEmail: caller.email || null,
    });
    if (!rid.exists) {
      tx.create(ridRef, {uid, createdAt: now, via: "enrollment"});
    }
    if (!map.exists) {
      tx.set(mapRef, {researchId, createdAt: now, via: "enrollment"});
    }
    tx.create(logRef, {
      action: "allocate", uid, researchId, stratum,
      sequencePosition: position, arm, at: now,
      by: caller.uid, byEmail: caller.email || null,
    });
    return {alreadyEnrolled: false, account, researchId,
      studyPeriod: period.studyPeriod, stratum,
      w0DjgEmotional: score, companionVariant: variant, w0Date, arm};
  });
}

/**
 * A repeat registration of an enrolled account: nothing is re-allocated;
 * the stored record is returned (no arm on a dry run) and, on a real
 * submission, the repeat is logged where the first registration was.
 * @param {object} tx transaction
 * @param {object} db
 * @param {{uid: string, email: ?string}} caller
 * @param {string} uid
 * @param {object} existing enrollments/{uid} snapshot
 * @param {boolean} same the input matches the stored registration
 * @param {object} account display name and creation time
 * @param {boolean} dryRun
 * @param {Date} now
 * @return {object}
 */
function resubmission(tx, db, caller, uid, existing, same, account, dryRun,
    now) {
  const e = existing.data();
  const pilot = e.studyPeriod === "PILOT";
  if (!dryRun) {
    const log = {
      action: "resubmit", uid, researchId: e.researchId, arm: e.arm,
      sameInput: same, at: now, by: caller.uid, byEmail: caller.email || null,
    };
    if (!pilot) {
      log.stratum = e.stratum;
      log.sequencePosition = e.sequencePosition;
    }
    tx.create(db.collection(pilot ? PILOT_LOG_COLLECTION : LOG_COLLECTION)
        .doc(), log);
  }
  return {
    alreadyEnrolled: true, sameInput: same, account,
    researchId: e.researchId, studyPeriod: e.studyPeriod || "B",
    stratum: e.stratum || null,
    w0DjgEmotional: e.w0DjgEmotional == null ? null : e.w0DjgEmotional,
    companionVariant: e.companionVariant, w0Date: e.w0Date,
    arm: dryRun ? null : e.arm,
  };
}

/**
 * T21 — register a pilot-run account (PILOT- research ID).  The
 * researcher chose the version ("A" Hybrid / "B" rule-based) on the
 * registration page and confirmed it a second time; no W0 score, no
 * stratum, no sequence position.  The study day starts on the
 * registration date (Hong Kong), stored as w0Date like Phase B's W0 so
 * the existing date logic applies.  Logged in pilot_assignment_log
 * (research ID, version, time, operator).
 * @param {object} db
 * @param {{uid: string, email: ?string}} caller
 * @param {string} uid participant account
 * @param {string} researchId normalised, PILOT- prefix
 * @param {object} input see enrol
 * @param {Date} now
 * @return {Promise<object>}
 */
async function enrolPilot(db, caller, uid, researchId, input, now) {
  const arm = input.pilotArm;
  if (arm !== "A" && arm !== "B") throw enrolError("invalid_pilot_arm");
  const dryRun = input.dryRun === true;
  if (!dryRun && input.confirmed !== true) {
    throw enrolError("not_confirmed");
  }
  const w0Date = hkDateKey(now);
  const period = studyPeriod.periodForResearchId(researchId);

  const userRef = db.collection("users").doc(uid);
  const enrolRef = db.collection(ENROLL_COLLECTION).doc(uid);
  const ridRef = db.collection("research_ids").doc(researchId);
  const mapRef = db.collection("research_id_map").doc(uid);

  return db.runTransaction(async (tx) => {
    const [user, existing, rid, map] = await Promise.all([
      tx.get(userRef), tx.get(enrolRef), tx.get(ridRef), tx.get(mapRef),
    ]);
    if (!user.exists) throw enrolError("account_not_found");
    const u = user.data() || {};
    const account = {
      displayName: u.displayName || null,
      createdAt: toIso(u.createdAt),
    };
    const variant = elderVariant(u);
    if (existing.exists) {
      const same = existing.get("researchId") === researchId &&
        existing.get("arm") === arm;
      return resubmission(tx, db, caller, uid, existing, same, account,
          dryRun, now);
    }
    if (u.arm === "A" || u.arm === "B") throw enrolError("already_has_arm");
    if (u.isTester === true) throw enrolError("tester_account");
    if (rid.exists && rid.get("uid") !== uid) {
      throw enrolError("research_id_taken");
    }
    if (map.exists && map.get("researchId") !== researchId) {
      throw enrolError("account_has_other_research_id");
    }
    // The researcher picked the version, so the preview may show it.
    const out = {alreadyEnrolled: false, account, researchId,
      studyPeriod: period.studyPeriod, stratum: null, w0DjgEmotional: null,
      companionVariant: variant, w0Date, arm};
    if (dryRun) return out;

    tx.set(userRef, {
      arm,
      armAssignmentMode: studyPeriod.PILOT_MODE,
      armAssignmentMethod: studyPeriod.PILOT_METHOD,
      armAssignedBy: "researcher",
      armAssignedAt: now,
      w0Date,
      cohort: period.cohort,
    }, {merge: true});
    tx.create(enrolRef, {
      uid, researchId, studyPeriod: period.studyPeriod, arm,
      companionVariant: variant, w0Date, w0DjgEmotional: null,
      stratum: null, sequencePosition: null,
      enrolledAt: now, enrolledBy: caller.uid,
      enrolledByEmail: caller.email || null,
    });
    if (!rid.exists) {
      tx.create(ridRef, {uid, createdAt: now, via: "enrollment"});
    }
    if (!map.exists) {
      tx.set(mapRef, {researchId, createdAt: now, via: "enrollment"});
    }
    tx.create(db.collection(PILOT_LOG_COLLECTION).doc(), {
      action: "designate", uid, researchId, arm, at: now,
      by: caller.uid, byEmail: caller.email || null,
    });
    return out;
  });
}

/**
 * @param {*} v Firestore Timestamp, Date or string
 * @return {?string}
 */
function toIso(v) {
  if (!v) return null;
  if (typeof v === "string") return v;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  return null;
}

/**
 * Admin-only correction (tool/correct_arm_assignment.js).  Changes the
 * stored arm, keeps the sequence position used, and logs the reason.
 * @param {object} db
 * @param {{uid: string, arm: string, reason: string, operator: string}} p
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{previousArm: string, arm: string}>}
 */
async function correctArm(db, p, opts) {
  const now = (opts && opts.now) || new Date();
  if (p.arm !== "A" && p.arm !== "B") throw enrolError("invalid_arm");
  const reason = typeof p.reason === "string" ? p.reason.trim() : "";
  if (reason.length < 10) throw enrolError("reason_required");
  if (!p.operator) throw enrolError("operator_required");
  const userRef = db.collection("users").doc(p.uid);
  const enrolRef = db.collection(ENROLL_COLLECTION).doc(p.uid);
  return db.runTransaction(async (tx) => {
    const [user, e] = await Promise.all([tx.get(userRef), tx.get(enrolRef)]);
    if (!user.exists || !e.exists) throw enrolError("not_enrolled");
    const previousArm = e.get("arm");
    if (previousArm === p.arm) throw enrolError("same_arm");
    tx.set(userRef, {arm: p.arm, armCorrectedAt: now}, {merge: true});
    tx.update(enrolRef, {arm: p.arm, correctedAt: now});
    // T21: a pilot account's version change goes to the pilot log.
    const pilot = e.get("studyPeriod") === "PILOT";
    tx.create(db.collection(pilot ? PILOT_LOG_COLLECTION : LOG_COLLECTION)
        .doc(), {
      action: "correction", uid: p.uid, researchId: e.get("researchId"),
      stratum: e.get("stratum") || null,
      sequencePosition: e.get("sequencePosition") || null,
      previousArm, arm: p.arm, reason, at: now, by: p.operator,
      byEmail: null,
    });
    return {previousArm, arm: p.arm};
  });
}

module.exports = {
  CONFIG_DOC, SEQ_COLLECTION, STATE_COLLECTION, ENROLL_COLLECTION,
  LOG_COLLECTION, PILOT_LOG_COLLECTION, STRATA, MIN_SEQUENCE_LENGTH,
  BLOCK_SIZES, METHOD, GENERATOR_VERSION, RESEARCH_ID_PATTERN, VARIANTS,
  UNBLINDED_ROLE,
  configFromSnap, stratumFor, normaliseResearchId, hkDateKey, validW0Date,
  seededRandomInt, generateSequences, sequenceHash, sequenceValid, enrol,
  correctArm,
};

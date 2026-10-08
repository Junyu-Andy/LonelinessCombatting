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
 */

"use strict";

const crypto = require("crypto");

const CONFIG_DOC = "meta/randomization_config";
const SEQ_COLLECTION = "randomization_sequences";
const STATE_COLLECTION = "randomization_state";
const ENROLL_COLLECTION = "enrollments";
const LOG_COLLECTION = "arm_assignment_log";
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
 *     companionVariant: *, w0Date: *, confirmed: *, dryRun: *}} input
 *     `uid` is the participant's account (resolved from the email by the
 *     callable wrapper)
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
  const score = input.w0DjgEmotional;
  const stratum = stratumFor(score);
  if (!stratum) throw enrolError("invalid_score");
  const variant = input.companionVariant;
  if (VARIANTS.indexOf(variant) < 0) throw enrolError("invalid_variant");
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

    if (existing.exists) {
      const e = existing.data();
      const same = e.researchId === researchId &&
        e.w0DjgEmotional === score && e.companionVariant === variant;
      if (!dryRun) {
        tx.create(logRef, {
          action: "resubmit", uid, researchId: e.researchId,
          stratum: e.stratum, sequencePosition: e.sequencePosition,
          arm: e.arm, sameInput: same, at: now,
          by: caller.uid, byEmail: caller.email || null,
        });
      }
      return {
        alreadyEnrolled: true, sameInput: same, account,
        researchId: e.researchId, stratum: e.stratum,
        w0DjgEmotional: e.w0DjgEmotional,
        companionVariant: e.companionVariant, w0Date: e.w0Date,
        arm: dryRun ? null : e.arm,
      };
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
      return {alreadyEnrolled: false, account, researchId, stratum,
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
      ahJanAhBakVariant: variant,
    }, {merge: true});
    tx.create(enrolRef, {
      uid, researchId, w0DjgEmotional: score, stratum, companionVariant:
        variant, w0Date, arm, sequencePosition: position,
      sequenceSha256: seq.get("sha256") || null,
      // T21 will let the researcher choose the study period here; the
      // sequence path is Phase B only.
      studyPeriod: "B",
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
    return {alreadyEnrolled: false, account, researchId, stratum,
      w0DjgEmotional: score, companionVariant: variant, w0Date, arm};
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
    tx.create(db.collection(LOG_COLLECTION).doc(), {
      action: "correction", uid: p.uid, researchId: e.get("researchId"),
      stratum: e.get("stratum"),
      sequencePosition: e.get("sequencePosition"),
      previousArm, arm: p.arm, reason, at: now, by: p.operator,
      byEmail: null,
    });
    return {previousArm, arm: p.arm};
  });
}

module.exports = {
  CONFIG_DOC, SEQ_COLLECTION, STATE_COLLECTION, ENROLL_COLLECTION,
  LOG_COLLECTION, STRATA, MIN_SEQUENCE_LENGTH, BLOCK_SIZES, METHOD,
  GENERATOR_VERSION, RESEARCH_ID_PATTERN, VARIANTS, UNBLINDED_ROLE,
  configFromSnap, stratumFor, normaliseResearchId, hkDateKey, validW0Date,
  seededRandomInt, generateSequences, sequenceHash, sequenceValid, enrol,
  correctArm,
};

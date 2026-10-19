/**
 * T30 (registry C01; dev-tasks-1010 §四 T30 §2.4; dev-tasks-1014 §二 rule
 * 9) — the allocation sequence is generated and uploaded by the person in
 * the study with no other role, not by Junyu and not with a service
 * account.
 *
 * Role `sequence_uploader` (Auth custom claim, tool/provision_researcher.js)
 * calls the `uploadRandomizationSequence` callable with the two sequences
 * generated on their own machine (tool/randomization_sequence.js, no seed
 * in the payload).
 *
 * 10/19 (dev-tasks-1020 §C, approved in 1020b §1) — sequence versions.
 * The first sequence (v1, randomization_sequences/{low,high}) served the
 * PB- registrations, which became the run-in; from 10/21 the randomised
 * analysis set (RCT-) draws from v2.  An upload now names its version and
 * the server:
 *   - checks the role and the switch meta/randomization_config
 *     .sequenceUploadEnabled (OFF unless literally true; Junyu turns it on
 *     for the upload and off again);
 *   - accepts only a version a registration draws from (study_period.js
 *     PERIODS: "v2"), else version_required;
 *   - validates both sequences (functions/randomization.js sequenceValid)
 *     and needs at least 80 positions per stratum (too_short);
 *   - refuses when that version already has an allocation
 *     (already_allocated), or is already there without `replace`
 *     (already_uploaded);
 *   - refuses a sequence made from v1's seed (same_seed_as_v1): the
 *     generator is deterministic, so the same seed repeats v1 at the
 *     start; the check compares the sha256 of v2's first v1-length
 *     positions with v1's stored sha256.  Only v1's `length` and `sha256`
 *     are read (a field mask) — never v1's arms;
 *   - writes randomization_sequences/{v2_low,v2_high} and
 *     randomization_state/{v2_low,v2_high}.next = 0, and in the same
 *     transaction sequence_versions/v2 (active) and — once —
 *     sequence_versions/v1 (retired: when, by whom, each stratum's length,
 *     used positions and sha256).  v1's own documents and the allocation
 *     log are not touched;
 *   - writes one server-only row in sequence_upload_log: time, uid,
 *     e-mail, version, each stratum's length, block count and sha256 —
 *     never the arms, never a seed.
 * No client role reads the sequences, the state, the versions or the log
 * (firestore.rules).
 */

"use strict";

const R = require("./randomization");
const studyPeriod = require("./study_period");

const ROLE = "sequence_uploader";
const FLAG = "sequenceUploadEnabled";
const LOG_COLLECTION = "sequence_upload_log";
const VERSIONS_COLLECTION = "sequence_versions";
const MIN_UPLOAD_LENGTH = 80;
const V1 = "v1";

/**
 * @param {string} code
 * @return {Error}
 */
function uploadError(code) {
  const e = new Error(code);
  e.uploadCode = code;
  return e;
}

/** @return {Array<string>} versions a registration draws from ("v2"). */
function uploadableVersions() {
  return studyPeriod.PERIODS
      .map((p) => p.sequenceVersion)
      .filter((v) => typeof v === "string");
}

/**
 * @param {*} raw sequences payload {low: {arms, blocks}, high: {...}}
 * @return {?object} normalised {stratum: {arms, blocks, length, sha256}}
 */
function normaliseSequences(raw) {
  if (!raw || typeof raw !== "object") return null;
  const out = {};
  for (const s of R.STRATA) {
    const seq = raw[s];
    if (!seq || !Array.isArray(seq.arms) || !Array.isArray(seq.blocks)) {
      return null;
    }
    const arms = seq.arms.map(String);
    const blocks = seq.blocks.map(Number);
    if (!R.sequenceValid({arms, blocks})) return null;
    out[s] = {arms, blocks, length: arms.length, sha256: R.sequenceHash(arms)};
    if (typeof seq.sha256 === "string" && seq.sha256 !== out[s].sha256) {
      return null; // the fingerprint the uploader saw does not match
    }
  }
  return out;
}

/**
 * Would [arms] repeat v1?  True when its first v1-length positions hash
 * to v1's stored sha256 (same seed → same start).
 * @param {Array<string>} arms the new stratum
 * @param {?{length: *, sha256: *}} v1 v1's stored length and sha256
 * @return {boolean}
 */
function repeatsV1(arms, v1) {
  if (!v1 || typeof v1.sha256 !== "string") return false;
  const len = Number(v1.length) || 0;
  if (len <= 0 || arms.length < len) return false;
  return R.sequenceHash(arms.slice(0, len)) === v1.sha256;
}

/**
 * @param {object} db admin.firestore()
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{sequences: *, replace: *, version: *}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{version: string, uploaded: Object<string, {length:
 *     number, blocks: number, sha256: string}>, replaced: boolean}>}
 */
async function uploadSequence(db, caller, input, opts) {
  const now = (opts && opts.now) || new Date();
  if (!caller || caller.role !== ROLE) throw uploadError("not_uploader");
  const cfg = await db.doc(R.CONFIG_DOC).get();
  if (!cfg.exists || cfg.get(FLAG) !== true) throw uploadError("disabled");
  const version = input && input.version;
  if (uploadableVersions().indexOf(version) < 0) {
    throw uploadError("version_required");
  }
  const seqs = normaliseSequences(input && input.sequences);
  if (!seqs) throw uploadError("invalid_sequences");
  for (const s of R.STRATA) {
    if (seqs[s].length < MIN_UPLOAD_LENGTH) throw uploadError("too_short");
  }
  const replace = !!(input && input.replace === true);

  return db.runTransaction(async (tx) => {
    const refs = {};
    const snaps = {};
    const v1Refs = {seq: [], state: []};
    for (const s of R.STRATA) {
      const id = R.sequenceDocId(version, s);
      refs[s] = {seq: db.collection(R.SEQ_COLLECTION).doc(id),
        state: db.collection(R.STATE_COLLECTION).doc(id)};
      snaps[s] = {seq: await tx.get(refs[s].seq),
        state: await tx.get(refs[s].state)};
      v1Refs.seq.push(db.collection(R.SEQ_COLLECTION)
          .doc(R.sequenceDocId(V1, s)));
      v1Refs.state.push(db.collection(R.STATE_COLLECTION)
          .doc(R.sequenceDocId(V1, s)));
    }
    // v1: length and sha256 only (field mask), and the used count.
    const v1Seq = await tx.getAll(...v1Refs.seq,
        {fieldMask: ["length", "sha256"]});
    const v1State = await tx.getAll(...v1Refs.state);
    const v1VersionRef = db.collection(VERSIONS_COLLECTION).doc(V1);
    const v1Version = await tx.get(v1VersionRef);

    for (const s of R.STRATA) {
      const used = snaps[s].state.exists ?
        Number(snaps[s].state.get("next")) || 0 : 0;
      if (used > 0) throw uploadError("already_allocated");
      if (snaps[s].seq.exists && !replace) {
        throw uploadError("already_uploaded");
      }
    }
    const v1 = {};
    R.STRATA.forEach((s, i) => {
      v1[s] = v1Seq[i].exists ? {length: v1Seq[i].get("length") || null,
        sha256: v1Seq[i].get("sha256") || null,
        used: v1State[i].exists ? Number(v1State[i].get("next")) || 0 : 0} :
        null;
      if (repeatsV1(seqs[s].arms, v1[s])) throw uploadError("same_seed_as_v1");
    });

    const replaced = R.STRATA.some((s) => snaps[s].seq.exists);
    const summary = {};
    for (const s of R.STRATA) {
      tx.set(refs[s].seq, {
        stratum: s, version, arms: seqs[s].arms, blocks: seqs[s].blocks,
        length: seqs[s].length, sha256: seqs[s].sha256,
        generatorVersion: R.GENERATOR_VERSION, studyPeriod: "B",
        uploadedAt: now, uploadedBy: caller.uid,
        uploadedByEmail: caller.email || null, via: "callable",
      });
      tx.set(refs[s].state, {next: 0, updatedAt: now});
      summary[s] = {length: seqs[s].length, blocks: seqs[s].blocks.length,
        sha256: seqs[s].sha256};
    }
    if (!v1Version.exists) {
      tx.create(v1VersionRef, {
        version: V1, status: "retired", retiredAt: now,
        retiredBy: caller.uid, retiredByEmail: caller.email || null,
        reason: "10/19: PB- became the run-in; RCT- draws from " + version,
        strata: v1,
      });
    }
    tx.set(db.collection(VERSIONS_COLLECTION).doc(version), {
      version, status: "active", activatedAt: now, uploadedBy: caller.uid,
      uploadedByEmail: caller.email || null, replaced, strata: summary,
    });
    tx.create(db.collection(LOG_COLLECTION).doc(), {
      at: now, by: caller.uid, byEmail: caller.email || null, version,
      replaced, strata: summary, generatorVersion: R.GENERATOR_VERSION,
    });
    return {version, uploaded: summary, replaced};
  });
}

module.exports = {ROLE, FLAG, LOG_COLLECTION, VERSIONS_COLLECTION,
  MIN_UPLOAD_LENGTH, uploadableVersions, normaliseSequences, repeatsV1,
  uploadSequence};

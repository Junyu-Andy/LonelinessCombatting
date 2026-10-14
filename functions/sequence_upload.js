/**
 * T30 (registry C01; dev-tasks-1010 §四 T30 §2.4; dev-tasks-1014 §二 rule
 * 9) — the allocation sequence is generated and uploaded by Calvin, not
 * by Junyu and not with a service account.
 *
 * Role `sequence_uploader` (Auth custom claim, tool/provision_researcher.js,
 * Calvin only) calls the `uploadRandomizationSequence` callable with the
 * two sequences he generated on his own machine
 * (tool/randomization_sequence.js, no seed in the payload).  The server:
 *   - checks the role and the switch meta/randomization_config
 *     .sequenceUploadEnabled (OFF unless literally true; Junyu turns it on
 *     for the upload and off again);
 *   - validates both sequences (functions/randomization.js sequenceValid);
 *   - refuses when a sequence is already there (unless `replace`), and
 *     always when either stratum has an allocation (state.next > 0);
 *   - writes randomization_sequences/{low,high} and
 *     randomization_state/{low,high}.next = 0 in one transaction;
 *   - writes one server-only row in sequence_upload_log: time, uid,
 *     e-mail, each stratum's length, block count and sha256 — never the
 *     arms, never a seed.
 * No client role reads the sequences, the state or the log
 * (firestore.rules).
 */

"use strict";

const R = require("./randomization");

const ROLE = "sequence_uploader";
const FLAG = "sequenceUploadEnabled";
const LOG_COLLECTION = "sequence_upload_log";

/**
 * @param {string} code
 * @return {Error}
 */
function uploadError(code) {
  const e = new Error(code);
  e.uploadCode = code;
  return e;
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
      return null; // the fingerprint Calvin saw does not match the arms
    }
  }
  return out;
}

/**
 * @param {object} db admin.firestore()
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{sequences: *, replace: *}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{uploaded: Object<string, {length: number,
 *     blocks: number, sha256: string}>, replaced: boolean}>}
 */
async function uploadSequence(db, caller, input, opts) {
  const now = (opts && opts.now) || new Date();
  if (!caller || caller.role !== ROLE) throw uploadError("not_uploader");
  const cfg = await db.doc(R.CONFIG_DOC).get();
  if (!cfg.exists || cfg.get(FLAG) !== true) throw uploadError("disabled");
  const seqs = normaliseSequences(input && input.sequences);
  if (!seqs) throw uploadError("invalid_sequences");
  const replace = !!(input && input.replace === true);

  return db.runTransaction(async (tx) => {
    const refs = {};
    const snaps = {};
    for (const s of R.STRATA) {
      refs[s] = {seq: db.collection(R.SEQ_COLLECTION).doc(s),
        state: db.collection(R.STATE_COLLECTION).doc(s)};
      snaps[s] = {seq: await tx.get(refs[s].seq),
        state: await tx.get(refs[s].state)};
    }
    for (const s of R.STRATA) {
      const used = snaps[s].state.exists ?
        Number(snaps[s].state.get("next")) || 0 : 0;
      if (used > 0) throw uploadError("already_allocated");
      if (snaps[s].seq.exists && !replace) {
        throw uploadError("already_uploaded");
      }
    }
    const replaced = R.STRATA.some((s) => snaps[s].seq.exists);
    const summary = {};
    for (const s of R.STRATA) {
      tx.set(refs[s].seq, {
        stratum: s, arms: seqs[s].arms, blocks: seqs[s].blocks,
        length: seqs[s].length, sha256: seqs[s].sha256,
        generatorVersion: R.GENERATOR_VERSION, studyPeriod: "B",
        uploadedAt: now, uploadedBy: caller.uid,
        uploadedByEmail: caller.email || null, via: "callable",
      });
      tx.set(refs[s].state, {next: 0, updatedAt: now});
      summary[s] = {length: seqs[s].length, blocks: seqs[s].blocks.length,
        sha256: seqs[s].sha256};
    }
    tx.create(db.collection(LOG_COLLECTION).doc(), {
      at: now, by: caller.uid, byEmail: caller.email || null,
      replaced, strata: summary, generatorVersion: R.GENERATOR_VERSION,
    });
    return {uploaded: summary, replaced};
  });
}

module.exports = {ROLE, FLAG, LOG_COLLECTION, normaliseSequences,
  uploadSequence};

/**
 * T30 (registry C19 / C20) — paper outcome instruments the W4 assessor
 * enters, as the server validates and scores them.
 *
 * One entry per instrument, mirroring the spec file in
 * docs/spec/instruments/<id>.md (the App shows the same text from its own
 * copy; functions/test/outcome_instruments_test.js checks both against the
 * spec file word for word).
 *
 *   DJG-ES   docs/spec/instruments/djg_es.md — the 6-item De Jong Gierveld
 *            scale of questionnaire package §3, the same items and the
 *            same scoring as the in-App W2 copy (functions/djg_w2.js).
 *   PHQ-9    no spec file yet (dev-tasks-1010b §二 T30 4): the mechanism
 *            exists — 9 items, raw 0–3, total — with placeholder item text,
 *            so the T34 hook (item 9 ≠ 0 → safety event, source
 *            `assessor_entry`) can be wired and tested now.  The real item
 *            text is added when the research side files the spec; the code
 *            structure does not change.
 *
 * The assessor never sees a score: scores are computed here, stored in
 * server-only `outcome_entries`, and never returned to the client.
 */

"use strict";

const PLACEHOLDER_MARK = "【占位】";

const DJG_ES = {
  id: "DJG-ES",
  version: "djg6_pkg3_v1",
  timepoints: ["W4"],
  scoringVersion: "djg6_v1",
  items: [
    {id: "q1", subscale: "emotional", text: "我有一種空虛的感覺。"},
    {id: "q2", subscale: "emotional", text: "我想念身邊有人陪伴。"},
    {id: "q3", subscale: "emotional", text: "我經常覺得自己被人排斥。"},
    {id: "q4", subscale: "social", text: "當我遇到問題時，有許多人可以倚靠。"},
    {id: "q5", subscale: "social", text: "我有許多可以完全信任的人。"},
    {id: "q6", subscale: "social", text: "有足夠多我感到親近的人。"},
  ],
  // Stored value → label, questionnaire package §3 verbatim.
  options: [["yes", "是"], ["mostly", "大致是"], ["no", "不是"]],
  missingValue: "skipped",
  /**
   * Same rule as functions/djg_w2.js scoreAnswers: emotional items score 1
   * for 是 / 大致是, social items score 1 for 大致是 / 不是; a subscale with
   * a missing item has no score; total needs both.
   * @param {object} answers {q1..q6: yes|mostly|no|skipped}
   * @return {{emotional: ?number, social: ?number, total: ?number}}
   */
  score(answers) {
    const a = answers || {};
    const sums = {emotional: 0, social: 0};
    const missing = {emotional: false, social: false};
    for (const it of DJG_ES.items) {
      const v = a[it.id];
      if (v !== "yes" && v !== "mostly" && v !== "no") {
        missing[it.subscale] = true;
        continue;
      }
      sums[it.subscale] += it.subscale === "emotional" ?
        (v === "no" ? 0 : 1) : (v === "yes" ? 0 : 1);
    }
    const emotional = missing.emotional ? null : sums.emotional;
    const social = missing.social ? null : sums.social;
    return {emotional, social,
      total: emotional === null || social === null ? null :
        emotional + social};
  },
};

const PHQ9_ITEMS = [];
for (let i = 1; i <= 9; i++) {
  PHQ9_ITEMS.push({id: `q${i}`, text: `${PLACEHOLDER_MARK}PHQ-9 第 ${i} 題`});
}

const PHQ_9 = {
  id: "PHQ-9",
  version: "phq9_placeholder_v0",
  timepoints: ["W4"],
  scoringVersion: "phq9_sum_v1",
  items: PHQ9_ITEMS,
  // Raw 0–3; labels are placeholders until the spec file arrives.
  options: [[0, `${PLACEHOLDER_MARK}0`], [1, `${PLACEHOLDER_MARK}1`],
    [2, `${PLACEHOLDER_MARK}2`], [3, `${PLACEHOLDER_MARK}3`]],
  missingValue: "skipped",
  /** T34 hook: item 9 (0–3) not 0 raises a safety event. */
  safetyItem: {item: 9, answerId: "q9"},
  /**
   * @param {object} answers {q1..q9: 0|1|2|3|"skipped"}
   * @return {{total: ?number, answered: number}}
   */
  score(answers) {
    const a = answers || {};
    let total = 0;
    let answered = 0;
    for (const it of PHQ_9.items) {
      const v = a[it.id];
      if (Number.isInteger(v) && v >= 0 && v <= 3) {
        total += v;
        answered++;
      }
    }
    return {total: answered === PHQ_9.items.length ? total : null, answered};
  },
};

const INSTRUMENTS = {"DJG-ES": DJG_ES, "PHQ-9": PHQ_9};

/**
 * @param {*} id
 * @return {?object} the instrument, or null
 */
function instrumentFor(id) {
  return typeof id === "string" &&
    Object.prototype.hasOwnProperty.call(INSTRUMENTS, id) ?
    INSTRUMENTS[id] : null;
}

/**
 * Validate one set of raw answers against the instrument: every item
 * present, each value one of the options or the missing mark.
 * @param {object} inst
 * @param {*} answers
 * @return {?{answers: object, missingItems: Array<string>}} normalised
 *     answers and the ids of missing items, or null when invalid
 */
function validateAnswers(inst, answers) {
  if (!answers || typeof answers !== "object" || Array.isArray(answers)) {
    return null;
  }
  const allowed = inst.options.map((o) => o[0]);
  const out = {};
  const missingItems = [];
  for (const k of Object.keys(answers)) {
    if (!inst.items.some((it) => it.id === k)) return null;
  }
  for (const it of inst.items) {
    const v = answers[it.id];
    if (v === undefined || v === null || v === inst.missingValue) {
      out[it.id] = inst.missingValue;
      missingItems.push(it.id);
    } else if (allowed.indexOf(v) >= 0) {
      out[it.id] = v;
    } else {
      return null;
    }
  }
  return {answers: out, missingItems};
}

/**
 * @param {object} inst
 * @return {boolean} any item text still carries the placeholder mark
 */
function hasPlaceholderText(inst) {
  return inst.items.some((it) => it.text.indexOf(PLACEHOLDER_MARK) >= 0);
}

module.exports = {
  PLACEHOLDER_MARK, DJG_ES, PHQ_9, INSTRUMENTS, instrumentFor,
  validateAnswers, hasPlaceholderText,
};

/**
 * tool/dashboard/lib/leak_guard.js — last check before anything leaves
 * the dashboard (JSON to the browser, CSV to disk): no answer, allocation
 * or text field name anywhere in it (fields.FORBIDDEN_OUTPUT_KEYS).  The
 * field masks in guarded_db.js already keep those fields out of memory;
 * this catches a future code change that would add one.
 *
 * Decision 0072: a page may pass the paths where a forbidden-named field
 * is allowed (fields.OUTPUT_ALLOW — only the person page's daily mood
 * values).  There it passes only as a number or null.
 */
'use strict';

const fields = require('./fields');

/** "$.days[3].moods[0].mood" → "$.days[].moods[].mood". */
function shapeOf(path) {
  return path.replace(/\[\d+\]/g, '[]');
}

/**
 * @param {*} value
 * @param {Array<string>=} allowPaths path shapes where a forbidden key
 *     may hold a number (fields.OUTPUT_ALLOW[page])
 * @return {Array<string>} forbidden keys found, as paths
 */
function findLeaks(value, allowPaths) {
  const allow = allowPaths || [];
  const out = [];
  const seen = new Set();
  function allowed(path, v) {
    return allow.indexOf(shapeOf(path)) >= 0 &&
      (v === null || (typeof v === 'number' && isFinite(v)));
  }
  function walk(v, path) {
    if (v === null || typeof v !== 'object') return;
    if (seen.has(v)) return;
    seen.add(v);
    if (Array.isArray(v)) {
      v.forEach((x, i) => walk(x, `${path}[${i}]`));
      return;
    }
    for (const k of Object.keys(v)) {
      const p = `${path}.${k}`;
      if (fields.FORBIDDEN_OUTPUT_KEYS.indexOf(k) >= 0 && !allowed(p, v[k])) {
        out.push(p);
      }
      walk(v[k], p);
    }
  }
  walk(value, '$');
  return out;
}

/** Throws when [value] carries a forbidden key (outside [allowPaths]). */
function assertNoLeak(value, allowPaths) {
  const leaks = findLeaks(value, allowPaths);
  if (leaks.length) {
    const e = new Error(`blocked output: ${leaks.slice(0, 5).join(', ')}`);
    e.leak = true;
    throw e;
  }
  return value;
}

/** CSV header check: no forbidden column. */
function assertCsvClean(csv) {
  const header = String(csv).split('\n')[0].split(',');
  const bad = header.filter((h) => fields.FORBIDDEN_OUTPUT_KEYS.indexOf(h) >= 0);
  if (bad.length) {
    const e = new Error(`blocked CSV column: ${bad.join(', ')}`);
    e.leak = true;
    throw e;
  }
  return csv;
}

module.exports = {shapeOf, findLeaks, assertNoLeak, assertCsvClean};

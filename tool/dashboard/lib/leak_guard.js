/**
 * tool/dashboard/lib/leak_guard.js — last check before anything leaves
 * the dashboard (JSON to the browser, CSV to disk): no answer, allocation
 * or text field name anywhere in it (fields.FORBIDDEN_OUTPUT_KEYS).  The
 * field masks in guarded_db.js already keep those fields out of memory;
 * this catches a future code change that would add one.
 */
'use strict';

const fields = require('./fields');

/**
 * @param {*} value
 * @return {Array<string>} forbidden keys found, as paths
 */
function findLeaks(value) {
  const out = [];
  const seen = new Set();
  function walk(v, path) {
    if (v === null || typeof v !== 'object') return;
    if (seen.has(v)) return;
    seen.add(v);
    if (Array.isArray(v)) {
      v.forEach((x, i) => walk(x, `${path}[${i}]`));
      return;
    }
    for (const k of Object.keys(v)) {
      if (fields.FORBIDDEN_OUTPUT_KEYS.indexOf(k) >= 0) out.push(`${path}.${k}`);
      walk(v[k], `${path}.${k}`);
    }
  }
  walk(value, '$');
  return out;
}

/** Throws when [value] carries a forbidden key. */
function assertNoLeak(value) {
  const leaks = findLeaks(value);
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

module.exports = {findLeaks, assertNoLeak, assertCsvClean};

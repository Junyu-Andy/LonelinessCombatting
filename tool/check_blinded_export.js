#!/usr/bin/env node
/**
 * tool/check_blinded_export.js — T12 blinding check (SPEC:C19, decision 0021).
 *
 * Scans a blinded export (a folder of *.ndjson files plus manifest.json,
 * as written by functions/blinding.js) for anything that could reveal a
 * participant's arm or identity.  Exit codes:
 *   0  nothing suspicious
 *   1  findings (printed one per line)
 *   2  usage error / nothing to scan
 *
 * Usage:
 *   node tool/check_blinded_export.js <export-folder-or-file> [...]
 *
 * Get the folder with e.g.
 *   gsutil -m cp -r gs://<bucket>/exports_v2/<date> ./export-<date>
 *
 * What counts as suspicious (see docs/dev-reports/T12-blinding-20261007.md):
 *  - a file for a collection that must wait until unblinding
 *    (turns, events, llm_*, mem_*, ...) or any file not on the allowlist;
 *  - a field name from the deny list (arm, uid, model, llm, source, ...);
 *  - a value that names the arm mechanism (rule_based, deepseek, ...),
 *    a raw Firestore uid, or a users/... path;
 *  - groupCode other than Group_X / Group_Y, researchId in the wrong shape,
 *    or a row without researchId;
 *  - long strings (free text).
 */

"use strict";

const fs = require("fs");
const path = require("path");

const ALLOWED_FILES = [
  "participants", "brief_pr", "weekly_pr", "pgic", "djg_es", "djg_responses",
  "agent_diff", "daily_mood", "loneliness_probes", "safety_events",
  "usage_weekly",
];

// Collections that reveal the arm by existing at all, or carry
// arm-specific fields.  Named so the finding says why.
const HELD_BACK_FILES = [
  "turns", "sessions", "events", "llm_turn_features", "llm_calls",
  "thought_exercise", "action_plans", "reminders", "response_feedback",
  "tester_feedback", "ppr_responses", "check_in_responses",
  "agent_contexts", "agent_greetings", "shared_context", "memory",
  "cross_module_callbacks", "onboarding", "pi_alerts", "te_audit_queue",
  "safety_event_dedup", "stt_usage", "users",
];

// Field names (at any depth) that must not appear.
const DENY_KEYS = [
  // identity
  "uid", "uidHash", "participantId", "email", "displayName",
  "emergencyContactName", "emergencyContactPhone", "closeContacts",
  "importantPeople", "reconnectPeople", "phone",
  // arm and arm bookkeeping
  "arm", "armAssignmentMode", "armAssignedBy", "armAssignedAt",
  "cohort",
  // LLM-only machinery
  "llm", "model", "model_returned", "promptVersion", "systemPromptHash",
  "temperature", "latencyMs", "flags", "F1", "F2", "F3", "F4", "F5",
  "tungtung", "searchInvoked", "fallbackCount", "llmStatus",
  "memory_enabled", "memoryDeletedAt",
  // values that differ by arm, or link back to raw ids
  "source", "source_surface", "sessionRef", "sessionId", "originTurnRef",
  "eventPath", "dedup_key", "dedupKey", "textHash", "referentRule",
  "sessionCountThisWeek",
  // free text / quotes
  "matchedTerm", "matchedTextPrefix32", "offerText", "agentInvitationText",
  "freeResponse", "reasonOtherText", "otherText", "note", "avoidTopics",
  "onMind", "thoughtPreview", "quote", "summary", "text",
];
const DENY_KEY_SET = {};
for (const k of DENY_KEYS) DENY_KEY_SET[k.toLowerCase()] = true;

const DENY_VALUE_PATTERNS = [
  {re: /rule_based/i, why: "names the rule-based arm"},
  {re: /deepseek/i, why: "names the LLM"},
  {re: /\bllm\b/i, why: "names the LLM"},
  {re: /(^|\/)users\/[^/]+/, why: "Firestore path with a raw uid"},
  {re: /^[A-Za-z0-9]{28}$/, why: "looks like a raw Firebase uid"},
  {re: /^[0-9a-f]{16}$/, why: "looks like the legacy uidHash"},
];

const RESEARCH_ID = /^P[0-9A-HJKMNP-TV-Z]{6}$/;
const GROUP_CODE = /^Group_[XY]$/;
const MAX_STRING = 60;

/**
 * Walk one row; push findings.
 * @param {*} v
 * @param {string} where
 * @param {Array<string>} out
 */
function walk(v, where, out) {
  if (v === null || v === undefined) return;
  if (Array.isArray(v)) {
    v.forEach((x, i) => walk(x, `${where}[${i}]`, out));
    return;
  }
  if (typeof v === "object") {
    for (const k of Object.keys(v)) {
      if (DENY_KEY_SET[k.toLowerCase()]) {
        out.push(`${where}.${k}: field not allowed in a blinded export`);
      }
      walk(v[k], `${where}.${k}`, out);
    }
    return;
  }
  if (typeof v !== "string") return;
  for (const p of DENY_VALUE_PATTERNS) {
    if (p.re.test(v)) out.push(`${where}: value ${JSON.stringify(v)} ${p.why}`);
  }
  if (v.length > MAX_STRING) {
    out.push(`${where}: ${v.length}-character string (free text?)`);
  }
}

/**
 * Check one row of an ndjson file.
 * @param {object} row
 * @param {string} where
 * @param {Array<string>} out
 */
function checkRow(row, where, out) {
  if (row === null || typeof row !== "object" || Array.isArray(row)) {
    out.push(`${where}: not a JSON object`);
    return;
  }
  if (!RESEARCH_ID.test(String(row.researchId))) {
    out.push(`${where}: researchId missing or not in P + 6 characters form`);
  }
  if (row.groupCode !== undefined && row.groupCode !== null &&
      !GROUP_CODE.test(String(row.groupCode))) {
    out.push(`${where}: groupCode ${JSON.stringify(row.groupCode)} ` +
      "is not Group_X / Group_Y");
  }
  const rest = Object.assign({}, row);
  delete rest.researchId;
  delete rest.groupCode;
  walk(rest, where, out);
}

/**
 * @param {string} file path to one .ndjson file
 * @param {Array<string>} out findings
 */
function checkFile(file, out) {
  const base = path.basename(file).replace(/\.ndjson$/, "");
  if (HELD_BACK_FILES.indexOf(base) >= 0 || /^mem_/.test(base)) {
    out.push(`${file}: collection "${base}" must not be exported before ` +
      "unblinding");
    return;
  }
  if (ALLOWED_FILES.indexOf(base) < 0) {
    out.push(`${file}: "${base}" is not on the blinded-export allowlist`);
    return;
  }
  const lines = fs.readFileSync(file, "utf8").split("\n");
  lines.forEach((line, i) => {
    if (!line.trim()) return;
    let row;
    try {
      row = JSON.parse(line);
    } catch (e) {
      out.push(`${file}:${i + 1}: not valid JSON`);
      return;
    }
    checkRow(row, `${base}:${i + 1}`, out);
  });
}

/**
 * Collect .ndjson files under the given paths.
 * @param {Array<string>} targets
 * @return {Array<string>}
 */
function listFiles(targets) {
  const files = [];
  for (const t of targets) {
    const st = fs.statSync(t);
    if (st.isDirectory()) {
      for (const f of fs.readdirSync(t).sort()) {
        const full = path.join(t, f);
        if (fs.statSync(full).isDirectory()) continue;
        if (f === "manifest.json") continue;
        files.push(full);
      }
    } else {
      files.push(t);
    }
  }
  return files;
}

/**
 * @param {Array<string>} targets folders or files
 * @return {{files: number, findings: Array<string>}}
 */
function checkExport(targets) {
  const findings = [];
  const files = listFiles(targets);
  for (const f of files) {
    if (!/\.ndjson$/.test(f)) {
      findings.push(`${f}: unexpected file (only .ndjson and manifest.json)`);
      continue;
    }
    checkFile(f, findings);
  }
  return {files: files.length, findings};
}

if (require.main === module) {
  const targets = process.argv.slice(2);
  if (targets.length === 0) {
    console.error("Usage: node tool/check_blinded_export.js <folder|file>...");
    process.exit(2);
  }
  let result;
  try {
    result = checkExport(targets);
  } catch (e) {
    console.error(`check_blinded_export: ${e.message}`);
    process.exit(2);
  }
  if (result.files === 0) {
    console.error("check_blinded_export: no files found");
    process.exit(2);
  }
  for (const f of result.findings) console.log(f);
  if (result.findings.length > 0) {
    console.log(`FAIL: ${result.findings.length} finding(s) in ` +
      `${result.files} file(s).`);
    process.exit(1);
  }
  console.log(`OK: ${result.files} file(s), nothing that reveals the arm.`);
}

module.exports = {checkExport, checkRow, ALLOWED_FILES, HELD_BACK_FILES,
  DENY_KEYS};

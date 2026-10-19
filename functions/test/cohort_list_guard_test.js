/**
 * 1020b §1(4) — leak guard for the cohort lists.  Every check by cohort
 * reads one list per environment:
 *   server  functions/study_period.js  ENROLLED_COHORTS, PHASE_B_COHORTS
 *   App     lib/core/study/cohorts.dart Cohorts.enrolled / Cohorts.phaseB
 *   rules   firestore.rules            enrolledCohort()
 * This test fails when code anywhere else (lib/, functions/*.js, tool/,
 * firestore.rules outside that function) writes a cohort label as a
 * string literal — 'phase_b', 'rct' or 'pilot' compared with a cohort, or
 * the literal 'phase_b' at all.  The path `app_config/phase_b`, the build
 * define PHASE_B and comments do not count.  Tests are not scanned.
 *
 * Run:  cd functions && node test/cohort_list_guard_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "../..");
const LIST_FILES = new Set([
  "functions/study_period.js",
  "lib/core/study/cohorts.dart",
]);

/** A quoted 'phase_b' / "phase_b" literal (not app_config/phase_b). */
const PHASE_B_LITERAL = /(['"])phase_b\1/;
/** A cohort compared or matched with a quoted label. */
const COHORT_COMPARE = new RegExp(
    "cohort[^;]*?(===|!==|==|!=|\\bin\\b)\\s*\\[?\\s*(['\"])(phase_b|rct|" +
    "pilot)\\2|(['\"])(phase_b|rct|pilot)\\4\\s*(===|!==|==|!=)[^;]*cohort");

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`ok - ${name}`);
  } catch (err) {
    failures.push(name);
    console.log(`FAIL - ${name}\n      ${err.message}`);
  }
}

function walk(dir, exts, out) {
  for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
    if (e.name === "node_modules" || e.name === "test" ||
        e.name.startsWith(".")) {
      continue;
    }
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, exts, out);
    else if (exts.some((x) => e.name.endsWith(x))) out.push(p);
  }
  return out;
}

/** Code lines only: comment lines dropped, trailing " // …" cut. */
function codeLines(text) {
  return text.split("\n").map((line, i) => {
    const t = line.trim();
    if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*")) {
      return {n: i + 1, code: ""};
    }
    const cut = line.search(/\s\/\/\s/);
    return {n: i + 1, code: cut >= 0 ? line.slice(0, cut) : line};
  });
}

/** @return {Array<string>} "file:line: code" offences in [text] */
function offences(rel, text) {
  const out = [];
  for (const {n, code} of codeLines(text)) {
    if (PHASE_B_LITERAL.test(code) || COHORT_COMPARE.test(code)) {
      out.push(`${rel}:${n}: ${code.trim()}`);
    }
  }
  return out;
}

function scanRepo() {
  const files = []
      .concat(walk(path.join(ROOT, "lib"), [".dart"], []))
      .concat(fs.readdirSync(path.join(ROOT, "functions"))
          .filter((f) => f.endsWith(".js"))
          .map((f) => path.join(ROOT, "functions", f)))
      .concat(walk(path.join(ROOT, "tool"), [".js"], []));
  const found = [];
  for (const f of files) {
    const rel = path.relative(ROOT, f).split(path.sep).join("/");
    if (LIST_FILES.has(rel)) continue;
    found.push(...offences(rel, fs.readFileSync(f, "utf8")));
  }
  return found;
}

test("the detector catches the patterns it is meant to catch", () => {
  const bad = [
    "if (u.cohort === \"phase_b\") return 1;",
    "  bool get x => cohort == 'pilot';",
    "  return u.get('cohort', null) in ['phase_b', 'pilot'];",
    "const PHASE = 'phase_b';",
    "if (\"rct\" === user.cohort) {",
  ];
  for (const b of bad) {
    assert.strictEqual(offences("x.js", b).length, 1, b);
  }
  const fine = [
    "const CONFIG_DOC = \"app_config/phase_b\";",
    "  'not_phase_b' => '…',",
    "// u.cohort === \"phase_b\" in a comment",
    " * cohort \"phase_b\" in a doc comment",
    "if (u.cohort === \"phase_a\") return true;",
    "const isPhaseB = bool.fromEnvironment('PHASE_B');",
    "return studyPeriod.isPhaseBCohort(u);",
  ];
  for (const f of fine) {
    assert.deepStrictEqual(offences("x.js", f), [], f);
  }
});

test("no cohort label outside the list files (lib/, functions/, tool/)",
    () => {
      const found = scanRepo();
      assert.deepStrictEqual(found, [],
          "compare with the lists instead:\n  " + found.join("\n  "));
    });

test("firestore.rules: the labels appear only in enrolledCohort()", () => {
  const rules = fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8");
  const hits = codeLines(rules).filter(({code}) =>
    /(['"])(phase_b|rct|pilot)\1/.test(code));
  assert.strictEqual(hits.length, 1,
      hits.map((h) => `firestore.rules:${h.n}`).join(", "));
  assert.match(hits[0].code,
      /in \['phase_b', 'rct', 'pilot'\]/);
  const fn = rules.slice(rules.indexOf("function enrolledCohort("));
  assert.ok(fn.slice(0, 200).includes(hits[0].code.trim()),
      "the one list is inside enrolledCohort()");
});

test("the three lists agree", () => {
  const SP = require("../study_period");
  const dart = fs.readFileSync(
      path.join(ROOT, "lib/core/study/cohorts.dart"), "utf8");
  for (const c of SP.ENROLLED_COHORTS) {
    assert.ok(dart.includes(`'${c}'`), `App list lacks ${c}`);
  }
  assert.deepStrictEqual([...SP.ENROLLED_COHORTS].sort(),
      ["phase_b", "pilot", "rct"]);
  assert.deepStrictEqual([...SP.PHASE_B_COHORTS].sort(), ["phase_b", "rct"]);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);

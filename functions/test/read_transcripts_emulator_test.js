/**
 * tool/read_transcripts.js against the Firestore emulator, synthetic data
 * only: a tester account with schema 1 and schema 2 rows (companion,
 * elder, button, typed, acute) prints in time order, grouped by session;
 * a non-tester (and a missing account) is refused BEFORE any transcript is
 * read (a recording wrapper around the database proves it); the dry run
 * reads only the time fields; nothing is written; no e-mail, research ID
 * or arm is printed; the target guard and the options.
 *
 * Run from the repo root (tool/ci_backend_tests.sh does this):
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/read_transcripts_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const tool = require("../../tool/read_transcripts");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
const PROJECT = "loneliness-pilot-dev";
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const SCRIPT = path.resolve(__dirname, "../../tool/read_transcripts.js");
const NODE_PATH = path.resolve(__dirname, "../node_modules");

const TESTER = "synthReadTxTester000000001";
const PARTICIPANT = "synthReadTxParticipant0002";
const STRING_FLAG = "synthReadTxStringFlag00003";
const MISSING = "synthReadTxNoUserDoc000004";
const TESTER_MAIL = "tester-secret-mail@example.invalid";
const PARTICIPANT_MAIL = "participant-mail@example.invalid";
const RESEARCH_ID = "RCT-901";
const SECRET = "參與者嘅秘密說話";

// The words the App shows (lib/features/context/data/check_in_chat_copy.dart,
// lib/features/crisis/presentation/widgets/crisis_chat_message.dart).
const Q0 = "早晨！想問下你尋日嘅情況，幾條就得。";
const Q1 = "尋日成日整體過得點？";
const Q2 = "尋日有冇同人傾過偈？";
const XG = "多謝你話俾我知尋日嘅情況。";
const Q4 = "今日有咩打算？想講就講，唔講都得。";
const R4A = "好呀，今日就照你嘅打算慢慢嚟。";
const Q5 = "想訂個小計劃嗎？";
const Q6 = "多謝你同我傾，聽朝再問候你。";
const SY0 = "今日 check-in 做咗喇，想再講啲咩都得。";
const ACUTE = "我真係想死";
const CRISIS = [
  "如果你而家好唔開心、好難頂，請即刻打以下電話，有人會聽你講：",
  "生命熱線 2382 0000",
  "撒瑪利亞會 2896 0000",
  "醫院管理局精神健康專線 2466 7350",
  "急症室 / 999 999",
  "〔打開緊急求助頁〕",
].join("\n");

const ts = (iso) => admin.firestore.Timestamp.fromDate(new Date(iso));

// A schema 2 row (decision 0069, TranscriptRow.toMap).
function v2(sessionId, f) {
  return {
    sessionId,
    agentId: f.agentId || "siu_yan",
    moduleId: f.moduleId || "m2_check_in",
    role: f.role,
    userText: f.userText === undefined ? null : f.userText,
    userInput: f.userInput === undefined ? null : f.userInput,
    replyText: f.replyText,
    replyStatus: f.replyStatus,
    userSentAt: f.userSentAt ? ts(f.userSentAt) : null,
    replyShownAt: ts(f.replyShownAt),
    receivedAt: ts(f.receivedAt),
    schemaVersion: 2,
  };
}

/**
 * Doc ids are deliberately NOT in time order, and one row reached the
 * server late (offline queue): the order must come from the row times.
 */
const ROWS = {
  // Session S1 — an older build (schema 1), 10/19 21:00 HKT.
  "m9v1b": {sessionId: "S1", agentId: "siu_yan", moduleId: "siu_yan_chat",
    userText: "今日去咗飲茶。", replyText: "聽落幾開心喎。", replyStatus: "ok",
    userSentAt: ts("2026-10-19T13:00:00Z"),
    replyShownAt: ts("2026-10-19T13:00:05Z"),
    receivedAt: ts("2026-10-19T13:00:06Z"), schemaVersion: 1},
  "b2v1a": {sessionId: "S1", agentId: "siu_yan", moduleId: "siu_yan_chat",
    userText: "仲去咗街市。", replyText: "買咗啲咩呀？", replyStatus: "ok",
    userSentAt: ts("2026-10-19T13:01:00Z"),
    replyShownAt: ts("2026-10-19T13:01:04Z"),
    receivedAt: ts("2026-10-19T13:01:05Z"), schemaVersion: 1},
  // Session S2 — check-in, 10/21 07:30 HKT (still 10/20 in UTC).
  "zc0": v2("S2", {role: "companion", replyText: `${Q0}\n\n${Q1}`,
    replyStatus: "fixed_reply", replyShownAt: "2026-10-20T23:30:00Z",
    receivedAt: "2026-10-20T23:30:12Z"}),
  "kb1": v2("S2", {role: "elder", userText: "幾好", userInput: "button",
    replyText: Q2, replyStatus: "fixed_reply",
    userSentAt: "2026-10-20T23:30:10Z", replyShownAt: "2026-10-20T23:30:11Z",
    receivedAt: "2026-10-20T23:45:00Z"}),
  "ab2": v2("S2", {role: "elder", userText: "唔講住", userInput: "button",
    replyText: `${XG}\n\n${Q4}`, replyStatus: "rule_based",
    userSentAt: "2026-10-20T23:31:00Z", replyShownAt: "2026-10-20T23:31:02Z",
    receivedAt: "2026-10-20T23:31:31Z"}),
  "qt3": v2("S2", {role: "elder", userText: "下晝去公園行下",
    userInput: "text", replyText: `${R4A}\n\n${Q5}`,
    replyStatus: "rule_based", userSentAt: "2026-10-20T23:31:30Z",
    replyShownAt: "2026-10-20T23:31:32Z",
    receivedAt: "2026-10-20T23:32:01Z"}),
  "cb4": v2("S2", {role: "elder", userText: "唔使喇", userInput: "button",
    replyText: Q6, replyStatus: "fixed_reply",
    userSentAt: "2026-10-20T23:32:00Z", replyShownAt: "2026-10-20T23:32:01Z",
    receivedAt: "2026-10-20T23:33:00Z"}),
  // Session S3 — 10/21 10:00 HKT: SY0, then the acute sentence.
  "xc5": v2("S3", {role: "companion", moduleId: "siu_yan_chat",
    replyText: SY0, replyStatus: "rule_based",
    replyShownAt: "2026-10-21T02:00:00Z", receivedAt: "2026-10-21T02:00:21Z"}),
  "de6": v2("S3", {role: "elder", moduleId: "siu_yan_chat",
    userText: ACUTE, userInput: "text", replyText: CRISIS,
    replyStatus: "short_circuited", userSentAt: "2026-10-21T02:00:20Z",
    replyShownAt: "2026-10-21T02:00:21Z",
    receivedAt: "2026-10-21T02:00:22Z"}),
};

async function reset() {
  for (const p of ["users", "enrollments"]) {
    await db.recursiveDelete(db.collection(p));
  }
}

async function seed() {
  await db.doc(`users/${TESTER}`).set({isTester: true, arm: "B",
    email: TESTER_MAIL, displayName: "Synth"});
  for (const [id, row] of Object.entries(ROWS)) {
    const data = Object.assign({turnId: id}, row);
    await db.doc(`users/${TESTER}/chat_transcripts/${id}`).set(data);
  }
  // A participant: enrolled, no isTester.  Its rows must never be read.
  await db.doc(`users/${PARTICIPANT}`).set({arm: "A",
    email: PARTICIPANT_MAIL});
  await db.doc(`enrollments/${PARTICIPANT}`).set({researchId: RESEARCH_ID,
    arm: "A"});
  await db.doc(`users/${PARTICIPANT}/chat_transcripts/p1`).set(v2("P1", {
    role: "elder", userText: SECRET, userInput: "text", replyText: SECRET,
    replyStatus: "ok", userSentAt: "2026-10-21T01:00:00Z",
    replyShownAt: "2026-10-21T01:00:02Z",
    receivedAt: "2026-10-21T01:00:03Z"}));
  // isTester as the string "true" is not a tester.
  await db.doc(`users/${STRING_FLAG}`).set({isTester: "true"});
  await db.doc(`users/${STRING_FLAG}/chat_transcripts/s1`).set(v2("P2", {
    role: "companion", replyText: SECRET, replyStatus: "fixed_reply",
    replyShownAt: "2026-10-21T01:00:00Z",
    receivedAt: "2026-10-21T01:00:01Z"}));
  // No users doc, rows anyway.
  await db.doc(`users/${MISSING}/chat_transcripts/m1`).set(v2("P3", {
    role: "companion", replyText: SECRET, replyStatus: "fixed_reply",
    replyShownAt: "2026-10-21T01:00:00Z",
    receivedAt: "2026-10-21T01:00:01Z"}));
}

async function countAll() {
  let n = 0;
  async function walk(ref) {
    for (const c of await ref.listCollections()) {
      for (const d of (await c.get()).docs) {
        n++;
        await walk(d.ref);
      }
    }
  }
  await walk(db);
  return n;
}

// Records every database call the tool makes (only these three exist).
function spyDb(real) {
  const calls = [];
  return {
    calls,
    doc(p) {
      calls.push({op: "doc", path: p});
      return real.doc(p);
    },
    getAll(...a) {
      const last = a[a.length - 1];
      calls.push({op: "getAll",
        paths: a.filter((x) => x && x.path).map((x) => x.path),
        fieldMask: last && last.fieldMask ? last.fieldMask : null});
      return real.getAll(...a);
    },
    collection(p) {
      calls.push({op: "collection", path: p});
      const c = real.collection(p);
      return {
        get() {
          calls.push({op: "get", path: p});
          return c.get();
        },
        select(...fields) {
          calls.push({op: "select", path: p, fields});
          return c.select(...fields);
        },
      };
    },
  };
}

function capture() {
  const out = {lines: [], errors: []};
  out.log = (s) => out.lines.push(s);
  out.error = (s) => out.errors.push(s);
  return out;
}

function cli(args, extraEnv) {
  return spawnSync(process.execPath, [SCRIPT].concat(args || []),
      {env: Object.assign({}, process.env,
          {NODE_PATH, GCLOUD_PROJECT: PROJECT}, extraEnv || {}),
      encoding: "utf8"});
}

// Never an e-mail, a research ID, an arm or a participant's words.
function assertNothingPrivate(text) {
  assert.ok(!text.includes(TESTER_MAIL), "tester e-mail printed");
  assert.ok(!text.includes(PARTICIPANT_MAIL), "participant e-mail printed");
  assert.ok(!text.includes(RESEARCH_ID), "research ID printed");
  assert.ok(!text.includes(SECRET), "a participant's words printed");
  assert.doesNotMatch(text, /\barm\b|@/i);
}

// Positions of [needles] in [text] must rise.
function assertOrder(text, needles) {
  let last = -1;
  for (const n of needles) {
    const i = text.indexOf(n);
    assert.ok(i >= 0, `missing: ${n}`);
    assert.ok(i > last, `out of order: ${n}`);
    last = i;
  }
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("tester: schema 1 + 2 rows in time order, grouped by session; " +
    "line breaks kept; writes nothing; nothing private printed", async () => {
  const before = await countAll();
  const r = cli([`--uid=${TESTER}`]);
  assert.strictEqual(r.status, 0, r.stderr);
  const out = r.stdout;
  assert.match(out, /账号 synthReadTxTester000000001：测试员（isTester = true）✓/);
  assert.match(out, /共 9 行；显示 9 行，3 个会话。/);
  for (const h of [
    "══ 会话 1/3 · sessionId: S1 · 2 行 · " +
      "2026-10-19 21:00:00 至 2026-10-19 21:01:00",
    "══ 会话 2/3 · sessionId: S2 · 5 行 · " +
      "2026-10-21 07:30:00 至 2026-10-21 07:32:00",
    "══ 会话 3/3 · sessionId: S3 · 2 行 · " +
      "2026-10-21 10:00:00 至 2026-10-21 10:00:20",
  ]) {
    assert.ok(out.includes(h), h);
  }
  // Time order: schema 1 first, then the check-in (the late-arriving 幾好
  // still second), then SY0 before the acute sentence.
  assertOrder(out, [
    "userText: 今日去咗飲茶。", "userText: 仲去咗街市。",
    "        " + Q0, "userText: 幾好", "userText: 唔講住",
    "userText: 下晝去公園行下", "userText: 唔使喇",
    "        " + SY0, "userText: " + ACUTE,
  ]);
  // Schema 1 rows say they have no role / userInput.
  assert.strictEqual(out.split("schema 1 旧格式，没有这个字段").length - 1, 2);
  assert.strictEqual(out.split("userInput: —（schema 1 旧格式没有）")
      .length - 1, 2);
  // Schema 2: two companion rows, three buttons, two typed.
  assert.strictEqual(out.split("role: companion").length - 1, 2);
  assert.strictEqual(out.split("userInput: button").length - 1, 3);
  assert.strictEqual(out.split("userInput: text").length - 1, 2);
  // Companion rows are timed by replyShownAt, elder rows by userSentAt.
  assert.match(out, /\[3\] 2026-10-21 07:30:00（香港时间，按 replyShownAt）/);
  assert.match(out, /\[4\] 2026-10-21 07:30:10（香港时间，按 userSentAt）/);
  // Two bubbles, blank line between, indented; the crisis message is one
  // bubble of six lines.
  assert.ok(out.includes(`replyText（2 个气泡，气泡之间空一行）:\n` +
      `        ${Q0}\n\n        ${Q1}\n`));
  assert.ok(out.includes(`        ${XG}\n\n        ${Q4}\n`));
  assert.ok(out.includes("replyText（1 个气泡）:\n" +
      CRISIS.split("\n").map((l) => `        ${l}`).join("\n") + "\n"));
  assert.ok(out.includes(
      "replyStatus: short_circuited   schemaVersion: 2   turnId: de6"));
  assert.ok(out.includes(
      "replyStatus: fixed_reply   schemaVersion: 2   turnId: zc0"));
  assertNothingPrivate(out + r.stderr);
  assert.strictEqual(await countAll(), before, "nothing written");
});

test("--since is a Hong Kong date; --limit keeps the latest rows", () => {
  const since = cli([`--uid=${TESTER}`, "--since=2026-10-21"]);
  assert.strictEqual(since.status, 0, since.stderr);
  assert.match(since.stdout,
      /共 9 行；显示 7 行，2 个会话（按 --since=2026-10-21）。/);
  assert.ok(!since.stdout.includes("今日去咗飲茶"));
  // 07:30 HKT on 10/21 is 23:30 UTC on 10/20: still included.
  assert.ok(since.stdout.includes("userText: 幾好"));
  const limit = cli([`--uid=${TESTER}`, "--limit=2"]);
  assert.strictEqual(limit.status, 0, limit.stderr);
  assert.match(limit.stdout, /显示 2 行，1 个会话（按 --limit=2）。/);
  assert.ok(!limit.stdout.includes("userText: 唔使喇"));
  assertOrder(limit.stdout, ["        " + SY0, "userText: " + ACUTE]);
});

test("--json: the same rows and order, exact replyText", () => {
  const r = cli([`--uid=${TESTER}`, "--json"]);
  assert.strictEqual(r.status, 0, r.stderr);
  const j = JSON.parse(r.stdout);
  assert.strictEqual(j.mode, "rows");
  assert.strictEqual(j.isTester, true);
  assert.strictEqual(j.totalRows, 9);
  assert.deepStrictEqual(j.sessions.map((s) => s.sessionId),
      ["S1", "S2", "S3"]);
  const [s1, s2, s3] = j.sessions;
  assert.deepStrictEqual(s1.rows.map((x) => [x.role, x.schemaVersion]),
      [[null, 1], [null, 1]]);
  assert.deepStrictEqual(s2.rows.map((x) => [x.role, x.userInput,
    x.userText]), [
    ["companion", null, null],
    ["elder", "button", "幾好"],
    ["elder", "button", "唔講住"],
    ["elder", "text", "下晝去公園行下"],
    ["elder", "button", "唔使喇"],
  ]);
  assert.strictEqual(s2.rows[0].replyText, `${Q0}\n\n${Q1}`);
  assert.strictEqual(s2.rows[0].timeField, "replyShownAt");
  assert.strictEqual(s2.rows[0].time, "2026-10-21 07:30:00");
  assert.strictEqual(s2.rows[0].userSentAt, null);
  assert.strictEqual(s2.rows[1].turnId, "kb1");
  assert.strictEqual(s3.rows[1].replyText, CRISIS);
  assert.strictEqual(s3.rows[1].replyStatus, "short_circuited");
  assertNothingPrivate(r.stdout);
});

test("non-tester, isTester \"true\" (string), no account: refused " +
    "before any transcript is read", async () => {
  for (const uid of [PARTICIPANT, STRING_FLAG, MISSING]) {
    const spy = spyDb(db);
    const out = capture();
    const res = await tool.run(spy, {uid, json: false, since: null,
      sinceText: null, limit: null, mode: "full", target: "test"}, out);
    assert.strictEqual(res.status, 3, uid);
    assert.deepStrictEqual(out.lines, [], `${uid}: nothing on stdout`);
    // Exactly one read: users/{uid}, field mask isTester only.
    assert.deepStrictEqual(spy.calls, [
      {op: "doc", path: `users/${uid}`},
      {op: "getAll", paths: [`users/${uid}`], fieldMask: ["isTester"]},
    ], uid);
    assert.ok(!JSON.stringify(spy.calls).includes("chat_transcripts"));
    const msg = out.errors.join("\n");
    if (uid === MISSING) {
      assert.match(msg, /不存在，没有读取任何原文/);
    } else {
      assert.match(msg, /不是测试员账号（isTester 不是 true），没有读取任何原文/);
      assert.match(msg, /真实参与者的原文一律不读/);
      assert.match(msg, /冻结后再做/);
    }
    assertNothingPrivate(msg);
  }
  // The command line: exit 3, the reason on stderr, nothing else.
  const r = cli([`--uid=${PARTICIPANT}`]);
  assert.strictEqual(r.status, 3, r.stderr);
  assert.match(r.stderr, /拒绝：users\/synthReadTxParticipant0002 不是测试员账号/);
  assert.strictEqual(r.stdout, "");
  assertNothingPrivate(r.stdout + r.stderr);
  const j = cli([`--uid=${PARTICIPANT}`, "--json"]);
  assert.strictEqual(j.status, 3);
  assert.strictEqual(j.stdout, "");
});

test("tester: the account check is the first read, the transcript after",
    async () => {
      const spy = spyDb(db);
      const out = capture();
      const res = await tool.run(spy, {uid: TESTER, json: false,
        since: null, sinceText: null, limit: null, mode: "full",
        target: "test"}, out);
      assert.strictEqual(res.status, 0);
      assert.strictEqual(res.rows, 9);
      assert.deepStrictEqual(spy.calls.map((c) => c.op),
          ["doc", "getAll", "collection", "get"]);
      assert.deepStrictEqual(spy.calls[1].fieldMask, ["isTester"]);
      assert.strictEqual(spy.calls[2].path,
          `users/${TESTER}/chat_transcripts`);
    });

test("dry run (real project, no --production): account check and counts; " +
    "reads only the time fields, prints no text", async () => {
  const spy = spyDb(db);
  const out = capture();
  const res = await tool.run(spy, {uid: TESTER, json: false,
    since: new Date("2026-10-21T00:00:00+08:00"), sinceText: "2026-10-21",
    limit: null, mode: "count", target: "REAL PROJECT x"}, out);
  assert.strictEqual(res.status, 0);
  const text = out.lines.join("\n");
  assert.match(text, /试运行（dry run）/);
  assert.match(text, /测试员（isTester = true）✓/);
  assert.match(text, /共 9 行；会显示 7 行，2 个会话（按 --since=2026-10-21）。/);
  assert.match(text, /加 --production 再跑一次/);
  for (const w of [Q0, "幾好", ACUTE, "今日去咗飲茶", "replyText", "S2"]) {
    assert.ok(!text.includes(w), `dry run printed ${w}`);
  }
  assert.deepStrictEqual(spy.calls.map((c) => c.op),
      ["doc", "getAll", "collection", "select"]);
  assert.deepStrictEqual(spy.calls[3].fields,
      ["sessionId", "userSentAt", "replyShownAt", "receivedAt"]);
  // --json dry run: counts only.
  const j = capture();
  await tool.run(db, {uid: TESTER, json: true, since: null, sinceText: null,
    limit: null, mode: "count", target: "REAL PROJECT x"}, j);
  const parsed = JSON.parse(j.lines.join("\n"));
  assert.strictEqual(parsed.mode, "dry_run");
  assert.strictEqual(parsed.rows, 9);
  assert.strictEqual(parsed.sessionCount, 3);
  assert.strictEqual(parsed.sessions, undefined);
});

test("mode: emulator shows rows; a real project only with --production",
    () => {
      assert.strictEqual(tool.decideMode({target: "emulator"}, {}), "full");
      assert.strictEqual(tool.decideMode({target: "production"}, {}),
          "count");
      assert.strictEqual(tool.decideMode({target: "production"},
          {production: true}), "full");
      assert.strictEqual(tool.decideMode({target: "production"},
          {production: "yes"}), "count");
    });

test("row time: userSentAt, else replyShownAt, else receivedAt", () => {
  const a = new Date("2026-10-21T01:00:00Z");
  const b = new Date("2026-10-21T02:00:00Z");
  const c = new Date("2026-10-21T03:00:00Z");
  assert.deepStrictEqual(tool.sortTime({userSentAt: a, replyShownAt: b,
    receivedAt: c}), {at: a, field: "userSentAt"});
  assert.deepStrictEqual(tool.sortTime({userSentAt: null, replyShownAt: b,
    receivedAt: c}), {at: b, field: "replyShownAt"});
  assert.deepStrictEqual(tool.sortTime({receivedAt: c}),
      {at: c, field: "receivedAt"});
  assert.strictEqual(tool.bubbleCount(`${Q0}\n\n${Q1}`), 2);
  assert.strictEqual(tool.bubbleCount(CRISIS), 1);
  assert.strictEqual(tool.bubbleCount(""), 0);
});

test("guard and options: exit 2 and nothing read", () => {
  const off = {FIRESTORE_EMULATOR_HOST: ""};
  const cases = [
    [[`--uid=${TESTER}`, `--project=${PROJECT}`], off,
      /拒绝运行：.*production-confirm/],
    [[`--uid=${TESTER}`], off, /拒绝运行：not on the emulator/],
    [[`--uid=${TESTER}`, "--production"], {}, /--production，目标不清楚/],
    [[`--uid=${TESTER}`, `--production-confirm=${PROJECT}`], {},
      /拒绝运行：--production-confirm given but FIRESTORE_EMULATOR_HOST/],
    [[], {}, /要给 --uid=/],
    [["--uid=a/b"], {}, /要给 --uid=/],
    [[`--uid=${TESTER}`, "--since=2026/10/21"], {}, /--since 要写成 YYYY-MM-DD/],
    [[`--uid=${TESTER}`, "--since=2026-02-30"], {}, /--since 要写成/],
    [[`--uid=${TESTER}`, "--limit=0"], {}, /--limit 要写正整数/],
    [[`--uid=${TESTER}`, "--limit"], {}, /--limit 要写正整数/],
  ];
  for (const [args, env, re] of cases) {
    const r = cli(args, env);
    assert.strictEqual(r.status, 2, `${args.join(" ")}: ${r.stderr}`);
    assert.match(r.stderr, re, args.join(" "));
    assert.strictEqual(r.stdout, "", args.join(" "));
  }
});

(async () => {
  await reset();
  await seed();
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ✓ ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`  ✗ ${t.name}\n    ${err.stack}`);
    }
  }
  await reset();
  console.log(failed ? `${failed} failed` : `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();

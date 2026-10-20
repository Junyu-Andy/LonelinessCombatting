/**
 * 1021 — tests for tool/add_readers.sh (logic in tool/add_readers.js).
 *
 *   node test/reader_html_check/add_readers_test.js
 *
 * Each test builds a throw-away copy of the repository layout (tool/ with
 * the three scripts, assets/readers/manifest.json = [], a few other files)
 * in a temp folder and runs the real shell script there, so the real
 * assets/readers/ is never touched.  Zips are written by a small writer
 * below (it can make the unsafe ones a normal zip tool would refuse to);
 * one test also uses the `zip` command when it is installed.
 */
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.resolve(__dirname, "..", "..");
const A = require(path.join(ROOT, "tool", "add_readers.js"));
const FIX = path.join(__dirname, "fixtures");

const tests = [];
const test = (name, fn) => tests.push({name: name, fn: fn});
const tempDirs = [];

const GOOD_HTML = fs.readFileSync(path.join(FIX, "good", "u1_good.html"), "utf8");
const GOOD_TXT = fs.readFileSync(path.join(FIX, "good", "u1_good.txt"), "utf8");

/** A passing unit with this id (and a 測試 title). */
function goodUnit(id, order) {
  return {
    entry: {id: id, titleZh: `測試：${id}`, minutes: 3, order: order},
    files: {
      [`${id}.html`]: GOOD_HTML,
      [`${id}.txt`]: GOOD_TXT,
    },
  };
}

/** A unit that fails check (1) and (4). */
function badUnit(id, order) {
  return {
    entry: {id: id, titleZh: `測試：${id}`, minutes: 3, order: order},
    files: {
      [`${id}.html`]: GOOD_HTML.replace("</section>",
          '<img src="https://x.example/a.png"><p>AI 講解</p></section>'),
      [`${id}.txt`]: GOOD_TXT,
    },
  };
}

/**
 * @param {Array<{name: string, data: (string|Buffer|undefined),
 *     method: (number|undefined), mode: (number|undefined),
 *     host: (number|undefined), flags: (number|undefined),
 *     declaredSize: (number|undefined)}>} entries
 * @return {Buffer} a zip
 */
function makeZip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    const data = Buffer.isBuffer(e.data) ? e.data : Buffer.from(e.data || "", "utf8");
    const method = e.method === undefined ? 8 : e.method;
    const comp = method === 8 ? zlib.deflateRawSync(data) : data;
    const name = Buffer.from(e.name, "utf8");
    const crc = A.crc32(data);
    const size = e.declaredSize === undefined ? data.length : e.declaredSize;
    const flags = (e.flags || 0) | 0x800;
    const host = e.host === undefined ? 3 : e.host;
    const mode = e.mode === undefined ? (/\/$/.test(e.name) ? 0o040755 : 0o100644) : e.mode;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);
    lh.writeUInt16LE(flags, 6);
    lh.writeUInt16LE(method, 8);
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(comp.length, 18);
    lh.writeUInt32LE(size, 22);
    lh.writeUInt16LE(name.length, 26);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE((host << 8) | 20, 4);
    ch.writeUInt16LE(20, 6);
    ch.writeUInt16LE(flags, 8);
    ch.writeUInt16LE(method, 10);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(comp.length, 20);
    ch.writeUInt32LE(size, 24);
    ch.writeUInt16LE(name.length, 28);
    ch.writeUInt32LE((mode << 16) >>> 0, 38);
    ch.writeUInt32LE(offset, 42);
    parts.push(lh, name, comp);
    central.push(ch, name);
    offset += 30 + name.length + comp.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat(parts.concat([cd, end]));
}

/**
 * Zip entries for units (+ manifest.json), optionally inside a folder.
 * @param {Array<object>} units goodUnit / badUnit results
 * @param {{prefix: (string|undefined), extra: (Array<object>|undefined),
 *     manifest: (*|undefined)}} opts
 * @return {Buffer}
 */
function unitsZip(units, opts) {
  const o = opts || {};
  const prefix = o.prefix || "";
  const entries = [];
  if (prefix) entries.push({name: prefix});
  const manifest = o.manifest !== undefined ? o.manifest : units.map((u) => u.entry);
  entries.push({name: `${prefix}manifest.json`,
    data: typeof manifest === "string" ? manifest : JSON.stringify(manifest, null, 2)});
  units.forEach((u, i) => {
    for (const f of Object.keys(u.files)) {
      // Mix stored and deflated entries.
      entries.push({name: prefix + f, data: u.files[f], method: i % 2 ? 0 : 8});
    }
  });
  return makeZip(entries.concat(o.extra || []));
}

/**
 * A fake repository: tool/ (the scripts), assets/readers/manifest.json
 * `[]`, and files that must never change.  Also an `outside/` folder next
 * to it, to catch writes that escape.
 * @return {{base: string, root: string, readers: string, outside: string}}
 */
function fakeRepo() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), "add-readers-test-"));
  tempDirs.push(base);
  const root = path.join(base, "repo");
  fs.mkdirSync(path.join(root, "tool"), {recursive: true});
  for (const f of ["add_readers.sh", "add_readers.js", "check_reader_html.js"]) {
    fs.copyFileSync(path.join(ROOT, "tool", f), path.join(root, "tool", f));
  }
  fs.chmodSync(path.join(root, "tool", "add_readers.sh"), 0o755);
  const readers = path.join(root, "assets", "readers");
  fs.mkdirSync(readers, {recursive: true});
  fs.writeFileSync(path.join(readers, "manifest.json"), "[]\n");
  fs.mkdirSync(path.join(root, "lib"), {recursive: true});
  fs.writeFileSync(path.join(root, "lib", "main.dart"), "// app\n");
  fs.writeFileSync(path.join(root, "assets", "other.txt"), "keep me\n");
  fs.writeFileSync(path.join(root, "pubspec.yaml"), "name: app_demo\n");
  const outside = path.join(base, "outside");
  fs.mkdirSync(outside);
  return {base: base, root: root, readers: readers, outside: outside};
}

/** Every file under dir → its content (base64), for before/after compares. */
function snapshot(dir, skip) {
  const out = {};
  (function walk(d) {
    for (const f of fs.readdirSync(d).sort()) {
      const full = path.join(d, f);
      if (skip && full === skip) continue;
      const st = fs.lstatSync(full);
      if (st.isDirectory()) walk(full);
      else out[path.relative(dir, full)] = st.isSymbolicLink() ?
        `link:${fs.readlinkSync(full)}` : fs.readFileSync(full).toString("base64");
    }
  })(dir);
  return out;
}

function writeZip(repo, name, buf) {
  const p = path.join(repo.base, name);
  fs.writeFileSync(p, buf);
  return p;
}

/** Run the real shell script from an unrelated working folder. */
function run(repo, args) {
  const r = childProcess.spawnSync("bash",
      [path.join(repo.root, "tool", "add_readers.sh")].concat(args),
      {cwd: repo.outside, encoding: "utf8"});
  return {status: r.status, out: r.stdout + r.stderr};
}

const manifestIds = (repo) => JSON.parse(
    fs.readFileSync(path.join(repo.readers, "manifest.json"), "utf8")).map((e) => e.id);
const filesIn = (dir) => fs.readdirSync(dir).sort();

test("good + bad unit: only the good one lands (folder and manifest); exit 2; " +
    "the reasons and the six-check labels are printed", () => {
  const repo = fakeRepo();
  const zip = writeZip(repo, "r.zip", unitsZip([goodUnit("zz_test_pass", 1),
    badUnit("zz_test_fail", 2)]));
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 2, r.out);
  assert.deepStrictEqual(filesIn(repo.readers),
      ["manifest.json", "zz_test_pass.html", "zz_test_pass.txt"]);
  assert.deepStrictEqual(manifestIds(repo), ["zz_test_pass"]);
  assert.ok(/通过    zz_test_pass/.test(r.out), r.out);
  assert.ok(/不通过  zz_test_fail/.test(r.out), r.out);
  assert.ok(r.out.indexOf("[external_resource]（第 1 项 外部资源、链接）") >= 0, r.out);
  assert.ok(r.out.indexOf("[forbidden_word]（第 4 项 不准用的字）") >= 0, r.out);
  assert.ok(r.out.indexOf("复核整个文件夹（和 CI 同一个检查") >= 0, r.out);
  assert.ok(/zip 的 SHA-256：[0-9a-f]{64}/.test(r.out), r.out);
  // The manifest written: the four fields, sorted, a trailing newline.
  const text = fs.readFileSync(path.join(repo.readers, "manifest.json"), "utf8");
  assert.deepStrictEqual(JSON.parse(text),
      [{id: "zz_test_pass", titleZh: "測試：zz_test_pass", minutes: 3, order: 1}]);
  assert.ok(/\n$/.test(text));
});

test("re-running the same zip gives the same folder, byte for byte", () => {
  const repo = fakeRepo();
  const zip = writeZip(repo, "r.zip", unitsZip([goodUnit("u2_b", 2),
    goodUnit("u1_a", 1), badUnit("u3_c", 3)]));
  assert.strictEqual(run(repo, [zip]).status, 2);
  const first = snapshot(repo.readers);
  assert.strictEqual(run(repo, [zip]).status, 2);
  assert.deepStrictEqual(snapshot(repo.readers), first);
  assert.deepStrictEqual(manifestIds(repo), ["u1_a", "u2_b"]);
});

test("all pass: exit 0; nothing outside assets/readers/ changes", () => {
  const repo = fakeRepo();
  const before = snapshot(repo.base, repo.readers);
  const zip = writeZip(repo, "r.zip", unitsZip([goodUnit("u1_a", 1)]));
  const after0 = snapshot(repo.base, repo.readers);
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 0, r.out);
  const after = snapshot(repo.base, repo.readers);
  // Only the zip we wrote is new.
  delete after0["r.zip"];
  assert.deepStrictEqual(before, after0);
  assert.deepStrictEqual(after, snapshot(repo.base, repo.readers));
  assert.deepStrictEqual(Object.keys(after).sort(),
      Object.keys(before).concat(["r.zip"]).sort());
  // No temp folder left behind.
  assert.deepStrictEqual(fs.readdirSync(os.tmpdir()).filter((f) =>
    f.indexOf("peizhu-readers-") === 0 &&
    fs.statSync(path.join(os.tmpdir(), f)).mtimeMs > Date.now() - 60000), []);
});

test("files inside one folder, with __MACOSX / .DS_Store junk: accepted; " +
    "unknown files and sub-folders are listed and not taken", () => {
  const repo = fakeRepo();
  const marker = path.join(repo.outside, "ran");
  const zip = writeZip(repo, "r.zip", unitsZip([goodUnit("u1_a", 1)], {
    prefix: "小讀本/",
    extra: [
      {name: "__MACOSX/"},
      {name: "__MACOSX/小讀本/._u1_a.html", data: "x"},
      {name: "小讀本/.DS_Store", data: "x"},
      {name: "小讀本/run.sh", data: `#!/bin/sh\ntouch ${marker}\n`, mode: 0o100755},
      {name: "小讀本/x.js", data: `require("fs").writeFileSync(${JSON.stringify(marker)}, "")`},
      {name: "小讀本/images/", mode: 0o040755},
      {name: "小讀本/images/a.png", data: "png"},
      {name: "小讀本/U9 Bad.html", data: "x"},
    ],
  }));
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 0, r.out);
  assert.deepStrictEqual(filesIn(repo.readers),
      ["manifest.json", "u1_a.html", "u1_a.txt"]);
  for (const n of ["run.sh", "x.js", "images/a.png", "U9 Bad.html"]) {
    assert.ok(r.out.indexOf(`不收：小讀本/${n}`) >= 0, `${n} listed: ${r.out}`);
  }
  assert.ok(r.out.indexOf("在文件夹 小讀本/ 里") >= 0, r.out);
  assert.ok(!fs.existsSync(marker), "nothing from the zip was run");
});

test("<id>.explain.json: a good one is copied; a broken one is dropped and " +
    "the unit still lands; an orphan one fails like any lone file", () => {
  const repo = fakeRepo();
  const u1 = goodUnit("u1_a", 1);
  u1.files["u1_a.explain.json"] = JSON.stringify({cards: [{q: "點解？", a: "因為。"}]});
  const u2 = goodUnit("u2_b", 2);
  u2.files["u2_b.explain.json"] = "{not json";
  const zip = writeZip(repo, "r.zip", unitsZip([u1, u2], {extra: [
    {name: "u9_orphan.explain.json", data: "{}"},
  ]}));
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 2, r.out); // u9_orphan fails
  assert.deepStrictEqual(filesIn(repo.readers), ["manifest.json",
    "u1_a.explain.json", "u1_a.html", "u1_a.txt", "u2_b.html", "u2_b.txt"]);
  assert.deepStrictEqual(manifestIds(repo), ["u1_a", "u2_b"]);
  assert.ok(r.out.indexOf("u2_b.explain.json：不是有效的 JSON") >= 0, r.out);
  assert.ok(/不通过  u9_orphan/.test(r.out), r.out);
});

test("unsafe zips are refused whole: nothing in assets/readers/ changes and " +
    "nothing is written outside", () => {
  const cases = [
    {why: "..", extra: [{name: "../evil.txt", data: "x"}]},
    {why: "..", extra: [{name: "a/../../evil.txt", data: "x"}]},
    {why: "绝对路径", extra: [{name: "/tmp/evil.txt", data: "x"}]},
    {why: "绝对路径", extra: [{name: "C:/evil.txt", data: "x"}]},
    {why: "反斜杠", extra: [{name: "..\\evil.txt", data: "x"}]},
    {why: "链接", extra: [{name: "u9_link.html", data: "/etc/passwd", mode: 0o120777}]},
    {why: "加了密码", extra: [{name: "u9.txt", data: "x", flags: 1}]},
    {why: "出现两次", extra: [{name: "u1_a.txt", data: "again"}]},
    {why: "不是普通文件", extra: [{name: "fifo", data: "", mode: 0o010644}]},
    {why: "太大", extra: [{name: "u9_big.txt", data: "x", declaredSize: 9 * 1024 * 1024}]},
  ];
  for (const c of cases) {
    const repo = fakeRepo();
    // Something already shipped, to see that it stays.
    assert.strictEqual(run(repo, [writeZip(repo, "ok.zip",
        unitsZip([goodUnit("u0_old", 0)]))]).status, 0);
    const before = snapshot(repo.base);
    const zip = writeZip(repo, "bad.zip", unitsZip([goodUnit("u1_a", 1)], {extra: c.extra}));
    const r = run(repo, [zip]);
    assert.strictEqual(r.status, 1, `${c.extra[0].name}: ${r.out}`);
    assert.ok(r.out.indexOf(c.why) >= 0, `${c.extra[0].name} → ${c.why}: ${r.out}`);
    assert.ok(r.out.indexOf("没有任何改动") >= 0, r.out);
    const after = snapshot(repo.base);
    delete after["bad.zip"];
    assert.deepStrictEqual(after, before, c.extra[0].name);
    assert.ok(!fs.existsSync(path.join(repo.base, "evil.txt")));
    assert.ok(!fs.existsSync(path.join(repo.root, "assets", "evil.txt")));
  }
});

test("a symlink made by the zip command (zip -y) is refused", () => {
  if (childProcess.spawnSync("zip", ["-v"]).status !== 0) {
    console.log("  (zip command not installed: skipped)");
    return;
  }
  const repo = fakeRepo();
  const src = path.join(repo.base, "src");
  fs.mkdirSync(src);
  fs.writeFileSync(path.join(src, "manifest.json"), "[]");
  fs.symlinkSync("/etc/passwd", path.join(src, "u1_a.txt"));
  const zip = path.join(repo.base, "link.zip");
  const z = childProcess.spawnSync("zip", ["-q", "-y", "-r", zip, "."], {cwd: src});
  assert.strictEqual(z.status, 0);
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 1, r.out);
  assert.ok(r.out.indexOf("链接") >= 0, r.out);
  assert.deepStrictEqual(filesIn(repo.readers), ["manifest.json"]);
});

test("the zip command's own zip of a folder works (deflate, folder entry)", () => {
  if (childProcess.spawnSync("zip", ["-v"]).status !== 0) {
    console.log("  (zip command not installed: skipped)");
    return;
  }
  const repo = fakeRepo();
  const src = path.join(repo.base, "src", "readers");
  fs.mkdirSync(src, {recursive: true});
  const u = goodUnit("u1_a", 1);
  fs.writeFileSync(path.join(src, "manifest.json"), JSON.stringify([u.entry]));
  for (const f of Object.keys(u.files)) fs.writeFileSync(path.join(src, f), u.files[f]);
  const zip = path.join(repo.base, "folder.zip");
  assert.strictEqual(childProcess.spawnSync("zip", ["-q", "-r", zip, "readers"],
      {cwd: path.dirname(src)}).status, 0);
  const r = run(repo, [zip]);
  assert.strictEqual(r.status, 0, r.out);
  assert.deepStrictEqual(manifestIds(repo), ["u1_a"]);
  assert.strictEqual(fs.readFileSync(path.join(repo.readers, "u1_a.html"), "utf8"), GOOD_HTML);
});

test("default replaces the whole set; --keep keeps passing units the zip " +
    "does not bring", () => {
  const repo = fakeRepo();
  assert.strictEqual(run(repo, [writeZip(repo, "1.zip",
      unitsZip([goodUnit("u1_a", 1), goodUnit("u2_b", 2)]))]).status, 0);
  // --keep: a fix for u2 only (manifest names all, files only u2).
  const fix = goodUnit("u2_b", 2);
  fix.entry.titleZh = "測試：u2_b 改好";
  const r = run(repo, ["--keep", writeZip(repo, "2.zip", unitsZip([fix], {
    manifest: [goodUnit("u1_a", 1).entry, fix.entry],
  }))]);
  assert.strictEqual(r.status, 0, r.out);
  assert.deepStrictEqual(manifestIds(repo), ["u1_a", "u2_b"]);
  assert.ok(fs.readFileSync(path.join(repo.readers, "manifest.json"), "utf8")
      .indexOf("u2_b 改好") >= 0);
  // Default: the zip is the whole set.
  const r2 = run(repo, [writeZip(repo, "3.zip", unitsZip([goodUnit("u3_c", 3)]))]);
  assert.strictEqual(r2.status, 0, r2.out);
  assert.deepStrictEqual(filesIn(repo.readers), ["manifest.json", "u3_c.html", "u3_c.txt"]);
  assert.ok(r2.out.indexOf("原来有、现在没有了：u1_a、u2_b") >= 0, r2.out);
});

test("not a zip, a missing file, no manifest.json, bad manifest JSON, no " +
    "argument: exit 1, nothing changes", () => {
  const repo = fakeRepo();
  const before = snapshot(repo.readers);
  const bad = [
    [writeZip(repo, "plain.zip", Buffer.from("not a zip at all"))],
    [path.join(repo.base, "missing.zip")],
    [writeZip(repo, "nomani.zip", makeZip([{name: "u1_a.html", data: GOOD_HTML}]))],
    [writeZip(repo, "badmani.zip", unitsZip([goodUnit("u1_a", 1)], {manifest: "{oops"}))],
    [writeZip(repo, "objmani.zip", unitsZip([goodUnit("u1_a", 1)], {manifest: "{}"}))],
    [],
    ["a.zip", "b.zip"],
  ];
  for (const args of bad) {
    const r = run(repo, args);
    assert.strictEqual(r.status, 1, `${args}: ${r.out}`);
    assert.deepStrictEqual(snapshot(repo.readers), before, String(args));
  }
});

test("all pass: manifest.json lands exactly as it came (every field, byte " +
    "for byte); the 1021 fields are kept when a unit is left out", () => {
  const repo = fakeRepo();
  const a = goodUnit("u1_a", 1);
  Object.assign(a.entry, {part: 1, partTitleZh: "認識孤單", icon: "science"});
  const raw = JSON.stringify([a.entry], null, 1);
  const r = run(repo, [writeZip(repo, "r.zip", unitsZip([a], {manifest: raw}))]);
  assert.strictEqual(r.status, 0, r.out);
  assert.strictEqual(fs.readFileSync(path.join(repo.readers, "manifest.json"), "utf8"), raw);
  const r2 = run(repo, [writeZip(repo, "r2.zip", unitsZip([a, badUnit("u2_b", 2)]))]);
  assert.strictEqual(r2.status, 2, r2.out);
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(repo.readers, "manifest.json"),
      "utf8")), [a.entry]);
});

test("a unit whose 「讀下一篇」 points at a unit that failed fails too (no " +
    "dead link ships)", () => {
  const repo = fakeRepo();
  const a = goodUnit("u1_a", 1);
  a.files["u1_a.html"] = a.files["u1_a.html"].replace("</section>",
      '<a href="peizhu://reader/open?id=u2_b">讀下一篇</a></section>');
  const r = run(repo, [writeZip(repo, "r.zip", unitsZip([a, badUnit("u2_b", 2),
    goodUnit("u3_c", 3)]))]);
  assert.strictEqual(r.status, 2, r.out);
  assert.deepStrictEqual(manifestIds(repo), ["u3_c"]);
  assert.ok(/不通过  u1_a/.test(r.out), r.out);
  assert.ok(r.out.indexOf("[open_target_missing]") >= 0, r.out);
});

test("a link planted in assets/readers/ is replaced, not followed", () => {
  const repo = fakeRepo();
  const victim = path.join(repo.outside, "victim.txt");
  fs.writeFileSync(victim, "untouched");
  fs.symlinkSync(victim, path.join(repo.readers, "u1_a.txt"));
  const r = run(repo, [writeZip(repo, "r.zip", unitsZip([goodUnit("u1_a", 1)]))]);
  assert.strictEqual(r.status, 0, r.out);
  assert.strictEqual(fs.readFileSync(victim, "utf8"), "untouched");
  assert.ok(fs.lstatSync(path.join(repo.readers, "u1_a.txt")).isFile());
});

test("assets/readers itself a link: refused", () => {
  const repo = fakeRepo();
  const elsewhere = path.join(repo.outside, "readers");
  fs.renameSync(repo.readers, elsewhere);
  fs.symlinkSync(elsewhere, repo.readers);
  const before = snapshot(elsewhere);
  const r = run(repo, [writeZip(repo, "r.zip", unitsZip([goodUnit("u1_a", 1)]))]);
  assert.strictEqual(r.status, 1, r.out);
  assert.deepStrictEqual(snapshot(elsewhere), before);
});

let failed = 0;
for (const t of tests) {
  try {
    t.fn();
    console.log(`ok - ${t.name}`);
  } catch (e) {
    failed++;
    console.log(`not ok - ${t.name}\n  ${e.stack}`);
  }
}
for (const d of tempDirs) fs.rmSync(d, {recursive: true, force: true});
if (failed) {
  console.log(`${failed} add_readers test(s) failed`);
  process.exit(1);
}
console.log(`all ${tests.length} add_readers tests passed`);

/**
 * 1020c §3 — tests for tool/check_reader_html.js.
 *
 *   node test/reader_html_check/check_reader_html_test.js
 *
 * Fixtures: fixtures/good (one unit that must pass — comments, scripts,
 * data: images, SVG numbers and CSS colours are not mistaken for
 * problems), fixtures/bad (fails several rules; the CLI exits 1),
 * fixtures/empty (manifest `[]`, passes).  Each rule is also checked by
 * copying the good unit into a temp folder and breaking one thing.
 * The real assets/readers/ must pass too (it is committed as `[]`).
 */
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const TOOL = path.join(ROOT, "tool", "check_reader_html.js");
const C = require(TOOL);
const FIX = path.join(__dirname, "fixtures");

const tests = [];
const test = (name, fn) => tests.push({name: name, fn: fn});
const tempDirs = [];

const GOOD_HTML = fs.readFileSync(path.join(FIX, "good", "u1_good.html"), "utf8");
const GOOD_TXT = fs.readFileSync(path.join(FIX, "good", "u1_good.txt"), "utf8");
const GOOD_MANIFEST = [{id: "u1_good", titleZh: "測試讀本", minutes: 5, order: 1}];

/**
 * A temp folder holding the good unit, changed by `edit`.
 * @param {function(object): void} edit gets {html, txt, manifest, extra}
 * @return {string} the folder
 */
function unit(edit) {
  const u = {html: GOOD_HTML, txt: GOOD_TXT, manifest: GOOD_MANIFEST.slice(),
    extra: {}, id: "u1_good"};
  edit(u);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "reader-check-"));
  tempDirs.push(dir);
  if (u.manifest !== null) {
    fs.writeFileSync(path.join(dir, "manifest.json"),
        typeof u.manifest === "string" ? u.manifest : JSON.stringify(u.manifest));
  }
  if (u.html !== null) fs.writeFileSync(path.join(dir, `${u.id}.html`), u.html);
  if (u.txt !== null) fs.writeFileSync(path.join(dir, `${u.id}.txt`), u.txt);
  for (const f of Object.keys(u.extra)) {
    fs.writeFileSync(path.join(dir, f), u.extra[f]);
  }
  return dir;
}

const codes = (dir) => C.checkReaderDir(dir).problems.map((p) => p.code);

function fails(dir, code) {
  const c = codes(dir);
  assert.ok(c.indexOf(code) >= 0, `expected ${code}, got ${JSON.stringify(c)}`);
}

const htmlWith = (snippet) => (u) => {
  u.html = u.html.replace("</section>", `${snippet}\n</section>`);
};

function cli(dir) {
  return childProcess.spawnSync(process.execPath, [TOOL, dir], {encoding: "utf8"});
}

test("good fixture passes (1 unit); comments, scripts, data:, SVG numbers " +
    "and CSS colours are not problems", () => {
  const r = C.checkReaderDir(path.join(FIX, "good"));
  assert.deepStrictEqual(r.problems, []);
  assert.strictEqual(r.units, 1);
});

test("empty manifest passes; the real assets/readers/ passes, and has no " +
    "placeholder (zz_test…) unit", () => {
  assert.deepStrictEqual(C.checkReaderDir(path.join(FIX, "empty")).problems, []);
  const real = C.checkReaderDirByUnit(path.join(ROOT, "assets", "readers"));
  assert.deepStrictEqual(real.general, []);
  for (const u of real.units) assert.deepStrictEqual(u.problems, [], u.id);
  assert.ok(real.ok);
  for (const u of real.units) {
    assert.ok(u.id.indexOf("zz_test") !== 0, `placeholder ${u.id} committed`);
  }
});

test("per unit: a good and a bad unit side by side — the good one passes, " +
    "the bad one lists its own reasons; the CLI says which", () => {
  const dir = unit((u) => {
    u.manifest = GOOD_MANIFEST.concat([{id: "u2_bad", titleZh: "壞", minutes: 3, order: 2}]);
    u.extra = {
      "u2_bad.html": GOOD_HTML.replace("</section>", "<p>AI</p></section>"),
      "u2_bad.txt": "x",
    };
  });
  const r = C.checkReaderDirByUnit(dir);
  assert.strictEqual(r.ok, false);
  assert.deepStrictEqual(r.units.map((u) => [u.id, u.ok]), [["u1_good", true], ["u2_bad", false]]);
  assert.deepStrictEqual(r.units[1].problems.map((p) => p.code), ["forbidden_word"]);
  const out = cli(dir);
  assert.strictEqual(out.status, 1);
  assert.ok(/通过    u1_good/.test(out.stderr), out.stderr);
  assert.ok(/不通过  u2_bad/.test(out.stderr), out.stderr);
  assert.ok(out.stderr.indexOf("（第 4 项 不准用的字）") >= 0, out.stderr);
  assert.ok(out.stderr.indexOf("1 个单元通过，1 个不通过") >= 0, out.stderr);
});

test("1021: <id>.explain.json — accepted; must be JSON and have its .html; " +
    "phone numbers / words in it are notes, not failures", () => {
  assert.deepStrictEqual(codes(unit((u) => {
    u.extra = {"u1_good.explain.json": JSON.stringify({c1: "點解？"})};
  })), []);
  fails(unit((u) => {
    u.extra = {"u1_good.explain.json": "{oops"};
  }), "explain_invalid");
  fails(unit((u) => {
    u.extra = {"u9.explain.json": "{}"};
  }), "no_html");
  const r = C.checkReaderDirByUnit(unit((u) => {
    u.extra = {"u1_good.explain.json": JSON.stringify({c1: "小組 2345 6789"})};
  }));
  assert.ok(r.ok);
  assert.strictEqual(r.units[0].notes.length, 2);
});

test("1021: links — the four CTAs, peizhu://reader/open to a packaged " +
    "unit, peizhu://explain only on class=\"ask\"; anything else fails", () => {
  const two = (snippet) => unit((u) => {
    u.html = u.html.replace("</section>", `${snippet}\n</section>`);
    u.manifest = GOOD_MANIFEST.concat([{id: "u2_next", titleZh: "二", minutes: 3, order: 2}]);
    u.extra = {"u2_next.html": GOOD_HTML, "u2_next.txt": "二"};
  });
  assert.deepStrictEqual(codes(two(
      '<a href="peizhu://cta/chat_siu_yan">小欣</a>' +
      '<a href="peizhu://reader/open?id=u2_next">讀下一篇</a>' +
      '<a class="ask" href="peizhu://explain?card=u1_good.c1">?</a>')), []);
  fails(two('<a href="peizhu://reader/open?id=u9_gone">下一篇</a>'), "open_target_missing");
  fails(two('<a href="peizhu://explain?card=u1_good.c1">?</a>'), "bad_link");
  fails(two('<a href="peizhu://reader/close?id=u2_next">x</a>'), "bad_link");
  fails(two('<script>location.href="peizhu://home";</script>'), "bad_link");
});

test("1021: manifest part / partTitleZh / icon — optional, checked when " +
    "given; an unknown icon name is only a note", () => {
  const withFields = (f) => unit((u) => {
    u.manifest = [Object.assign({}, GOOD_MANIFEST[0], f)];
  });
  assert.deepStrictEqual(codes(withFields({part: 1, partTitleZh: "認識孤單", icon: "science"})), []);
  for (const bad of [{part: 0}, {part: "1"}, {partTitleZh: ""}, {icon: "Bad Icon"}]) {
    fails(withFields(bad), "manifest_entry");
  }
  fails(withFields({part: 1, partTitleZh: "小組"}), "forbidden_word");
  const r = C.checkReaderDirByUnit(withFields({icon: "no_such_icon"}));
  assert.ok(r.ok);
  assert.strictEqual(r.units[0].notes.length, 1);
  fails(unit((u) => {
    u.manifest = [Object.assign({}, GOOD_MANIFEST[0], {part: 1, partTitleZh: "一"}),
      {id: "u2_x", titleZh: "二", minutes: 3, order: 2, part: 1, partTitleZh: "不同"}];
    u.extra = {"u2_x.html": GOOD_HTML, "u2_x.txt": "二"};
  }), "manifest_entry");
});

test("1021: a journal page range in a reference (年;卷(期):页码) is not a " +
    "phone number; the same digits elsewhere still are", () => {
  assert.deepStrictEqual(codes(unit(htmlWith(
      "<li>J Am Geriatr Soc. 2015;63(10):2014-2022.</li>" +
      "<li>Br J Sports Med. 2020;54(24):1451-1462.</li>"))), []);
  fails(unit(htmlWith("<p>電話 2014-2022</p>")), "phone_number");
});

test("1021: text in <script type=\"application/json\"> (shown by the " +
    "page) counts as visible", () => {
  fails(unit(htmlWith('<script type="application/json" data-for="x">["小組"]</script>')),
      "forbidden_word");
});

test("CLI: exit 0 on good / empty, exit 1 with the reasons on bad", () => {
  assert.strictEqual(cli(path.join(FIX, "good")).status, 0);
  assert.strictEqual(cli(path.join(FIX, "empty")).status, 0);
  const bad = cli(path.join(FIX, "bad"));
  assert.strictEqual(bad.status, 1);
  for (const code of ["external_resource", "network_api", "phone_number",
    "forbidden_word", "no_section", "no_fs", "no_txt", "not_in_manifest"]) {
    assert.ok(bad.stderr.indexOf(`[${code}]`) >= 0, `${code} in ${bad.stderr}`);
  }
});

test("(1) external resources: src / href / // / @import / url(", () => {
  fails(unit(htmlWith('<img src="https://x.example/a.png">')), "external_resource");
  fails(unit(htmlWith('<img src="http://x.example/a.png">')), "external_resource");
  fails(unit(htmlWith('<script src="//cdn.example/x.js"></script>')),
      "external_resource");
  fails(unit(htmlWith('<a href="https://www.example.com/">x</a>')),
      "external_resource");
  fails(unit((u) => {
    u.html = u.html.replace("<style>", "<style>@import 'https://f.example/a.css';");
  }), "external_resource");
  fails(unit((u) => {
    u.html = u.html.replace("<style>",
        "<style>.x{background:url(https://f.example/a.png)}");
  }), "external_resource");
  fails(unit((u) => {
    u.html = u.html.replace("<style>", "<style>.x{background:url('//f.example/a.png')}");
  }), "external_resource");
});

test("(1+) a local file reference or a stray link cannot work in the App", () => {
  fails(unit(htmlWith('<img src="pic.png">')), "local_resource");
  fails(unit(htmlWith('<link rel="stylesheet" href="a.css">')), "local_resource");
  fails(unit((u) => {
    u.html = u.html.replace("<style>", "<style>@import 'a.css';");
  }), "local_resource");
  fails(unit(htmlWith('<a href="peizhu://cta/call_now">x</a>')), "bad_link");
  fails(unit(htmlWith('<a href="mailto:a@b.c">x</a>')), "bad_link");
});

test("(2) fetch( XMLHttpRequest WebSocket localStorage <form <input " +
    "<textarea tel:", () => {
  for (const s of ["<script>fetch ('x')</script>",
    "<script>new XMLHttpRequest()</script>",
    "<script>new WebSocket('wss://x')</script>",
    "<script>localStorage.setItem('a','b')</script>",
    "<form></form>", "<INPUT type=text>", "<textarea></textarea>",
    '<a href="tel:999">x</a>']) {
    fails(unit(htmlWith(s)), "network_api");
  }
  fails(unit((u) => {
    u.txt += "\ntel:12";
  }), "network_api");
  // "hotel:" is not tel:
  assert.deepStrictEqual(codes(unit(htmlWith("<p>hotel: 好</p>"))), []);
});

test("(3) phone-like numbers: 8 digits, xxxx xxxx, xxxx-xxxx, full-width; " +
    "in the html, the txt and a manifest title", () => {
  for (const n of ["23456789", "2345 6789", "2345-6789", "２３４５６７８９"]) {
    fails(unit(htmlWith(`<p>${n}</p>`)), "phone_number");
    fails(unit((u) => {
      u.txt += `\n${n}`;
    }), "phone_number");
  }
  fails(unit((u) => {
    u.manifest = [Object.assign({}, GOOD_MANIFEST[0], {titleZh: "熱線 2345 6789"})];
  }), "phone_number");
  // 7 or 9 digits, a year, a time: not phone-like.
  assert.deepStrictEqual(codes(unit(htmlWith(
      "<p>1234567 123456789 2026 年 10:30</p>"))), []);
});

test("(4) forbidden words in the visible text, alt / title, the txt and " +
    "a title; not in comments, <script> or <style>", () => {
  for (const w of ["AI", "模型", "機械人", "版本", "組", "机械人", "组"]) {
    fails(unit(htmlWith(`<p>呢度有${w}字</p>`)), "forbidden_word");
    fails(unit((u) => {
      u.txt += `\n${w}`;
    }), "forbidden_word");
  }
  fails(unit(htmlWith('<img alt="AI 圖" src="data:image/png;base64,AA">')),
      "forbidden_word");
  fails(unit((u) => {
    u.manifest = [Object.assign({}, GOOD_MANIFEST[0], {titleZh: "小組活動"})];
  }), "forbidden_word");
  // Words that merely contain the letters: fine.
  assert.deepStrictEqual(codes(unit(htmlWith("<p>SAID AIA MAIL</p>"))), []);
  assert.deepStrictEqual(codes(unit(htmlWith(
      "<!-- 模型 組 --><script>var AI=1;</script><style>/* 版本 */</style>"))),
  []);
});

test("(5) data-section, same-name .txt, in manifest, manifest ids have files", () => {
  fails(unit((u) => {
    u.html = u.html.replace(/data-section="[^"]*"/g, "");
  }), "no_section");
  fails(unit(htmlWith('<div data-section="第三節"></div>')), "bad_section_id");
  fails(unit(htmlWith('<div data-section="s1_intro"></div>')), "duplicate_section");
  fails(unit((u) => {
    u.txt = null;
  }), "no_txt");
  fails(unit((u) => {
    u.manifest = [];
  }), "not_in_manifest");
  fails(unit((u) => {
    u.manifest = GOOD_MANIFEST.concat([{id: "u2_missing", titleZh: "冇檔",
      minutes: 3, order: 2}]);
  }), "missing_files");
  fails(unit((u) => {
    u.extra = {"u9_orphan.txt": "淨係文字"};
  }), "no_html");
  fails(unit((u) => {
    u.html = u.html.replace(/var\(--fs, 1\)/g, "1");
  }), "no_fs");
});

test("manifest shape: JSON list of {id, titleZh, minutes, order}", () => {
  fails(unit((u) => {
    u.manifest = "not json";
  }), "manifest_invalid");
  fails(unit((u) => {
    u.manifest = "{}";
  }), "manifest_invalid");
  fails(unit((u) => {
    u.manifest = null;
  }), "manifest_invalid");
  for (const bad of [{id: "U1 Good"}, {titleZh: ""}, {minutes: 0},
    {minutes: "5"}, {order: 1.5}]) {
    fails(unit((u) => {
      u.manifest = [Object.assign({}, GOOD_MANIFEST[0], bad)];
    }), "manifest_entry");
  }
  fails(unit((u) => {
    u.manifest = GOOD_MANIFEST.concat(GOOD_MANIFEST);
  }), "manifest_entry");
});

test("(6) every file under 1 MB; only .html / .txt / .explain.json / " +
    "manifest.json", () => {
  fails(unit((u) => {
    u.html = u.html.replace("</body>",
        `<!-- ${"x".repeat(1024 * 1024)} --></body>`);
  }), "too_large");
  fails(unit((u) => {
    u.extra = {"pic.png": "x"};
  }), "unknown_file");
  fails(unit((u) => {
    u.extra = {"Bad Name.txt": "x"};
  }), "bad_file_name");
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
  console.log(`${failed} check_reader_html test(s) failed`);
  process.exit(1);
}
console.log(`all ${tests.length} check_reader_html tests passed`);

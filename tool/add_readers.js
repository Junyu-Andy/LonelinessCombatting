#!/usr/bin/env node
/**
 * 1021 — 小讀本一步加入和检查。通常经 tool/add_readers.sh 调用：
 *
 *   tool/add_readers.sh [--keep] <zip 路径>
 *
 * 做的事（只碰 assets/readers/ 和一个临时目录）：
 *   1. 读 zip（当作不可信的数据）：自己解析 zip 目录，不调用 unzip，不运行里面的任何
 *      东西。有路径穿越（..、/ 开头、盘符、反斜杠）、链接（symlink）、加密、
 *      解压后过大、重名的条目，整个包不处理，assets/readers/ 一点不改。
 *   2. 只收 manifest.json、<id>.html、<id>.txt、<id>.explain.json，写进临时目录。
 *      zip 可以把文件直接放在最上层，也可以整个放在一个文件夹里；
 *      __MACOSX/、.DS_Store、._* 这类电脑自动加的文件不理。其他文件列出来、不收。
 *   3. 用 tool/check_reader_html.js 的检查（1020c 第三节六项）逐个单元查。
 *      <id>.explain.json 不是有效 JSON 或太大：只丢掉这个文件，单元照常。
 *   4. 通过的单元放进 assets/readers/；不通过的不放（文件夹和 manifest.json 都没有）。
 *      默认 zip 就是整套：assets/readers/ 变成「这个 zip 里通过的单元」。
 *      --keep：zip 里没有的、原来在 assets/readers/ 而且通过检查的单元保留。
 *   5. 再查一次整个 assets/readers/（和 CI 一样），列出结果。
 *
 * 可以重跑：同一个 zip 跑两次，结果一模一样。
 * 退出码：0 全部通过；2 有单元不通过（通过的已放进去）；1 没有处理（zip 不安全、
 * 读不了、没有 manifest.json），assets/readers/ 没改。
 *
 * 只用 Node 自带模块。写法保持 ES2018（不用 ?.、??）。
 */
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");

const check = require("./check_reader_html.js");

const ID_RE = check.ID_RE;
const EXPLAIN_SUFFIX = check.EXPLAIN_SUFFIX;

/** Refuse zips bigger than this outright. */
const MAX_ZIP_BYTES = 64 * 1024 * 1024;
/** One file may unpack to at most this (bigger = the zip is refused). */
const MAX_ENTRY_BYTES = 8 * 1024 * 1024;
/** All the files we keep together. */
const MAX_TOTAL_BYTES = 64 * 1024 * 1024;
const MAX_ENTRIES = 2000;

/** A zip we will not touch. */
class UnsafeZip extends Error {}

// ---------------------------------------------------------------- zip ---

let crcTable = null;

/**
 * @param {Buffer} buf
 * @return {number} CRC-32 (unsigned)
 */
function crc32(buf) {
  if (crcTable === null) {
    crcTable = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      crcTable[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = crcTable[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}

/**
 * @param {Buffer} bytes
 * @param {number} flags general purpose bit flags
 * @return {string}
 */
function decodeName(bytes, flags) {
  let ascii = true;
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] >= 0x80) {
      ascii = false;
      break;
    }
  }
  if (ascii) return bytes.toString("latin1");
  try {
    return new TextDecoder("utf-8", {fatal: true}).decode(bytes);
  } catch (e) {
    if (flags & 0x800) throw new UnsafeZip("文件名的编码坏了");
    return bytes.toString("latin1");
  }
}

/**
 * The entries of a zip, from its central directory.  Nothing is unpacked.
 * @param {Buffer} buf
 * @return {Array<object>}
 */
function readZipDirectory(buf) {
  if (buf.length < 22) throw new UnsafeZip("不是 zip 文件");
  let eocd = -1;
  const stop = Math.max(0, buf.length - 22 - 0xffff);
  for (let i = buf.length - 22; i >= stop; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new UnsafeZip("不是 zip 文件（找不到 zip 目录）");
  const disk = buf.readUInt16LE(eocd + 4);
  const cdDisk = buf.readUInt16LE(eocd + 6);
  const countHere = buf.readUInt16LE(eocd + 8);
  const count = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOffset = buf.readUInt32LE(eocd + 16);
  if (disk !== 0 || cdDisk !== 0 || countHere !== count) {
    throw new UnsafeZip("分卷 zip 不支持");
  }
  if (count === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
    throw new UnsafeZip("ZIP64 格式不支持（小讀本不需要这么大）");
  }
  if (count > MAX_ENTRIES) throw new UnsafeZip(`条目太多（${count}）`);
  if (cdOffset + cdSize > eocd) throw new UnsafeZip("zip 目录损坏");

  const entries = [];
  let p = cdOffset;
  for (let i = 0; i < count; i++) {
    if (p + 46 > eocd || buf.readUInt32LE(p) !== 0x02014b50) {
      throw new UnsafeZip("zip 目录损坏");
    }
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    if (p + 46 + nameLen > eocd) throw new UnsafeZip("zip 目录损坏");
    const flags = buf.readUInt16LE(p + 8);
    entries.push({
      madeBy: buf.readUInt16LE(p + 4),
      flags: flags,
      method: buf.readUInt16LE(p + 10),
      crc: buf.readUInt32LE(p + 16),
      compressedSize: buf.readUInt32LE(p + 20),
      size: buf.readUInt32LE(p + 24),
      externalAttrs: buf.readUInt32LE(p + 38),
      localOffset: buf.readUInt32LE(p + 42),
      name: decodeName(buf.subarray(p + 46, p + 46 + nameLen), flags),
    });
    p += 46 + nameLen + extraLen + commentLen;
  }
  entries.cdOffset = cdOffset;
  return entries;
}

const S_IFMT = 0o170000;
const S_IFREG = 0o100000;
const S_IFDIR = 0o040000;
const S_IFLNK = 0o120000;

/**
 * Refuse anything that could write outside the folder or is not a plain
 * file or folder.  Throws UnsafeZip.
 * @param {object} e an entry
 * @return {boolean} true for a folder entry
 */
function vetEntry(e) {
  const n = e.name;
  const show = JSON.stringify(n);
  if (n.length === 0) throw new UnsafeZip("有一个没有名字的条目");
  if (n.indexOf("\0") >= 0) throw new UnsafeZip(`条目 ${show} 名字里有空字符`);
  if (n.indexOf("\\") >= 0) throw new UnsafeZip(`条目 ${show} 用了反斜杠 \\（路径不安全）`);
  if (n.charAt(0) === "/" || /^[A-Za-z]:/.test(n)) {
    throw new UnsafeZip(`条目 ${show} 是绝对路径（会写到别处）`);
  }
  const isDirName = n.charAt(n.length - 1) === "/";
  const segs = (isDirName ? n.slice(0, -1) : n).split("/");
  for (const s of segs) {
    if (s === "..") throw new UnsafeZip(`条目 ${show} 有 ..（路径穿越）`);
    if (s === "" || s === ".") throw new UnsafeZip(`条目 ${show} 路径不规范`);
  }
  if (e.flags & 0x1) throw new UnsafeZip(`条目 ${show} 加了密码`);
  const host = e.madeBy >> 8;
  const mode = e.externalAttrs >>> 16;
  const type = mode & S_IFMT;
  // Unix-made zips (macOS, Linux; host 3, or 19 for old macOS) carry the
  // file type in the top half of the external attributes.
  if ((host === 3 || host === 19) && type !== 0) {
    if (type === S_IFLNK) throw new UnsafeZip(`条目 ${show} 是链接（symlink），不收`);
    if (type !== S_IFREG && type !== S_IFDIR) {
      throw new UnsafeZip(`条目 ${show} 不是普通文件`);
    }
    if (type === S_IFDIR) return true;
  }
  if (isDirName) return true;
  // MS-DOS directory attribute.
  if (host === 0 && (e.externalAttrs & 0x10)) return true;
  return false;
}

/**
 * Unpack one entry into memory, checking size and CRC.
 * @param {Buffer} buf the zip
 * @param {object} e the entry
 * @param {number} cdOffset where the central directory starts
 * @return {Buffer}
 */
function readEntry(buf, e, cdOffset) {
  const show = JSON.stringify(e.name);
  if (e.size > MAX_ENTRY_BYTES) throw new UnsafeZip(`${show} 解压后太大（${e.size} 字节）`);
  const lo = e.localOffset;
  if (lo + 30 > cdOffset || buf.readUInt32LE(lo) !== 0x04034b50) {
    throw new UnsafeZip(`${show}：zip 损坏`);
  }
  const start = lo + 30 + buf.readUInt16LE(lo + 26) + buf.readUInt16LE(lo + 28);
  const end = start + e.compressedSize;
  if (end > cdOffset) throw new UnsafeZip(`${show}：zip 损坏`);
  const raw = buf.subarray(start, end);
  let data;
  if (e.method === 0) {
    data = Buffer.from(raw);
  } else if (e.method === 8) {
    try {
      data = zlib.inflateRawSync(raw, {maxOutputLength: MAX_ENTRY_BYTES});
    } catch (err) {
      throw new UnsafeZip(`${show}：解压失败或解压后太大`);
    }
  } else {
    throw new UnsafeZip(`${show}：不支持的压缩方式（${e.method}）`);
  }
  if (data.length !== e.size || crc32(data) !== e.crc) {
    throw new UnsafeZip(`${show}：zip 损坏（大小或校验对不上）`);
  }
  return data;
}

/**
 * @param {Array<string>} segs the entry's path, split at "/"
 * @return {boolean} a file computers add on their own
 */
function isJunk(segs) {
  const base = segs[segs.length - 1];
  return segs.indexOf("__MACOSX") >= 0 || base === ".DS_Store" ||
      base.indexOf("._") === 0 || base === "Thumbs.db" || base === "desktop.ini";
}

/**
 * @param {string} base
 * @return {boolean} one of the names we take
 */
function isReaderFileName(base) {
  return base === "manifest.json" || check.unitFileOf(base) !== null;
}

/**
 * Read the zip and pick the reader files.  Throws UnsafeZip.
 * @param {Buffer} buf
 * @return {{files: Object<string, Buffer>, ignored: Array<{name: string,
 *     why: string}>, prefix: string}}
 */
function readReaderZip(buf) {
  if (buf.length > MAX_ZIP_BYTES) throw new UnsafeZip(`zip 太大（${buf.length} 字节）`);
  const entries = readZipDirectory(buf);
  const seen = {};
  const candidates = [];
  const ignored = [];
  for (const e of entries) {
    const isDir = vetEntry(e);
    const key = e.name.replace(/\/$/, "");
    if (seen[key]) throw new UnsafeZip(`条目 ${JSON.stringify(e.name)} 出现两次`);
    seen[key] = true;
    if (isDir) continue;
    const segs = e.name.split("/");
    if (isJunk(segs)) {
      ignored.push({name: e.name, why: "电脑自动加的文件"});
      continue;
    }
    candidates.push({entry: e, segs: segs});
  }
  // Everything inside one folder (e.g. a zipped 小讀本/ folder): drop it.
  let prefix = "";
  if (candidates.length && candidates.every((c) => c.segs.length >= 2 &&
      c.segs[0] === candidates[0].segs[0])) {
    prefix = candidates[0].segs[0] + "/";
    candidates.forEach((c) => {
      c.segs = c.segs.slice(1);
    });
  }
  const files = {};
  let total = 0;
  for (const c of candidates) {
    if (c.segs.length > 1) {
      ignored.push({name: c.entry.name, why: "在子文件夹里（只收最上一层）"});
      continue;
    }
    const base = c.segs[0];
    if (!isReaderFileName(base)) {
      ignored.push({name: c.entry.name, why: /\.(html|txt|json)$/i.test(base) ?
          "文件名不合规则（id 只可以用小写字母、数字、_、-）" :
          "不认识的文件（只收 manifest.json、<id>.html、<id>.txt、<id>.explain.json）"});
      continue;
    }
    const data = readEntry(buf, c.entry, entries.cdOffset);
    total += data.length;
    if (total > MAX_TOTAL_BYTES) throw new UnsafeZip("解压后总共太大");
    files[base] = data;
  }
  return {files: files, ignored: ignored, prefix: prefix};
}

// ------------------------------------------------------------ folder ---

/**
 * @param {Array<object>} entries manifest entries
 * @return {string} manifest.json as written: the entries as given (every
 *     field kept), sorted by order, then id
 */
function manifestText(entries) {
  const list = entries.slice();
  list.sort((a, b) => (a.order !== b.order ? a.order - b.order :
      (a.id < b.id ? -1 : (a.id > b.id ? 1 : 0))));
  return JSON.stringify(list, null, 2) + "\n";
}

/**
 * The unit files now in a folder, by unit id.
 * @param {string} dir
 * @return {Object<string, Array<string>>}
 */
function unitFilesIn(dir) {
  const out = {};
  for (const f of fs.readdirSync(dir)) {
    const uf = check.unitFileOf(f);
    if (!uf) continue;
    (out[uf.id] = out[uf.id] || []).push(f);
  }
  return out;
}

/**
 * Write one file in the readers folder without following a link that
 * might sit there.
 * @param {string} dir
 * @param {string} name a vetted file name
 * @param {Buffer|string} data
 */
function putFile(dir, name, data) {
  const full = path.join(dir, name);
  let st = null;
  try {
    st = fs.lstatSync(full);
  } catch (e) {
    st = null;
  }
  if (st !== null) {
    if (st.isDirectory()) throw new Error(`${full} 是文件夹，不覆盖`);
    fs.unlinkSync(full);
  }
  fs.writeFileSync(full, data, {flag: "wx", mode: 0o644});
}

/**
 * @param {string} root the repository
 * @return {string} assets/readers, checked to be a real folder inside root
 */
function readersDir(root) {
  const target = path.join(root, "assets", "readers");
  let st;
  try {
    st = fs.lstatSync(target);
  } catch (e) {
    throw new Error(`找不到 ${target}`);
  }
  if (!st.isDirectory()) throw new Error(`${target} 不是普通文件夹`);
  const real = fs.realpathSync(target);
  if (real !== path.join(fs.realpathSync(root), "assets", "readers")) {
    throw new Error(`${target} 指向别处，不处理`);
  }
  return target;
}

// -------------------------------------------------------------- main ---

/**
 * @param {Array<string>} argv
 * @param {{root: string, log: function(string): void}} opts
 * @return {number} exit code
 */
function addReaders(argv, opts) {
  const log = opts.log;
  const args = argv.filter((a) => a !== "--keep");
  const keep = argv.indexOf("--keep") >= 0;
  if (args.length !== 1 || args[0].charAt(0) === "-") {
    log("用法：tool/add_readers.sh [--keep] <zip 路径>");
    return 1;
  }
  const zipPath = path.resolve(args[0]);
  let target;
  try {
    target = readersDir(opts.root);
  } catch (e) {
    log(`没有处理：${e.message}`);
    return 1;
  }
  const rel = path.relative(opts.root, target) + "/";

  log(`小讀本加入：${zipPath}${keep ? "（--keep：保留 zip 里没有的旧单元）" : ""}`);
  let zip;
  try {
    const st = fs.statSync(zipPath);
    if (!st.isFile()) throw new Error("不是文件");
    if (st.size > MAX_ZIP_BYTES) throw new UnsafeZip(`zip 太大（${st.size} 字节）`);
    const bytes = fs.readFileSync(zipPath);
    log(`zip 的 SHA-256：${crypto.createHash("sha256").update(bytes).digest("hex")}`);
    zip = readReaderZip(bytes);
  } catch (e) {
    log(`没有处理：${e instanceof UnsafeZip ? "zip 不安全或读不了：" : "读不了 zip："}${e.message}`);
    log(`${rel} 没有任何改动。`);
    return 1;
  }
  const names = Object.keys(zip.files).sort();
  log(`zip 里收到 ${names.length} 个文件${zip.prefix ? `（在文件夹 ${zip.prefix} 里）` : ""}：` +
      (names.length ? names.join("、") : "无"));
  for (const i of zip.ignored) log(`  不收：${i.name}（${i.why}）`);
  if (!zip.files["manifest.json"]) {
    log("没有处理：zip 里没有 manifest.json。");
    log(`${rel} 没有任何改动。`);
    return 1;
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "peizhu-readers-"));
  try {
    const stage = path.join(tmp, "stage");
    fs.mkdirSync(stage, {mode: 0o700});
    for (const n of names) {
      fs.writeFileSync(path.join(stage, n), zip.files[n], {flag: "wx", mode: 0o644});
    }

    // <id>.explain.json is not read by the App yet: a bad one is dropped,
    // the unit goes on.
    const warnings = [];
    for (const n of names) {
      if (n.slice(-EXPLAIN_SUFFIX.length) !== EXPLAIN_SUFFIX) continue;
      const data = zip.files[n];
      let why = null;
      if (data.length >= check.MAX_BYTES) why = `太大（${data.length} 字节）`;
      else {
        const r = check.checkExplain(data.toString("utf8"));
        if (r.problems.length) why = r.problems[0].message;
      }
      if (why) {
        fs.unlinkSync(path.join(stage, n));
        warnings.push(`${n}：${why}；这个文件不放进去，单元照常检查`);
      }
    }

    // The staged manifest.
    let zipManifest;
    try {
      zipManifest = JSON.parse(zip.files["manifest.json"].toString("utf8"));
    } catch (e) {
      log(`没有处理：manifest.json 不是有效的 JSON（${e.message}）。`);
      log(`${rel} 没有任何改动。`);
      return 1;
    }
    if (!Array.isArray(zipManifest)) {
      log("没有处理：manifest.json 要是一个列表 [ … ]。");
      log(`${rel} 没有任何改动。`);
      return 1;
    }
    const validId = (e) => !!e && typeof e === "object" && typeof e.id === "string" &&
        ID_RE.test(e.id);
    const zipUnitIds = {};
    Object.keys(unitFilesIn(stage)).forEach((id) => {
      zipUnitIds[id] = true;
    });
    const keptFromBefore = [];
    const dropped = [];
    if (keep) {
      // A manifest line whose files are not in this zip: under --keep the
      // copy already in assets/readers/ (if any) stays as it is.
      zipManifest = zipManifest.filter((e) => {
        if (validId(e) && !zipUnitIds[e.id]) {
          warnings.push(`manifest.json 有 ${e.id}，但 zip 里没有它的文件；` +
              `--keep：${rel} 里原来的（如果有）照旧`);
          return false;
        }
        return true;
      });
      // Units already in assets/readers/ that the zip does not bring go
      // into the check with the new ones (a 「讀下一篇」 link may point at
      // them), if they pass where they are.
      const now = check.checkReaderDirByUnit(target);
      const nowEntries = {};
      now.manifestEntries.forEach((e) => {
        nowEntries[e.id] = e;
      });
      for (const u of now.units) {
        if (zipUnitIds[u.id]) continue;
        if (!(u.ok && u.inManifest)) {
          dropped.push(u.id);
          continue;
        }
        for (const f of u.files) {
          fs.writeFileSync(path.join(stage, f), fs.readFileSync(path.join(target, f)),
              {flag: "wx", mode: 0o644});
        }
        zipManifest.push(nowEntries[u.id]);
        keptFromBefore.push(u.id);
      }
    }
    const writeStagedManifest = () => fs.writeFileSync(
        path.join(stage, "manifest.json"), JSON.stringify(zipManifest));
    if (keep) writeStagedManifest();
    for (const w of warnings) log(`  提示：${w}`);

    // The six checks, unit by unit.  A unit that fails is taken out and
    // the rest checked again, until nothing new fails (a 「讀下一篇」 link
    // to a unit that was taken out fails the unit that has it).
    const first = check.checkReaderDirByUnit(stage);
    const failedById = {};
    let r = first;
    for (let round = 0; round < 100; round++) {
      const newly = r.units.filter((u) => !(u.ok && u.inManifest) && !failedById[u.id]);
      if (!newly.length) break;
      const staged = unitFilesIn(stage);
      for (const u of newly) {
        failedById[u.id] = u;
        for (const f of staged[u.id] || []) fs.unlinkSync(path.join(stage, f));
      }
      zipManifest = zipManifest.filter((e) => !(validId(e) && failedById[e.id]));
      writeStagedManifest();
      r = check.checkReaderDirByUnit(stage);
    }
    const passing = r.units.filter((u) => u.ok && u.inManifest);
    const failing = Object.keys(failedById).map((id) => failedById[id]);

    log("检查（1020c 第三节六项，每个单元分开）：");
    const shown = {};
    for (const u0 of first.units.concat(failing)) {
      if (shown[u0.id]) continue;
      shown[u0.id] = true;
      const u = failedById[u0.id] || u0;
      const lines = check.formatReport({units: [u], general: []});
      for (const l of lines.out.concat(lines.err)) log(l);
    }
    if (first.general.length) {
      const lines = check.formatReport({units: [], general: first.general});
      for (const l of lines.err) log(l);
    }

    // Apply: unit files not in the final set go; the final set's files
    // come in; manifest.json last.  Nothing else in the folder is touched.
    const before = unitFilesIn(target);
    const finalIds = {};
    passing.forEach((u) => {
      finalIds[u.id] = true;
    });
    for (const id of Object.keys(before)) {
      for (const f of before[id]) fs.unlinkSync(path.join(target, f));
    }
    const stagedFinal = unitFilesIn(stage);
    for (const u of passing) {
      for (const f of (stagedFinal[u.id] || []).sort()) {
        putFile(target, f, fs.readFileSync(path.join(stage, f)));
      }
    }
    // All passed, nothing kept or dropped: manifest.json exactly as it
    // came.  Otherwise the zip's own lines for the units that passed.
    const untouched = !keep && !failing.length && !first.general.length;
    putFile(target, "manifest.json", untouched ? zip.files["manifest.json"] :
        manifestText(zipManifest.filter((e) => validId(e) && finalIds[e.id])));

    // Report.
    const fromZip = passing.filter((u) => keptFromBefore.indexOf(u.id) < 0);
    log("结果：");
    log(`  通过 ${fromZip.length} 个，已放进 ${rel}：` +
        (fromZip.length ? fromZip.map((u) => u.id).join("、") : "无"));
    if (failing.length) {
      log(`  不通过 ${failing.length} 个，没有放进去（${rel} 和 manifest.json 里都没有）：` +
          failing.map((u) => u.id).join("、"));
    }
    if (keep) {
      const kept = passing.filter((u) => keptFromBefore.indexOf(u.id) >= 0);
      log(`  保留原来的 ${kept.length} 个：` +
          (kept.length ? kept.map((u) => u.id).join("、") : "无"));
      if (dropped.length) log(`  原来的这些不通过检查，拿走了：${dropped.join("、")}`);
    }
    const removed = Object.keys(before).filter((id) => !finalIds[id]);
    if (removed.length) log(`  ${rel} 里原来有、现在没有了：${removed.join("、")}`);
    const fin = check.checkReaderDirByUnit(target);
    log(`${rel} 现在有 ${fin.manifestCount} 个单元：` +
        (fin.manifestCount ? fin.manifestEntries.map((e) => e.id).join("、") : "无"));
    if (!fin.ok) {
      log(`复核整个 ${rel}（和 CI 同一个检查）：不通过。原因见下` +
          "（多半是文件夹里本来就有别的文件；请把下面贴给开发）：");
      const fl = check.formatReport(fin);
      for (const l of fl.err) log(l);
      return 1;
    }
    log("复核整个文件夹（和 CI 同一个检查，node tool/check_reader_html.js）：通过");
    log(`下一步：git status -- ${rel} 看改动，再提交。` +
        (failing.length ? "不通过的单元，把上面的原因发回写读本的窗口。" : ""));
    return failing.length ? 2 : 0;
  } finally {
    fs.rmSync(tmp, {recursive: true, force: true});
  }
}

module.exports = {addReaders, readReaderZip, readZipDirectory, crc32, UnsafeZip,
  manifestText};

if (require.main === module) {
  const code = addReaders(process.argv.slice(2), {
    root: path.resolve(__dirname, ".."),
    log: (s) => console.log(s),
  });
  process.exit(code);
}

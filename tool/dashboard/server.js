#!/usr/bin/env node
/**
 * tool/dashboard/server.js — the local ops dashboard (decision 0061;
 * dev-tasks 1020i 第二版 §2).  Start it with tool/dashboard/start.sh; the
 * guide is docs/release/ops-dashboard-local.md.
 *
 *   - Listens on 127.0.0.1 only; requests whose Host is not this machine
 *     are refused (no DNS rebinding), POSTs must come from this page.
 *   - Reads Firestore through lib/guarded_db.js only (allowlist + field
 *     masks, no writes).  Real project: the key in
 *     GOOGLE_APPLICATION_CREDENTIALS must be a viewer-only key
 *     (lib/key_check.js), kept outside the repository.
 *   - Writes nothing to Firestore.  確認處理 / 標記誤觸 run in the browser
 *     with Junyu's own App login against the existing callables
 *     (public/auth.js); this process never sees the password or token.
 *   - Every JSON reply and CSV passes lib/leak_guard.js.
 *   - Reads are cached in memory for CACHE_MS; 「刷新」 clears the cache.
 *
 * Usage:
 *   real project  GOOGLE_APPLICATION_CREDENTIALS=<viewer key> \
 *                 NODE_PATH=functions/node_modules node tool/dashboard/server.js
 *   emulator      FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *                 NODE_PATH=functions/node_modules node tool/dashboard/server.js --emulator
 * Options: --port=8787 (DASHBOARD_PORT); DASHBOARD_EXPORT_DIR (default
 * ~/dev/dashboard-exports, must be outside the repository); DASHBOARD_NOW
 * (emulator only: pretend it is this instant, for the synthetic demo).
 */
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

const pages = require('./lib/pages');
const {guardedDb} = require('./lib/guarded_db');
const leak = require('./lib/leak_guard');
const keyCheck = require('./lib/key_check');

const ROOT = path.resolve(__dirname, '..', '..');
const PUBLIC = path.join(__dirname, 'public');
const PROJECT = 'loneliness-pilot-dev';
const REGION = 'asia-east2';
/** The web App's API key (lib/firebase_options.dart `web`; public). */
const WEB_API_KEY = 'AIzaSyByMJdPkLLlvfZcG2NgSkwmRzXIYZkJ8_w';
const CACHE_MS = 5 * 60 * 1000;
const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/auth.js': ['auth.js', 'text/javascript; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
};

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

function isInside(child, parent) {
  const rel = path.relative(parent, child);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

/** Refuses the real project unless the setup is the safe one. */
function startupProblems(env, args) {
  const problems = [];
  if (args.emulator) {
    if (!env.FIRESTORE_EMULATOR_HOST) {
      problems.push('--emulator 需要 FIRESTORE_EMULATOR_HOST（用 start.sh --demo）');
    }
    return problems;
  }
  if (env.FIRESTORE_EMULATOR_HOST) {
    problems.push('设了 FIRESTORE_EMULATOR_HOST，但没加 --emulator。' +
      '连正式项目前先 unset FIRESTORE_EMULATOR_HOST。');
  }
  const key = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!key) {
    problems.push('没有设 GOOGLE_APPLICATION_CREDENTIALS（看板只读钥匙的路径）');
  } else {
    const abs = path.resolve(key);
    if (!fs.existsSync(abs)) problems.push(`钥匙文件不存在：${abs}`);
    else if (isInside(abs, ROOT)) {
      problems.push('钥匙放在仓库里面了。请移到仓库以外（例如 ~/dev/keys/）。');
    } else {
      try {
        const k = JSON.parse(fs.readFileSync(abs, 'utf8'));
        if (k.project_id && k.project_id !== PROJECT) {
          problems.push(`钥匙属于项目 ${k.project_id}，不是 ${PROJECT}`);
        }
      } catch (_) {
        problems.push('钥匙文件不是有效的 JSON');
      }
    }
  }
  return problems;
}

function exportDir(env) {
  const dir = path.resolve(env.DASHBOARD_EXPORT_DIR ||
    path.join(os.homedir(), 'dev', 'dashboard-exports'));
  if (dir === ROOT || isInside(dir, ROOT)) {
    throw new Error('导出文件夹不能在仓库里面（DASHBOARD_EXPORT_DIR）');
  }
  return dir;
}

/** In-memory cache: key → {at, promise}. */
function makeCache(clock) {
  const store = new Map();
  return {
    get(key, fn) {
      const hit = store.get(key);
      if (hit && clock() - hit.at < CACHE_MS) return hit.promise;
      const promise = fn();
      store.set(key, {at: clock(), promise});
      promise.catch(() => store.delete(key));
      return promise;
    },
    clear() {
      store.clear();
    },
  };
}

/**
 * The request handler (exported for the tests).
 * @param {{g: object, now: function(): Date, port: number, emulator: boolean,
 *     projectId: (string|undefined), authEmulator: ?string,
 *     functionsEmulator: ?string, exportDir: function(): string,
 *     clock: function(): number}} ctx  projectId: the emulator's project
 *     (emulator mode only); the real project otherwise
 * @return {function(object, object)}
 */
function handler(ctx) {
  const cache = makeCache(ctx.clock || Date.now);
  const allowedHosts = [`127.0.0.1:${ctx.port}`, `localhost:${ctx.port}`];
  const allowedOrigins = allowedHosts.map((h) => `http://${h}`);

  const base = () => cache.get('base', () => pages.base(ctx.g));
  const overview = (testers) => cache.get(`overview:${testers ? 1 : 0}`,
      async () => pages.overview(ctx.g, ctx.now(), await base(), {testers}));

  function send(res, status, body, type) {
    res.writeHead(status, {
      'Content-Type': type || 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      // Origin only (http://127.0.0.1:8787): enough for a web API key
      // restricted to localhost, nothing about the page.
      'Referrer-Policy': 'strict-origin',
      'X-Frame-Options': 'DENY',
      'Content-Security-Policy': csp(ctx),
    });
    res.end(body);
  }

  function json(res, value) {
    send(res, 200, JSON.stringify(leak.assertNoLeak(value)));
  }

  async function route(req, res, url) {
    const p = url.pathname;
    if (req.method === 'GET' && STATIC[p]) {
      const [file, type] = STATIC[p];
      return send(res, 200, fs.readFileSync(path.join(PUBLIC, file)), type);
    }
    if (req.method === 'GET' && p === '/api/config') {
      return json(res, {
        projectId: (ctx.emulator && ctx.projectId) || PROJECT, region: REGION,
        apiKey: WEB_API_KEY,
        emulator: !!ctx.emulator, authEmulator: ctx.authEmulator || null,
        functionsEmulator: ctx.functionsEmulator || null,
        cacheMinutes: CACHE_MS / 60000,
      });
    }
    if (req.method === 'GET' && p === '/api/overview') {
      return json(res, await overview(url.searchParams.get('testers') === '1'));
    }
    if (req.method === 'GET' && p === '/api/today') {
      const value = await cache.get('today', async () =>
        pages.today(ctx.g, ctx.now(), await base(), await overview(false)));
      return json(res, value);
    }
    if (req.method === 'GET' && p === '/api/person') {
      const id = String(url.searchParams.get('id') || '').trim().toUpperCase();
      if (!/^[A-Z0-9-]{3,40}$/.test(id)) return send(res, 400, '{"error":"bad id"}');
      const value = await cache.get(`person:${id}`, async () =>
        pages.person(ctx.g, id, ctx.now(), await base()));
      if (!value) return send(res, 404, '{"error":"unknown research id"}');
      return json(res, value);
    }
    if (req.method === 'GET' && p === '/api/completion') {
      const value = await cache.get('completion', async () =>
        pages.completion(ctx.g, ctx.now(), await base()));
      return json(res, value);
    }
    if (req.method === 'POST' && p === '/api/refresh') {
      cache.clear();
      return json(res, {ok: true});
    }
    if (req.method === 'POST' && p === '/api/export') {
      const now = ctx.now();
      const out = await pages.exportCsv(ctx.g, now, await base());
      leak.assertCsvClean(out.weekly);
      leak.assertCsvClean(out.daily);
      const dir = ctx.exportDir();
      fs.mkdirSync(dir, {recursive: true});
      // Hong Kong time in the file name, e.g. 2026-11-20-10-00.
      const stamp = new Date(now.getTime() + 8 * 3600 * 1000).toISOString()
          .slice(0, 16).replace(/[:T]/g, '-');
      const files = [
        [`process_weekly_${stamp}.csv`, out.weekly],
        [`process_daily_${stamp}.csv`, out.daily],
      ].map(([name, text]) => {
        const full = path.join(dir, name);
        fs.writeFileSync(full, text, {mode: 0o600});
        return full;
      });
      return json(res, {files, people: out.people});
    }
    return send(res, 404, '{"error":"not found"}');
  }

  return (req, res) => {
    if (allowedHosts.indexOf(req.headers.host) < 0) {
      return send(res, 403, '{"error":"host"}');
    }
    if (req.method === 'POST' &&
      allowedOrigins.indexOf(req.headers.origin) < 0) {
      return send(res, 403, '{"error":"origin"}');
    }
    const url = new URL(req.url, `http://${req.headers.host}`);
    route(req, res, url).catch((err) => {
      console.error(`[dashboard] ${url.pathname}:`, err && err.message);
      const msg = err && (err.leak || err.guard) ? err.message :
        '读取出错，请稍后按「刷新」再试；一直不行就把终端里的错误发给开发窗口。';
      send(res, 500, JSON.stringify({error: msg}));
    });
  };
}

function csp(ctx) {
  const connect = ["'self'", 'https://identitytoolkit.googleapis.com',
    'https://securetoken.googleapis.com',
    `https://${REGION}-${PROJECT}.cloudfunctions.net`];
  if (ctx.authEmulator) connect.push(`http://${ctx.authEmulator}`);
  if (ctx.functionsEmulator) connect.push(`http://${ctx.functionsEmulator}`);
  return `default-src 'self'; connect-src ${connect.join(' ')}; ` +
    "img-src 'self' data:; style-src 'self'; script-src 'self'; " +
    "frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const env = process.env;
  const problems = startupProblems(env, args);
  if (problems.length) {
    for (const p of problems) console.error(`✗ ${p}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  const emulatorProject = env.GCLOUD_PROJECT || PROJECT;
  if (args.emulator) {
    admin.initializeApp({projectId: emulatorProject});
  } else {
    const credential = admin.credential.applicationDefault();
    admin.initializeApp({projectId: PROJECT, credential});
    const verdict = await keyCheck.checkKey({
      projectId: PROJECT,
      fetch: (u, o) => fetch(u, o),
      getAccessToken: async () =>
        (await credential.getAccessToken()).access_token,
    });
    if (!verdict.ok) {
      console.error(`✗ ${verdict.reason}`);
      process.exit(2);
    }
    console.log(`✓ 钥匙检查：${verdict.reason}`);
  }
  const db = admin.firestore();
  const g = guardedDb(db, {FieldPath: admin.firestore.FieldPath});
  const fixedNow = args.emulator && env.DASHBOARD_NOW ?
    new Date(env.DASHBOARD_NOW) : null;
  const port = Number(args.port || env.DASHBOARD_PORT || 8787);
  const server = http.createServer(handler({
    g, port, emulator: !!args.emulator,
    projectId: args.emulator ? emulatorProject : PROJECT,
    now: () => fixedNow || new Date(),
    authEmulator: args.emulator ? (env.FIREBASE_AUTH_EMULATOR_HOST || null) : null,
    functionsEmulator: args.emulator ?
      (env.DASHBOARD_FUNCTIONS_EMULATOR || null) : null,
    exportDir: () => exportDir(env),
  }));
  server.listen(port, '127.0.0.1', () => {
    console.log(`看板已打开：http://127.0.0.1:${port}/` +
      (args.emulator ? '（模拟器，合成数据）' : ''));
    console.log('关掉看板：在这个终端按 Ctrl+C。');
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err && err.stack || err);
    process.exit(1);
  });
}

module.exports = {PROJECT, REGION, WEB_API_KEY, CACHE_MS, handler,
  startupProblems, exportDir, parseArgs, isInside};

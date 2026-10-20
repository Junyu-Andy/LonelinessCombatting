/**
 * tool/dashboard/test/dashboard_emulator_test.js — the local ops dashboard
 * against the Firestore emulator with synthetic data (decision 0061;
 * 1020i 第二版 §2.3 test: outcome answer fields never appear in any
 * output).  Run inside `firebase emulators:exec --only firestore`, after
 * the other emulator tests: it empties the emulator first and leaves its
 * synthetic data behind (tool/ci_backend_tests.sh,
 * tool/run_local_tests_mac.sh):
 *
 *   NODE_PATH=functions/node_modules node tool/dashboard/test/dashboard_emulator_test.js
 *
 * Checks:
 *   - no answer / mood / text / allocation marker ever came back from
 *     Firestore (field masks), nor reached a page or a CSV;
 *   - only allowlisted paths were read; allocation collections never;
 *   - nothing was written (ops_daily untouched — the server's loaders
 *     would have written it);
 *   - the page numbers on the synthetic people;
 *   - the HTTP layer: Host / Origin checks, CSP, 404, static files.
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const fields = require('../lib/fields');
const {guardedDb} = require('../lib/guarded_db');
const pages = require('../lib/pages');
const leak = require('../lib/leak_guard');
const server = require('../server');
const S = require('./seed_synthetic');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('emulator only: FIRESTORE_EMULATOR_HOST is not set');
  process.exit(2);
}

admin.initializeApp({projectId: 'loneliness-pilot-dev'}, 'dashboard-test');
const db = admin.app('dashboard-test').firestore();

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`ok - ${name}`);
}

function hasMarker(value) {
  const s = JSON.stringify(value);
  return s.indexOf(S.SENTINEL) >= 0 || s.indexOf(String(S.SENTINEL_NUM)) >= 0;
}

async function countDocs(coll) {
  return (await db.collection(coll).count().get()).data().count;
}

async function opsDailyCount() {
  let n = 0;
  for (const p of S.PEOPLE) {
    n += (await db.collection(`ops_daily/${p.uid}/days`).count().get())
        .data().count;
  }
  return n;
}

function request(port, opts) {
  return new Promise((resolve, reject) => {
    const req = http.request(Object.assign({host: '127.0.0.1', port},
        opts), (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => resolve({status: res.statusCode,
        headers: res.headers, body}));
    });
    req.on('error', reject);
    req.end(opts.body || undefined);
  });
}

/** Start from an empty emulator (other emulator tests run before this one
 * in the same `emulators:exec`); emulator only. */
async function clearEmulator() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const res = await fetch(`http://${host}/emulator/v1/projects/` +
    'loneliness-pilot-dev/databases/(default)/documents', {method: 'DELETE'});
  assert.ok(res.ok, `emulator clear failed: ${res.status}`);
}

(async () => {
  await clearEmulator();
  await S.seed(db, admin);
  const reads = [];
  const g = guardedDb(db, {FieldPath: admin.firestore.FieldPath,
    onRead: (template, rows) => reads.push({template, rows})});
  const now = S.NOW;
  const before = {ops: await opsDailyCount(),
    alerts: await countDocs('pi_alerts'),
    events: await countDocs('safety_events')};

  const base = await pages.base(g);
  const ov = await pages.overview(g, now, base, {testers: true});
  const td = await pages.today(g, now, base, ov);
  const p1 = await pages.person(g, 'RCT-001', now, base);
  const p2 = await pages.person(g, 'RCT-002', now, base);
  const comp = await pages.completion(g, now, base);
  const csv = await pages.exportCsv(g, now, base);
  const outputs = {ov, td, p1, p2, comp, csv};

  await test('no marker came back from Firestore (field masks)', async () => {
    for (const r of reads) {
      assert.ok(!hasMarker(r.rows), `marker read on ${r.template}`);
    }
    assert.ok(reads.length > 50, 'reads were recorded');
  });

  await test('no marker and no forbidden key in any output', async () => {
    for (const [name, value] of Object.entries(outputs)) {
      assert.ok(!hasMarker(value), `marker in ${name}`);
      assert.deepStrictEqual(leak.findLeaks(value), [], name);
    }
    leak.assertCsvClean(csv.weekly);
    leak.assertCsvClean(csv.daily);
  });

  await test('only allowlisted paths were read; allocation never', async () => {
    const allowed = Object.keys(fields.READ_ALLOW).concat(fields.CONFIG_DOCS);
    for (const r of reads) {
      assert.ok(allowed.indexOf(r.template) >= 0, r.template);
      for (const d of fields.DENIED_COLLECTIONS) {
        assert.ok(r.template.split('/').indexOf(d) < 0, r.template);
      }
    }
    for (const t of ['randomization_state', 'randomization_sequences',
      'arm_assignment_log', 'pilot_assignment_log', 'research_id_map']) {
      assert.throws(() => g.query(t), /dashboard read refused/);
    }
    assert.throws(() => g.query('users/{uid}/turns', {uid: 'uidRct001'}),
        /dashboard read refused/);
    assert.throws(() => g.query('users/{uid}/events', {uid: 'uidRct001'})
        .where('name', '==', 'voice_transcription_failed'),
    /dashboard read refused/);
    await assert.rejects(g.query('users/{uid}/events', {uid: 'uidRct001'})
        .get(), /dashboard read refused/);
  });

  await test('nothing was written', async () => {
    assert.strictEqual(await opsDailyCount(), before.ops);
    assert.strictEqual(await countDocs('pi_alerts'), before.alerts);
    assert.strictEqual(await countDocs('safety_events'), before.events);
  });

  await test('overview rows', async () => {
    const by = {};
    for (const r of ov.people) by[r.researchId] = r;
    assert.deepStrictEqual(Object.keys(by).sort(), S.PEOPLE.map((p) => p.rid)
        .sort());
    const r1 = by['RCT-001'];
    assert.strictEqual(r1.arm, 'A');
    assert.strictEqual(r1.cohort, 'RCT');
    assert.strictEqual(r1.studyDay, 30);
    assert.strictEqual(r1.studyWeek, 5);
    assert.strictEqual(r1.openedToday, true);
    assert.strictEqual(r1.stage, 'follow_up_period'); // day 30 > 28
    assert.deepStrictEqual(r1.weeklyPr, {W1: 'done', W2: 'done', W3: 'done',
      W4: 'open'});
    assert.strictEqual(r1.w8, 'not_built');
    assert.strictEqual(r1.pendingAlerts, 0);
    // Opened days 1..30 except multiples of 6 below 30 (6,12,18,24):
    // 26 days; valid unless day % 5 == 0 (5,10,15,20,25,30): 26 - 6 = 20.
    assert.strictEqual(r1.validSessions.all.total, 20);
    // Week 5 = days 29–30 so far, both opened; day 30 is a multiple of 5,
    // so only day 29's session is valid.
    assert.strictEqual(r1.validSessions.thisWeek.total, 1);
    assert.strictEqual(r1.checkIn.daysSoFar, 2);
    assert.strictEqual(r1.checkIn.daysThisWeek, 1); // day 29 (odd)
    assert.strictEqual(by['RCT-002'].stage, 'whatsapp');
    assert.strictEqual(by['RCT-002'].consecutiveUnopenedDays, 4);
    assert.strictEqual(by['RCT-002'].pendingAlerts, 1);
    assert.strictEqual(by['RCT-003'].stage, 'phone');
    assert.strictEqual(by['RCT-003'].consecutiveUnopenedDays, 7);
    assert.strictEqual(by['RCT-004'].stage, 'follow_up_period');
    assert.strictEqual(by['PILOT-01'].cohort, 'PILOT');
    assert.strictEqual(ov.testers.length, 1);
    assert.strictEqual(ov.testers[0].pendingAlerts, 1);
  });

  await test('ops_daily stored rows are used; the gap is computed', async () => {
    const days = p1.days.slice().reverse();
    assert.strictEqual(days.length, 30);
    assert.strictEqual(days[28].studyDay, 29);
    assert.strictEqual(days[28].opened, true); // not stored: computed
    assert.strictEqual(days[5].opened, false); // day 6: stored
  });

  await test('today: follow-up, questionnaires, alerts (no arm)', async () => {
    assert.deepStrictEqual(td.whatsapp.map((r) => r.researchId), ['RCT-002']);
    assert.deepStrictEqual(td.phone.map((r) => r.researchId), ['RCT-003']);
    const due = td.weeklyDue.map((r) => `${r.researchId}:${r.bundle}`).sort();
    assert.deepStrictEqual(due, ['PILOT-01:W1', 'RCT-002:W2']);
    assert.deepStrictEqual(td.alerts.map((a) => a.alertId), ['al1']);
    assert.strictEqual(td.alerts[0].researchId, 'RCT-002');
    assert.ok(JSON.stringify(td).indexOf('"arm"') < 0, 'no arm on today');
  });

  await test('person: safety events with their alerts, mood presence', async () => {
    assert.strictEqual(p2.safety.length, 1);
    assert.strictEqual(p2.safety[0].alert.alertId, 'al1');
    assert.strictEqual(p2.safety[0].alert.acknowledgedAt, null);
    assert.strictEqual(p1.safety[0].falseAlarm, true);
    assert.ok(p1.safety[0].alert.acknowledgedAt);
    const d29 = p1.days.find((d) => d.studyDay === 29);
    assert.strictEqual(d29.moodRecorded, true);
    assert.strictEqual(d29.checkInDone, true);
    assert.ok(p1.sessions.length >= 26);
    assert.strictEqual(p1.briefPr[0].understanding, 6);
    assert.strictEqual(await pages.person(g, 'RCT-999', now, base), null);
  });

  await test('completion: pooled, Phase B only, hidden below 5', async () => {
    const row = (inst, tp) => comp.rows.find((r) => r.instrument === inst &&
      r.timepoint === tp);
    // W1 closed for all 8 RCT people; RCT-007 did not do W1.
    assert.deepStrictEqual(row('DJG-ES', 'W1'), {instrument: 'DJG-ES',
      timepoint: 'W1', suppressed: false, n: 8, completed: 7, rate: 0.875});
    // W2 closed (day ≥ 17) for 001, 004–008: 6 people.
    assert.strictEqual(row('DJG-ES', 'W2').n, 6);
    // W4 paper due from day 32: 004, 005, 006, 007, 008.
    assert.strictEqual(row('DJG-ES', 'W4').n, 5);
    assert.strictEqual(row('DJG-ES', 'W4').completed, 5);
    assert.strictEqual(row('W8', 'W8').notBuilt, true);
    assert.ok(JSON.stringify(comp).indexOf('"arm"') < 0, 'never by arm');
  });

  await test('CSV: weekly and daily, process columns only', async () => {
    const header = csv.weekly.split('\n')[0];
    assert.strictEqual(header, pages.WEEKLY_CSV_COLUMNS.join(','));
    assert.ok(csv.weekly.indexOf('RCT-001,RCT,A,5,29,30,2,2,') >= 0,
        csv.weekly.split('\n').filter((l) => l.startsWith('RCT-001')).pop());
    assert.ok(csv.daily.startsWith('researchId,studyPeriod,arm,studyDay'));
  });

  await test('HTTP: host and origin checks, CSP, pages', async () => {
    const port = 18787;
    const exportDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dash-export-'));
    const srv = http.createServer(server.handler({g, port, emulator: true,
      now: () => now, exportDir: () => exportDir}));
    await new Promise((r) => srv.listen(port, '127.0.0.1', r));
    try {
      const ok = await request(port, {path: '/api/today',
        headers: {host: `127.0.0.1:${port}`}});
      assert.strictEqual(ok.status, 200);
      assert.ok(/default-src 'self'/.test(ok.headers['content-security-policy']));
      assert.ok(!hasMarker(ok.body));
      const evil = await request(port, {path: '/api/today',
        headers: {host: 'evil.example:80'}});
      assert.strictEqual(evil.status, 403);
      const csrf = await request(port, {path: '/api/refresh', method: 'POST',
        headers: {host: `127.0.0.1:${port}`, origin: 'https://evil.example'}});
      assert.strictEqual(csrf.status, 403);
      const refresh = await request(port, {path: '/api/refresh', method: 'POST',
        headers: {host: `localhost:${port}`, origin: `http://localhost:${port}`}});
      assert.strictEqual(refresh.status, 200);
      const page = await request(port, {path: '/',
        headers: {host: `127.0.0.1:${port}`}});
      assert.strictEqual(page.status, 200);
      assert.ok(page.body.indexOf('陪住运营看板') >= 0);
      const missing = await request(port, {path: '/../../functions/index.js',
        headers: {host: `127.0.0.1:${port}`}});
      assert.strictEqual(missing.status, 404);
      const person = await request(port, {path: '/api/person?id=RCT-002',
        headers: {host: `127.0.0.1:${port}`}});
      assert.strictEqual(person.status, 200);
      assert.strictEqual(JSON.parse(person.body).person.researchId, 'RCT-002');
      const exp = await request(port, {path: '/api/export', method: 'POST',
        headers: {host: `127.0.0.1:${port}`, origin: `http://127.0.0.1:${port}`}});
      assert.strictEqual(exp.status, 200);
      const files = JSON.parse(exp.body).files;
      assert.strictEqual(files.length, 2);
      for (const f of files) {
        assert.ok(f.startsWith(exportDir));
        assert.ok(!hasMarker(fs.readFileSync(f, 'utf8')));
      }
    } finally {
      srv.close();
    }
  });

  console.log(`all ${passed} dashboard emulator tests passed`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

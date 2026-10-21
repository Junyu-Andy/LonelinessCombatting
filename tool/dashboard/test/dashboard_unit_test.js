/**
 * tool/dashboard/test/dashboard_unit_test.js — the local ops dashboard
 * without Firestore (decision 0072, which supersedes 0061):
 *
 *   NODE_PATH=functions/node_modules node tool/dashboard/test/dashboard_unit_test.js
 *
 *   - the read allowlist never names allocation data or an answer field;
 *     the daily mood value is the one exception, and may leave only on
 *     the person page (decision 0072);
 *   - the overview's weekly cells: the whole questionnaire of each week,
 *     by the server's rules (weekly_schedule);
 *   - the source never names an allocation collection and never writes;
 *   - guarded_db refuses what is not allowed and masks every query;
 *   - key_check refuses a key that can write;
 *   - public/auth.js calls only the two existing entry points, with the
 *     callable protocol and Junyu's token;
 *   - start-up refuses a key inside the repository, an export folder
 *     inside the repository, and an emulator host without --emulator.
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const fields = require('../lib/fields');
const {guardedDb} = require('../lib/guarded_db');
const leak = require('../lib/leak_guard');
const keyCheck = require('../lib/key_check');
const auth = require('../public/auth');
const server = require('../server');
const pages = require('../lib/pages');
const L = require('../lib/load');
const ws = require('../../../functions/weekly_schedule');

const DIR = path.resolve(__dirname, '..');
const ROOT = path.resolve(DIR, '..', '..');
const ALLOCATION = ['randomization_sequences', 'randomization_state',
  'sequence_versions', 'arm_assignment_log', 'pilot_assignment_log',
  'allocation_records'];

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`ok - ${name}`);
}

function source(rel) {
  return fs.readFileSync(path.join(DIR, rel), 'utf8');
}

/** A fake Firestore that records the query chain. */
function fakeDb(rows) {
  const log = [];
  function query(pathName, chain) {
    return {
      where: (...a) => query(pathName, chain.concat([['where'].concat(a)])),
      orderBy: (...a) => query(pathName, chain.concat([['orderBy'].concat(a)])),
      limit: (n) => query(pathName, chain.concat([['limit', n]])),
      select: (...f) => query(pathName, chain.concat([['select'].concat(f)])),
      get: async () => {
        log.push({path: pathName, chain});
        return {docs: (rows || []).map((r) => ({id: r.id, data: () => r.data}))};
      },
    };
  }
  return {
    log,
    collection: (p) => query(p, []),
    doc: (p) => ({get: async () => ({id: p, exists: true,
      data: () => ({weeklyScheduleV2Enabled: true})})}),
  };
}
const FieldPath = {documentId: () => '__name__'};

(async () => {
  await test('allowlist: no allocation collection, no answer field', async () => {
    for (const t of Object.keys(fields.READ_ALLOW)) {
      for (const seg of t.split('/')) {
        assert.ok(fields.DENIED_COLLECTIONS.indexOf(seg) < 0, t);
      }
      const exceptions = fields.READ_EXCEPTIONS[t] || [];
      for (const f of fields.READ_ALLOW[t]) {
        if (exceptions.indexOf(f) >= 0) continue;
        assert.ok(fields.FORBIDDEN_OUTPUT_KEYS.indexOf(f) < 0, `${t}.${f}`);
      }
    }
    for (const a of ALLOCATION) {
      assert.ok(fields.DENIED_COLLECTIONS.indexOf(a) >= 0, a);
    }
    // Decision 0072: the mood value is the one exception — read on
    // daily_mood, out on the person page's day rows only.  Still a
    // forbidden output key everywhere else.
    assert.deepStrictEqual(fields.READ_EXCEPTIONS,
        {'users/{uid}/daily_mood': ['mood']});
    assert.deepStrictEqual(fields.OUTPUT_ALLOW,
        {person: ['$.days[].moods[].mood']});
    assert.deepStrictEqual(fields.READ_ALLOW['users/{uid}/daily_mood'],
        ['date_iso', 'mood', 'is_primary', 'entry_seq_today']);
    for (const k of ['answers', 'scores', 'value', 'mood', 'items', 'text',
      'params', 'allocatedArm', 'sequencePosition']) {
      assert.ok(fields.FORBIDDEN_OUTPUT_KEYS.indexOf(k) >= 0, k);
    }
    // Outcome collections: done-or-not fields only.
    assert.deepStrictEqual(fields.READ_ALLOW['users/{uid}/pgic'],
        ['answeredAt', 'missed']);
    assert.deepStrictEqual(fields.READ_ALLOW['users/{uid}/djg_responses'],
        ['status', 'missed']);
    assert.deepStrictEqual(
        fields.READ_ALLOW['users/{uid}/social_contact_probes'],
        ['status', 'missed']);
    assert.deepStrictEqual(fields.READ_ALLOW['users/{uid}/weekly_pr'],
        ['status']);
    assert.deepStrictEqual(
        fields.READ_ALLOW['users/{uid}/check_in_responses'].indexOf('answers'),
        -1);
    assert.deepStrictEqual(fields.READ_ALLOW['outcome_entries'],
        ['researchId', 'instrument', 'timepoint']);
    assert.ok(fields.READ_ALLOW['enrollments'].indexOf('w0DjgEmotional') < 0);
    assert.ok(!fields.READ_ALLOW['users/{uid}/turns']);
  });

  await test('source: no allocation collection named, no write', async () => {
    const files = ['server.js', 'lib/guarded_db.js', 'lib/load.js',
      'lib/pages.js', 'lib/leak_guard.js', 'lib/key_check.js',
      'public/app.js', 'public/auth.js', 'public/index.html'];
    for (const f of files) {
      const text = source(f);
      for (const a of ALLOCATION) {
        assert.ok(text.indexOf(a) < 0, `${f} names ${a}`);
      }
    }
    // Only guarded_db touches the Firestore object, and only to read.
    const g = source('lib/guarded_db.js');
    for (const w of ['.set(', '.update(', '.add(', '.delete(', '.batch(',
      'runTransaction', 'bulkWriter', '.create(', 'recursiveDelete']) {
      assert.ok(g.indexOf(w) < 0, `guarded_db uses ${w}`);
    }
    for (const f of ['lib/load.js', 'lib/pages.js']) {
      const text = source(f);
      assert.ok(!/\bdb\.(collection|doc|batch|runTransaction)\b/.test(text), f);
      assert.ok(!/require\(['"]firebase-admin['"]\)/.test(text), f);
    }
    const s = source('server.js');
    assert.ok(!/\.(collection|doc)\(/.test(s), 'server.js reads directly');
    // Decision 0072: only the person route lets the mood value out.
    assert.ok((s.match(/OUTPUT_ALLOW\.\w+/g) || []).every((u) =>
      u === 'OUTPUT_ALLOW.person'));
    assert.strictEqual(s.split('json(res, value, fields.OUTPUT_ALLOW.person)')
        .length, 2);
    assert.ok(/'\/api\/person'[\s\S]{0,600}json\(res, value, fields\.OUTPUT_ALLOW\.person\)/
        .test(s), 'person route');
    for (const f of ['lib/pages.js', 'lib/load.js', 'lib/guarded_db.js']) {
      assert.ok(source(f).indexOf('OUTPUT_ALLOW') < 0, f);
    }
    assert.ok(!/\.(set|update|delete|batch)\(/.test(s.replace(
        /searchParams|res\.|headers|store\.|cache\./g, '')),
    'server.js writes');
  });

  await test('guarded_db: masks every query, refuses the rest', async () => {
    const db = fakeDb([{id: 'u1', data: {researchId: 'RCT-001'}}]);
    const g = guardedDb(db, {FieldPath});
    await g.query('enrollments').get();
    await g.query('users/{uid}/sessions', {uid: 'u1'})
        .where('startedAt', '>=', 1).orderBy('startedAt', 'desc').limit(1)
        .get();
    await g.query('users/{uid}/events', {uid: 'u1'})
        .where('name', '==', 'check_in_submitted').get();
    for (const q of db.log) {
      const sel = q.chain.find((c) => c[0] === 'select');
      assert.ok(sel, `${q.path} not masked`);
    }
    const enroll = db.log[0].chain.find((c) => c[0] === 'select').slice(1);
    assert.deepStrictEqual(enroll, fields.READ_ALLOW.enrollments);
    assert.strictEqual(db.log[1].path, 'users/u1/sessions');
    for (const bad of ['randomization_state', 'arm_assignment_log',
      'pilot_assignment_log', 'sequence_versions', 'meta', 'turns',
      'users/{uid}/turns', 'users/{uid}/mem_facts', 'llm_calls']) {
      assert.throws(() => g.query(bad, {uid: 'u1'}), /refused/, bad);
    }
    assert.throws(() => g.query('users/{uid}/sessions', {uid: 'a/b'}),
        /bad path parameter/);
    assert.throws(() => g.query('users/{uid}/sessions', {uid: '../x'}),
        /bad path parameter/);
    assert.throws(() => g.query('users/{uid}/check_in_responses', {uid: 'u1'})
        .where('answers', '==', 1), /not readable/);
    assert.throws(() => g.query('users/{uid}/events', {uid: 'u1'})
        .where('name', '==', 'voice_transcription_failed'), /by name/);
    await assert.rejects(g.query('users/{uid}/events', {uid: 'u1'}).get(),
        /by name/);
    await assert.rejects(g.config('meta/alert_config'), /not a config doc/);
    const wrapper = g.query('enrollments');
    for (const m of ['set', 'update', 'add', 'delete', 'doc', 'batch']) {
      assert.strictEqual(wrapper[m], undefined, m);
      assert.strictEqual(g[m], undefined, m);
    }
  });

  await test('leak_guard', async () => {
    assert.deepStrictEqual(leak.findLeaks({a: [{b: 1}], c: {d: 2}}), []);
    assert.deepStrictEqual(leak.findLeaks({rows: [{answers: {q1: 1}}]}),
        ['$.rows[0].answers']);
    assert.throws(() => leak.assertNoLeak({x: {mood: 3}}), /blocked output/);
    assert.throws(() => leak.assertCsvClean('researchId,value\nA,1\n'),
        /blocked CSV column/);
    assert.throws(() => leak.assertCsvClean('researchId,mood\nA,1\n'),
        /blocked CSV column/);
    // Decision 0072: the person page's mood values, there only, numbers
    // only.
    const allow = fields.OUTPUT_ALLOW.person;
    const page = {days: [{moods: [{mood: 3, primary: true},
      {mood: null, primary: false}]}, {moods: []}]};
    assert.deepStrictEqual(leak.findLeaks(page, allow), []);
    assert.strictEqual(leak.assertNoLeak(page, allow), page);
    assert.deepStrictEqual(leak.findLeaks(page),
        ['$.days[0].moods[0].mood', '$.days[0].moods[1].mood']);
    assert.throws(() => leak.assertNoLeak(page), /blocked output/);
    assert.deepStrictEqual(leak.findLeaks({person: {mood: 3}}, allow),
        ['$.person.mood']);
    assert.deepStrictEqual(leak.findLeaks({days: [{mood: 3}]}, allow),
        ['$.days[0].mood']);
    assert.deepStrictEqual(leak.findLeaks({days: [{moods: [{mood: '3'}]}]},
        allow), ['$.days[0].moods[0].mood']);
    assert.deepStrictEqual(leak.findLeaks({days: [{moods: [{mood:
      {answers: 1}}]}]}, allow), ['$.days[0].moods[0].mood',
      '$.days[0].moods[0].mood.answers']);
    assert.deepStrictEqual(leak.findLeaks({days: [{moods: [{answers: 1,
      value: 2}]}]}, allow), ['$.days[0].moods[0].answers',
      '$.days[0].moods[0].value']);
    assert.strictEqual(leak.shapeOf('$.days[12].moods[0].mood'),
        '$.days[].moods[].mood');
    assert.strictEqual(leak.assertCsvClean('researchId,arm\n'),
        'researchId,arm\n');
  });

  await test('key_check: a key that can write is refused', async () => {
    const all = keyCheck.WRITE_PERMISSIONS.concat(keyCheck.READ_PERMISSIONS);
    assert.strictEqual(keyCheck.verdict(all).ok, false);
    assert.strictEqual(keyCheck.verdict(['datastore.entities.update']
        .concat(keyCheck.READ_PERMISSIONS)).ok, false);
    assert.strictEqual(keyCheck.verdict(['datastore.entities.get']).ok, false);
    assert.strictEqual(keyCheck.verdict(keyCheck.READ_PERMISSIONS).ok, true);
    let seen = null;
    const v = await keyCheck.checkKey({projectId: 'p1',
      getAccessToken: async () => 'tok',
      fetch: async (url, o) => {
        seen = {url, o};
        return {ok: true, json: async () => ({
          permissions: keyCheck.READ_PERMISSIONS})};
      }});
    assert.strictEqual(v.ok, true);
    assert.strictEqual(seen.url, 'https://cloudresourcemanager.googleapis.com' +
      '/v1/projects/p1:testIamPermissions');
    assert.strictEqual(seen.o.headers.Authorization, 'Bearer tok');
    const bad = await keyCheck.checkKey({projectId: 'p1',
      getAccessToken: async () => 'tok',
      fetch: async () => ({ok: false, status: 403,
        json: async () => ({error: {message: 'API disabled'}})})});
    assert.strictEqual(bad.ok, false);
    assert.ok(/API disabled/.test(bad.reason));
  });

  await test('auth.js: sign-in, the two callables only, errors', async () => {
    const calls = [];
    let clock = 1000;
    const fetchFn = async (url, o) => {
      calls.push({url, o});
      if (url.indexOf('signInWithPassword') >= 0) {
        return {ok: true, json: async () => ({email: 'pi@example.org',
          idToken: 'id1', refreshToken: 'r1', expiresIn: '3600'})};
      }
      if (url.indexOf('securetoken') >= 0) {
        return {ok: true, json: async () => ({id_token: 'id2',
          refresh_token: 'r2', expires_in: '3600'})};
      }
      if (url.endsWith('/markSafetyFalseAlarm')) {
        return {ok: false, status: 400, json: async () => ({error: {
          status: 'FAILED_PRECONDITION', message: 'feature disabled'}})};
      }
      return {ok: true, json: async () => ({result: {ok: true,
        alreadyAcknowledged: false}})};
    };
    const a = auth.createAuth({apiKey: 'K', projectId: 'loneliness-pilot-dev',
      region: 'asia-east2'}, fetchFn, () => clock);
    await assert.rejects(a.call('acknowledgeAlert', {alertId: 'x'}),
        /重新登录/);
    await a.signIn('pi@example.org', 'pw');
    assert.deepStrictEqual(a.current(), {email: 'pi@example.org'});
    assert.ok(calls[0].url.startsWith('https://identitytoolkit.googleapis.com' +
      '/v1/accounts:signInWithPassword?key=K'));
    const r = await a.call('acknowledgeAlert', {alertId: 'al1'});
    assert.deepStrictEqual(r, {ok: true, alreadyAcknowledged: false});
    const last = calls[calls.length - 1];
    assert.strictEqual(last.url, 'https://asia-east2-loneliness-pilot-dev' +
      '.cloudfunctions.net/acknowledgeAlert');
    assert.strictEqual(last.o.headers.Authorization, 'Bearer id1');
    assert.deepStrictEqual(JSON.parse(last.o.body), {data: {alertId: 'al1'}});
    await assert.rejects(a.call('markSafetyFalseAlarm', {alertId: 'al1'}),
        /开关没开/);
    await assert.rejects(a.call('enrollParticipant', {}), /not allowed/);
    await assert.rejects(a.call('uploadRandomizationSequence', {}),
        /not allowed/);
    clock += 3600 * 1000; // token expired → refreshed first
    await a.call('acknowledgeAlert', {alertId: 'al1'});
    assert.ok(calls.some((c) => c.url.indexOf('securetoken') >= 0));
    assert.strictEqual(calls[calls.length - 1].o.headers.Authorization,
        'Bearer id2');
    a.signOut();
    assert.strictEqual(a.current(), null);
    const emu = auth.createAuth({apiKey: 'K', projectId: 'p', region: 'r',
      functionsEmulator: '127.0.0.1:5001'}, fetchFn);
    assert.strictEqual(emu.functionUrl('acknowledgeAlert'),
        'http://127.0.0.1:5001/p/r/acknowledgeAlert');
    assert.deepStrictEqual(auth.CALLABLES,
        ['acknowledgeAlert', 'markSafetyFalseAlarm']);
  });

  await test('the web API key is the App\'s web key', async () => {
    const dart = fs.readFileSync(path.join(ROOT, 'lib', 'firebase_options.dart'),
        'utf8');
    const web = dart.slice(dart.indexOf('FirebaseOptions web'));
    assert.ok(web.indexOf(`apiKey: '${server.WEB_API_KEY}'`) >= 0);
    assert.strictEqual(server.PROJECT, 'loneliness-pilot-dev');
  });

  await test('start-up refuses unsafe setups', async () => {
    const keyInRepo = path.join(ROOT, 'functions', 'package.json');
    const p1 = server.startupProblems({GOOGLE_APPLICATION_CREDENTIALS:
      keyInRepo}, {});
    assert.ok(p1.some((m) => /仓库里面/.test(m)), p1.join());
    const p2 = server.startupProblems({}, {});
    assert.ok(p2.some((m) => /GOOGLE_APPLICATION_CREDENTIALS/.test(m)));
    const p3 = server.startupProblems({FIRESTORE_EMULATOR_HOST: 'x:1',
      GOOGLE_APPLICATION_CREDENTIALS: '/nonexistent.json'}, {});
    assert.ok(p3.some((m) => /FIRESTORE_EMULATOR_HOST/.test(m)));
    assert.deepStrictEqual(server.startupProblems(
        {FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080'}, {emulator: true}), []);
    assert.ok(server.startupProblems({}, {emulator: true}).length);
    assert.throws(() => server.exportDir({DASHBOARD_EXPORT_DIR:
      path.join(ROOT, 'build')}), /仓库里面/);
    assert.ok(server.exportDir({DASHBOARD_EXPORT_DIR: '/tmp/x'}));
  });

  await test('weekly CSV rows from day rows', async () => {
    const days = [
      {dayKey: 'd1', studyDay: 1, opened: true, foregroundMinutes: 10,
        validSessions: {siu_yan: 1}, briefPrInvited: 1, briefPrCompleted: 1,
        basis: 'usage'},
      {dayKey: 'd2', studyDay: 7, opened: false, foregroundMinutes: 0,
        validSessions: {}, basis: 'usage'},
      {dayKey: 'd3', studyDay: 8, opened: true, foregroundMinutes: 5,
        validSessions: {tung_tung: 2}, basis: 'usage'},
    ];
    const rows = pages.weeklyRowsFor({researchId: 'RCT-1', cohort: 'RCT',
      arm: 'B'}, days, new Set(['d1', 'd3']), new Set(['d2']));
    assert.deepStrictEqual(rows, [
      ['RCT-1', 'RCT', 'B', 1, 1, 7, 2, 1, 10, 1, 0, 0, 1, 1, 1, 1, 1, 'usage'],
      ['RCT-1', 'RCT', 'B', 2, 8, 8, 1, 1, 5, 0, 0, 2, 2, 0, 0, 1, 0, 'usage'],
    ]);
  });

  await test('part done: the server\'s rule, PGIC by its answer time', async () => {
    const P = ws.PART;
    const cases = [[P.DJG, {status: 'submitted'}], [P.DJG, {status: 'missed'}],
      [P.DJG, null], [P.SOCIAL, {status: 'submitted'}],
      [P.SOCIAL, {status: 'in_progress'}], [P.WEEKLY_PR, {status: 'completed'}],
      [P.WEEKLY_PR, {status: 'skipped'}], [P.WEEKLY_PR, {status: 'no_referent'}],
      [P.WEEKLY_PR, {status: 'missed'}], [P.WEEKLY_PR, {}]];
    for (const [part, data] of cases) {
      assert.strictEqual(L.partDone(part, data), ws.partSubmitted(part, data),
          `${part} ${JSON.stringify(data)}`);
    }
    // PGIC: the server checks the answer `value`; the dashboard never
    // reads it — the App writes answeredAt with it.
    const at = new Date('2026-11-08T04:00:00Z');
    assert.strictEqual(L.partDone(P.PGIC, {answeredAt: at}),
        ws.partSubmitted(P.PGIC, {value: 4, answeredAt: at}));
    assert.strictEqual(L.partDone(P.PGIC, {missed: true}),
        ws.partSubmitted(P.PGIC, {missed: true, status: 'missed'}));
    // Answered after the missed mark: done, as on the server.
    assert.strictEqual(L.partDone(P.PGIC, {answeredAt: at, missed: true}),
        ws.partSubmitted(P.PGIC, {value: 4, answeredAt: at, missed: true}));
    assert.strictEqual(L.partDone(P.PGIC, null), false);
  });

  await test('weekly cells: the whole questionnaire of each week', async () => {
    const cfg = ws.configFromData({weeklyScheduleV2Enabled: true,
      socialContactProbeEnabled: true}, {weeklyReminderV2Enabled: true});
    const w0 = '2026-11-01';
    const day8 = new Date('2026-11-09T02:00:00Z'); // 10:00 HK, study day 8
    const day10 = new Date('2026-11-11T02:00:00Z');
    const recs = {djg: {W1: {status: 'submitted'}},
      weekly_pr: {W1: {status: 'completed'}}, pgic: {},
      social_contact: {W1: {status: 'submitted'}}};
    const cells = pages.weeklyCellsFor(cfg, w0, {}, recs,
        {W1: {pushedAt: day8}}, day8);
    assert.deepStrictEqual(Object.keys(cells),
        ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8']);
    // Whole days 7–9 (reminders v2); PGIC still open.
    assert.deepStrictEqual(cells.W1, {status: 'open', partsDone: 3,
      partsTotal: 4, parts: {djg: true, weekly_pr: true, pgic: false,
        social_contact: true}, opensOn: '2026-11-08', closesOn: '2026-11-10'});
    assert.strictEqual(cells.W2.status, 'not_yet');
    assert.deepStrictEqual(cells.W4.parts, {weekly_pr: false, pgic: false,
      social_contact: false});
    // W5–W7: PGIC only, whole days 35–37 (decision 0067).
    assert.deepStrictEqual(cells.W5, {status: 'not_yet', partsDone: 0,
      partsTotal: 1, parts: {pgic: false}, opensOn: '2026-12-06',
      closesOn: '2026-12-08'});
    assert.deepStrictEqual(cells.W8, {status: 'not_built'});
    // Closed with a part missing → missed; every part → done.
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0, {}, recs, {}, day10)
        .W1.status, 'missed');
    const all = Object.assign({}, recs, {pgic: {W1: {answeredAt: day8}}});
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0, {}, all, {}, day10)
        .W1.status, 'done');
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0, {}, all, {}, day8)
        .W1.status, 'done');
    // The server's missed mark counts even inside the window.
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0, {}, recs,
        {W1: {missedAt: day8}}, day8).W1.status, 'missed');
    // Before 00:00 of day 7, nothing pushed: not yet.
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0, {}, {}, {},
        new Date('2026-11-07T10:00:00Z')).W1.status, 'not_yet');
    // W4 closes on the recorded visit day (users.w4RecordedOn).
    assert.strictEqual(pages.weeklyCellsFor(cfg, w0,
        {w4RecordedOn: '2026-11-30'}, {}, {}, day8).W4.closesOn, '2026-11-30');
    // Schedule switch off.
    const off = pages.weeklyCellsFor(ws.configFromData({}, null), w0, {}, {},
        {}, day8);
    assert.deepStrictEqual(off.W1, {status: 'off'});
    assert.deepStrictEqual(off.W8, {status: 'not_built'});
    assert.deepStrictEqual(pages.partsOf(cfg),
        ['djg', 'weekly_pr', 'pgic', 'social_contact']);
    assert.deepStrictEqual(pages.partsOf(ws.configFromData(
        {weeklyScheduleV2Enabled: true}, null)), ['djg', 'weekly_pr', 'pgic']);
    // Done or not only.
    assert.deepStrictEqual(leak.findLeaks(cells), []);
  });

  await test('mood values by day, the first entry first', async () => {
    assert.deepStrictEqual(pages.moodsByDay([
      {data: {date_iso: '2026-11-08', mood: 2, is_primary: false,
        entry_seq_today: 2}},
      {data: {date_iso: '2026-11-08', mood: 4, is_primary: true,
        entry_seq_today: 1}},
      {data: {date_iso: '2026-11-09', mood: 'x'}},
      {data: {mood: 5}},
    ]), {
      '2026-11-08': [{mood: 4, primary: true}, {mood: 2, primary: false}],
      '2026-11-09': [{mood: null, primary: false}],
    });
  });

  console.log(`all ${passed} dashboard unit tests passed`);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

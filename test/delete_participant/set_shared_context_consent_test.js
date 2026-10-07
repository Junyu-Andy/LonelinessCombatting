/**
 * tool/set_shared_context_consent.js against the Firestore emulator, with
 * synthetic users only (decision 0020). Run by tool/ci_backend_tests.sh
 * inside the same emulators as delete_participant_test.js.
 */
'use strict';
/* eslint-disable require-jsdoc */

const assert = require('assert');
const admin = require('firebase-admin');
const tool = require('../../tool/set_shared_context_consent');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('FIRESTORE_EMULATOR_HOST not set — run inside the emulator.');
  process.exit(1);
}
admin.initializeApp({projectId: 'loneliness-pilot-dev'});
const db = admin.firestore();
const users = db.collection('users');

async function seed() {
  await db.recursiveDelete(users);
  await users.doc('synthNoConsentField00000001').set({arm: 'A'});
  await users.doc('synthConsentFalse0000000002').set({arm: 'B',
    consent: {functionalData: true, transcriptRetention: true,
      sharedContextUse: false}});
  await users.doc('synthConsentTrue00000000003').set({arm: 'A',
    consent: {sharedContextUse: true}});
}

const shared = async (uid) => (await users.doc(uid).get())
    .get('consent.sharedContextUse');

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test('--all dry run lists the accounts and writes nothing', async () => {
  await seed();
  const r = await tool.run({db, uids: null, value: true, confirm: false});
  assert.deepStrictEqual(r.changed.sort(), ['synthConsentFalse0000000002',
    'synthNoConsentField00000001']);
  assert.strictEqual(r.unchanged, 1);
  assert.strictEqual(await shared('synthConsentFalse0000000002'), false);
  assert.strictEqual(await shared('synthNoConsentField00000001'), undefined);
});

test('--all --confirm sets every account to true, keeps other consent',
    async () => {
      const r = await tool.run({db, uids: null, value: true, confirm: true});
      assert.strictEqual(r.changed.length, 2);
      for (const d of (await users.get()).docs) {
        assert.strictEqual(d.get('consent.sharedContextUse'), true, d.id);
      }
      const d = await users.doc('synthConsentFalse0000000002').get();
      assert.strictEqual(d.get('consent.transcriptRetention'), true);
      assert.strictEqual(d.get('consent.functionalData'), true);
      assert.strictEqual(d.get('sharedContextUseSetBy'),
          'tool/set_shared_context_consent.js');
      assert.ok(d.get('sharedContextUseSetAt'));
      // Already-true account is left alone (no audit stamp).
      const t = await users.doc('synthConsentTrue00000000003').get();
      assert.strictEqual(t.get('sharedContextUseSetBy'), undefined);
    });

test('--uid --off turns one person off; others untouched', async () => {
  const uid = 'synthConsentTrue00000000003';
  const dry = await tool.run({db, uids: [uid], value: false,
    confirm: false});
  assert.deepStrictEqual(dry.changed, [uid]);
  assert.strictEqual(await shared(uid), true, 'dry run writes nothing');
  await tool.run({db, uids: [uid], value: false, confirm: true});
  assert.strictEqual(await shared(uid), false);
  assert.strictEqual(await shared('synthConsentFalse0000000002'), true);
  const again = await tool.run({db, uids: [uid], value: false,
    confirm: true});
  assert.deepStrictEqual(again.changed, [], 'idempotent');
});

test('unknown uid is reported, nothing created', async () => {
  const r = await tool.run({db, uids: ['synthMissing000000000000004'],
    value: false, confirm: true});
  assert.deepStrictEqual(r.missing, ['synthMissing000000000000004']);
  assert.strictEqual((await users.doc('synthMissing000000000000004').get())
      .exists, false);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL  ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();

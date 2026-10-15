/**
 * 1014e §2.3 (backlog 96) — `users/{uid}.isTester` is admin-only.
 *
 *   - A client create may not carry isTester (true or false).
 *   - A client update may not set, change or clear it.
 *   - Everything else on the profile still writes as before, also on a
 *     profile that already holds isTester: true (the App omits the field,
 *     so a merge write leaves the server's value alone).
 *   - The Admin SDK (rules bypassed) is how tool/set_tester.js writes it.
 *
 * Run inside the emulator (see README.md).
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteField } = require('firebase/firestore');

const PROJECT_ID = 'loneliness-pilot-dev';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const owner = () => testEnv.authenticatedContext('u1').firestore();
const profile = (db) => doc(db, 'users', 'u1');

async function seed(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'u1'), data);
  });
}

describe('1014e §2.3: users/{uid}.isTester is admin-only', () => {
  it('DENIES a signup create carrying isTester (true or false)', async () => {
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', displayName: 'x', isTester: true }));
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', displayName: 'x', isTester: false }));
  });

  it('ALLOWS the signup create without it (what the App writes now)',
    async () => {
      await assertSucceeds(setDoc(profile(owner()),
        { uid: 'u1', displayName: 'x', ageGroup: '70-74', consent: {} }));
    });

  it('DENIES setting, changing or clearing it on update', async () => {
    await seed({ uid: 'u1', displayName: 'x' });
    await assertFails(updateDoc(profile(owner()), { isTester: true }));
    await assertFails(setDoc(profile(owner()), { isTester: true },
      { merge: true }));
    await seed({ uid: 'u1', displayName: 'x', isTester: true });
    await assertFails(updateDoc(profile(owner()), { isTester: false }));
    await assertFails(updateDoc(profile(owner()),
      { isTester: deleteField() }));
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', displayName: 'y' }));  // full overwrite would drop it
  });

  it('ALLOWS ordinary profile writes on a tester profile (merge, flag '
     + 'omitted) and on a non-tester profile', async () => {
    await seed({ uid: 'u1', displayName: 'x', isTester: true });
    await assertSucceeds(setDoc(profile(owner()),
      { displayName: 'y', memory_enabled: false }, { merge: true }));
    await assertSucceeds(updateDoc(profile(owner()), { fontScale: 'large' }));
    await seed({ uid: 'u1', displayName: 'x' });
    await assertSucceeds(setDoc(profile(owner()),
      { displayName: 'z' }, { merge: true }));
  });

  it('ALLOWS rewriting the same value (a merge that repeats it)', async () => {
    await seed({ uid: 'u1', displayName: 'x', isTester: true });
    await assertSucceeds(setDoc(profile(owner()),
      { displayName: 'y', isTester: true }, { merge: true }));
  });
});

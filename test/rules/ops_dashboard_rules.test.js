/**
 * T39 — Firestore rules for the operations dashboard's server-only
 * collections: ops_daily/{uid}/days/{dayKey} (stored day rows) and
 * ops_audit_log/{id}.  No client reads or writes them — participant,
 * blinded assessor, unblinded researcher alike; the researcher reads
 * through the callables.
 *
 * Run inside the emulator (see README.md).
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, collection, setDoc, addDoc, getDoc, getDocs, deleteDoc } =
  require('firebase/firestore');

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
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'ops_daily/u1/days/2026-10-16'),
      { uid: 'u1', opened: true, foregroundMinutes: 12 });
    await setDoc(doc(db, 'ops_audit_log/a1'),
      { type: 'open_people', by: 'k1' });
  });
});

const participant = () => testEnv.authenticatedContext('u1').firestore();
const blinded = () =>
  testEnv.authenticatedContext('pi1', { role: 'blinded' }).firestore();
const unblinded = () =>
  testEnv.authenticatedContext('k1', { role: 'unblinded' }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

describe('T39 ops dashboard collections are server-only', () => {
  for (const [name, ctx] of [['participant (the owner uid)', participant],
    ['blinded assessor', blinded], ['unblinded researcher', unblinded],
    ['anonymous', anon]]) {
    it(`${name}: cannot read or write ops_daily`, async () => {
      const db = ctx();
      await assertFails(getDoc(doc(db, 'ops_daily/u1/days/2026-10-16')));
      await assertFails(getDocs(collection(db, 'ops_daily/u1/days')));
      await assertFails(setDoc(doc(db, 'ops_daily/u1/days/2026-10-17'),
        { opened: true }));
      await assertFails(deleteDoc(doc(db, 'ops_daily/u1/days/2026-10-16')));
    });

    it(`${name}: cannot read or write ops_audit_log`, async () => {
      const db = ctx();
      await assertFails(getDoc(doc(db, 'ops_audit_log/a1')));
      await assertFails(getDocs(collection(db, 'ops_audit_log')));
      await assertFails(addDoc(collection(db, 'ops_audit_log'),
        { type: 'open_people' }));
      await assertFails(deleteDoc(doc(db, 'ops_audit_log/a1')));
    });
  }
});

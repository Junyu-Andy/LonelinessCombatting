/**
 * T12 blinding rules (decision 0021): the research-ID lookup is readable
 * only by the unblinded role; no client writes it.  T19 (decision 0029)
 * renamed the roles ('pi' → 'unblinded', 'researcher' → 'blinded'; the
 * PI is now blinded) and closed meta/arm_counter to every client.
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
const {
  doc, setDoc, getDoc, getDocs, deleteDoc, collection,
} = require('firebase/firestore');

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

const participant = () => testEnv.authenticatedContext('u1').firestore();
const blinded = () => testEnv.authenticatedContext('pi1',
  { role: 'blinded' }).firestore();
const unblinded = () => testEnv.authenticatedContext('k1',
  { role: 'unblinded' }).firestore();
// Claims issued before T19: they must grant nothing now.
const legacyPi = () => testEnv.authenticatedContext('old1',
  { role: 'pi' }).firestore();
const legacyResearcher = () => testEnv.authenticatedContext('old2',
  { role: 'researcher' }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

describe('T12 blinding rules', () => {
  // Inside describe: a top-level hook would run for every rules file.
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'research_id_map', 'u1'), { researchId: 'P0ZAHP5' });
      await setDoc(doc(db, 'research_ids', 'P0ZAHP5'), { uid: 'u1' });
      await setDoc(doc(db, 'meta', 'arm_counter'),
        { cell_0: { aCount: 3, bCount: 2 } });
      await setDoc(doc(db, 'meta', 'blinding_config'), { enabled: true });
      await setDoc(doc(db, 'export_blind_keys', 'stable_v2'),
        { mapping: { A: 'Group_X', B: 'Group_Y' } });
      await setDoc(doc(db, 'users', 'u1'), { arm: 'A' });
    });
  });

  it('the unblinded role reads the research-ID lookup', async () => {
    const db = unblinded();
    await assertSucceeds(getDoc(doc(db, 'research_id_map', 'u1')));
    await assertSucceeds(getDoc(doc(db, 'research_ids', 'P0ZAHP5')));
    await assertSucceeds(getDocs(collection(db, 'research_id_map')));
  });

  it('participants, blinded researchers and anonymous users cannot',
    async () => {
      for (const db of [participant(), blinded(), anon(), legacyPi(),
        legacyResearcher()]) {
        await assertFails(getDoc(doc(db, 'research_id_map', 'u1')));
        await assertFails(getDoc(doc(db, 'research_ids', 'P0ZAHP5')));
        await assertFails(getDocs(collection(db, 'research_id_map')));
      }
    });

  it('no client writes the lookup, the unblinded role included', async () => {
    for (const db of [participant(), blinded(), unblinded()]) {
      await assertFails(setDoc(doc(db, 'research_id_map', 'u1'),
        { researchId: 'P111111' }));
      await assertFails(setDoc(doc(db, 'research_ids', 'P111111'),
        { uid: 'u1' }));
      await assertFails(deleteDoc(doc(db, 'research_ids', 'P0ZAHP5')));
    }
  });

  it('retired per-arm counter: no client reads it (T19)', async () => {
    for (const db of [unblinded(), blinded(), participant(), anon(),
      legacyPi()]) {
      await assertFails(getDoc(doc(db, 'meta', 'arm_counter')));
    }
  });

  it('blind keys and the blinding switch stay server-only', async () => {
    for (const db of [participant(), blinded(), unblinded()]) {
      await assertFails(getDoc(doc(db, 'export_blind_keys', 'stable_v2')));
      await assertFails(getDoc(doc(db, 'meta', 'blinding_config')));
      await assertFails(setDoc(doc(db, 'meta', 'blinding_config'),
        { enabled: false }));
    }
  });

  it('a blinded researcher cannot read a participant profile (arm)',
    async () => {
      await assertFails(getDoc(doc(blinded(), 'users', 'u1')));
    });
});

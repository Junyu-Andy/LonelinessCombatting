/**
 * T30 rules (dev-tasks-1014 §三 T30 2; dev-tasks-1010 §四 T30 §4.2, §7):
 * two synthetic assessor accounts (`blinded`) read nothing — not a profile
 * (arm), not Brief PR / Weekly PR / sessions / turns / events (usage,
 * chats), not safety_events / pi_alerts, not the research-ID lookup, not
 * the sequence / state / enrollments, not outcome_entries or anything T30
 * added.  The `sequence_uploader` role reads nothing either.  No client
 * role reads another person's outcome records (djg_responses,
 * outcome_entries); the unblinded researcher included.
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
  doc, setDoc, getDoc, getDocs, collection, addDoc, updateDoc, deleteDoc,
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

const ELDER = 'elderUid00000000000000000001';
const participant = () => testEnv.authenticatedContext(ELDER).firestore();
const other = () => testEnv.authenticatedContext('elder2').firestore();
const keran = () => testEnv.authenticatedContext('assessorKeran',
  { role: 'blinded' }).firestore();
const mingyan = () => testEnv.authenticatedContext('assessorMingyan',
  { role: 'blinded' }).firestore();
const junyu = () => testEnv.authenticatedContext('junyu',
  { role: 'unblinded' }).firestore();
const calvin = () => testEnv.authenticatedContext('calvin',
  { role: 'sequence_uploader' }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

const T30_SERVER_ONLY = [
  ['outcome_entries', 'e1'],
  ['outcome_entry_corrections', 'c1'],
  ['weekly_status', ELDER],
  ['sequence_upload_log', 'l1'],
  ['pairing_change_log', 'p1'],
  ['allocation_records', 'PB-001'],
  ['meta', 'data_lock'],
  ['analysis_export_log', 'a1'],
  ['process_export_log', 'x1'],
];

// What the assessor must never see, by path.
const BLINDING_READS = [
  ['users', ELDER], // arm
  ['users', ELDER, 'brief_pr', 'b1'],
  ['users', ELDER, 'weekly_pr', 'w1'],
  ['users', ELDER, 'sessions', 's1'], // usage
  ['users', ELDER, 'turns', 't1'], // chats
  ['users', ELDER, 'events', 'ev1'],
  ['users', ELDER, 'djg_responses', 'W2'], // outcome record
  ['safety_events', 'se1'],
  ['pi_alerts', 'al1'],
  ['research_id_map', ELDER],
  ['research_ids', 'PB-001'],
  ['randomization_sequences', 'low'],
  ['randomization_state', 'low'],
  ['enrollments', ELDER],
  ['arm_assignment_log', 'g1'],
  ['export_blind_keys', 'stable_v2'],
  ['meta', 'blinding_config'],
  ['meta', 'randomization_config'],
].concat(T30_SERVER_ONLY);

describe('T30 assessor and uploader roles', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', ELDER), { arm: 'A', cohort: 'phase_b',
        displayName: '陳太' });
      await setDoc(doc(db, 'users', ELDER, 'brief_pr', 'b1'),
        { understanding: 6, arm: 'A' });
      await setDoc(doc(db, 'users', ELDER, 'weekly_pr', 'w1'),
        { items: { u: 5 } });
      await setDoc(doc(db, 'users', ELDER, 'sessions', 's1'),
        { isValid: true });
      await setDoc(doc(db, 'users', ELDER, 'turns', 't1'), { text: '你好' });
      await setDoc(doc(db, 'users', ELDER, 'events', 'ev1'),
        { name: 'app_open' });
      await setDoc(doc(db, 'users', ELDER, 'djg_responses', 'W2'),
        { timepoint: 'W2', status: 'submitted', scores: { total: 3 } });
      await setDoc(doc(db, 'safety_events', 'se1'), { uid: ELDER,
        source: 'ai_output_scan', level: 'acute' });
      await setDoc(doc(db, 'pi_alerts', 'al1'), { uid: ELDER, level: 'acute' });
      await setDoc(doc(db, 'research_id_map', ELDER),
        { researchId: 'PB-001' });
      await setDoc(doc(db, 'research_ids', 'PB-001'), { uid: ELDER });
      await setDoc(doc(db, 'randomization_sequences', 'low'),
        { arms: ['A', 'B'] });
      await setDoc(doc(db, 'randomization_state', 'low'), { next: 1 });
      await setDoc(doc(db, 'enrollments', ELDER), { arm: 'A',
        researchId: 'PB-001' });
      await setDoc(doc(db, 'arm_assignment_log', 'g1'), { arm: 'A' });
      await setDoc(doc(db, 'export_blind_keys', 'stable_v2'),
        { mapping: { A: 'Group_X' } });
      await setDoc(doc(db, 'meta', 'blinding_config'), { enabled: true });
      await setDoc(doc(db, 'meta', 'randomization_config'),
        { enabled: true, sequenceUploadEnabled: true });
      for (const [col, id] of T30_SERVER_ONLY) {
        await setDoc(doc(db, col, id), { researchId: 'PB-001', arm: 'A',
          scores: { total: 6 } });
      }
    });
  });

  it('both assessor accounts read nothing — item by item', async () => {
    for (const db of [keran(), mingyan()]) {
      for (const p of BLINDING_READS) {
        await assertFails(getDoc(doc(db, ...p)), p.join('/'));
      }
      for (const col of ['users', 'safety_events', 'pi_alerts',
        'research_id_map', 'enrollments', 'outcome_entries',
        'randomization_sequences', 'allocation_records']) {
        await assertFails(getDocs(collection(db, col)), col);
      }
      await assertFails(getDocs(collection(db, 'users', ELDER, 'brief_pr')));
      await assertFails(getDocs(collection(db, 'users', ELDER, 'turns')));
    }
  });

  it('assessors write nothing: not an outcome entry, not a profile, ' +
    'not a safety event with their source', async () => {
    for (const db of [keran(), mingyan()]) {
      await assertFails(addDoc(collection(db, 'outcome_entries'),
        { researchId: 'PB-001', answers: { q1: 'yes' } }));
      await assertFails(setDoc(doc(db, 'weekly_status', ELDER),
        { w4VisitDate: '2026-11-27' }));
      await assertFails(updateDoc(doc(db, 'users', ELDER),
        { displayName: 'x' }));
      await assertFails(addDoc(collection(db, 'safety_events'),
        { uid: ELDER, source: 'assessor_entry', textHash: 'h',
          level: 'acute' }));
      await assertFails(deleteDoc(doc(db, 'outcome_entries', 'e1')));
    }
  });

  it('the sequence uploader reads and writes nothing in Firestore', async () => {
    const db = calvin();
    for (const p of BLINDING_READS) {
      await assertFails(getDoc(doc(db, ...p)), p.join('/'));
    }
    await assertFails(setDoc(doc(db, 'randomization_sequences', 'high'),
      { arms: ['A', 'B'] }));
    await assertFails(setDoc(doc(db, 'randomization_state', 'high'),
      { next: 0 }));
    await assertFails(addDoc(collection(db, 'sequence_upload_log'),
      { by: 'calvin' }));
  });

  it('no client role reads the sequence, the state or the upload log',
    async () => {
      for (const db of [participant(), keran(), junyu(), calvin(), anon()]) {
        await assertFails(getDoc(doc(db, 'randomization_sequences', 'low')));
        await assertFails(getDoc(doc(db, 'randomization_state', 'low')));
        await assertFails(getDoc(doc(db, 'sequence_upload_log', 'l1')));
      }
    });

  it('T30 server-only collections are closed to every client role',
    async () => {
      for (const db of [participant(), keran(), junyu(), calvin(), anon()]) {
        for (const [col, id] of T30_SERVER_ONLY) {
          await assertFails(getDoc(doc(db, col, id)), `${col} read`);
          await assertFails(setDoc(doc(db, col, id), { x: 1 }),
            `${col} write`);
        }
      }
    });

  it('outcome records: only the owner reads their own in-App record; ' +
    'nobody — unblinded included — reads another person\'s', async () => {
    await assertSucceeds(getDoc(doc(participant(), 'users', ELDER,
      'djg_responses', 'W2')));
    for (const db of [other(), keran(), mingyan(), junyu(), calvin(), anon()]) {
      await assertFails(getDoc(doc(db, 'users', ELDER, 'djg_responses', 'W2')));
      await assertFails(getDoc(doc(db, 'outcome_entries', 'e1')));
    }
  });

  it('the unblinded researcher keeps what T12 / T34 gave: the lookup and ' +
    'pi_alerts — but no outcome entry and no sequence', async () => {
    const db = junyu();
    await assertSucceeds(getDoc(doc(db, 'research_id_map', ELDER)));
    await assertSucceeds(getDoc(doc(db, 'pi_alerts', 'al1')));
    await assertFails(getDoc(doc(db, 'outcome_entries', 'e1')));
    await assertFails(getDoc(doc(db, 'meta', 'data_lock')));
    await assertFails(getDoc(doc(db, 'randomization_sequences', 'low')));
    await assertFails(getDoc(doc(db, 'users', ELDER)));
  });

  it('a participant cannot set their own pairing in the registration ' +
    'record (it is server-only), only on the profile', async () => {
    const db = participant();
    await assertFails(updateDoc(doc(db, 'enrollments', ELDER),
      { companionVariant: 'masculine' }));
    await assertSucceeds(updateDoc(doc(db, 'users', ELDER),
      { ahJanAhBakVariant: 'masculine' }));
  });
});

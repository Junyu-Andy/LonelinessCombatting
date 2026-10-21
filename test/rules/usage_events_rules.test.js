/**
 * T40 (registry C23) — Firestore rules for users/{uid}/usage_events.
 *
 *   - An ENROLLED owner (cohort phase_b / rct / pilot) may create a row with
 *     exactly the client fields (type, clientAt, receivedAt = server time,
 *     appVersion, buildNumber, platform, schemaVersion 1).
 *   - Not before registration: no cohort (even a tester) → refused.
 *   - The owner never reads, updates or deletes a row (the server stamps
 *     the research ID on it — decision 0021).
 *   - Server-only fields (researchId, studyDay, uploadedLate, …) can never
 *     come from the client; a bad type or a missing field is refused.
 *   - Another account, blinded or unblinded, cannot touch the rows.
 *   - 1020c §1(5): the 小讀本 rows (reader_open / reader_section /
 *     reader_cta / reader_close) with exactly their own extra field(s);
 *     ids are slugs, so no text fits; foreground / background rows may
 *     not carry reader fields.
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
  doc, collection, setDoc, addDoc, getDoc, getDocs, updateDoc, deleteDoc,
  serverTimestamp, Timestamp,
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

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const me = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const unblinded = () =>
  testEnv.authenticatedContext('staff', { role: 'unblinded' }).firestore();
const blinded = () =>
  testEnv.authenticatedContext('keran', { role: 'blinded' }).firestore();

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

const col = (db, uid) => collection(db, 'users', uid || 'u1', 'usage_events');

function row(extra) {
  return Object.assign({
    type: 'foreground',
    clientAt: Timestamp.fromDate(new Date('2026-10-20T03:59:58Z')),
    receivedAt: serverTimestamp(),
    appVersion: '1.0.0',
    buildNumber: '3',
    platform: 'android',
    schemaVersion: 1,
  }, extra || {});
}

describe('T40: users/{uid}/usage_events', () => {
  for (const cohort of ['phase_b', 'rct', 'pilot']) {
    it(`ALLOWS an enrolled owner (${cohort}) to append foreground and ` +
       'background rows', async () => {
      await seed('users/u1', { uid: 'u1', cohort, arm: 'A' });
      await assertSucceeds(addDoc(col(me()), row()));
      await assertSucceeds(addDoc(col(me()), row({ type: 'background' })));
    });
  }

  it('DENIES an account with no cohort (not registered yet)', async () => {
    await seed('users/u1', { uid: 'u1' });
    await assertFails(addDoc(col(me()), row()));
  });

  it('DENIES a tester without a cohort', async () => {
    await seed('users/u1', { uid: 'u1', isTester: true });
    await assertFails(addDoc(col(me()), row()));
  });

  it('DENIES a phase_a cohort (not a Phase B / pilot participant)', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_a' });
    await assertFails(addDoc(col(me()), row()));
  });

  it('DENIES the owner reading, updating or deleting a row', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'pilot', arm: 'B' });
    await seed('users/u1/usage_events/e1', row({ receivedAt: Timestamp.now() }));
    await assertFails(getDoc(doc(me(), 'users', 'u1', 'usage_events', 'e1')));
    await assertFails(getDocs(col(me())));
    await assertFails(updateDoc(doc(me(), 'users', 'u1', 'usage_events', 'e1'),
      { type: 'background' }));
    await assertFails(deleteDoc(doc(me(), 'users', 'u1', 'usage_events', 'e1')));
  });

  for (const f of ['researchId', 'dayKey', 'studyDay', 'uploadedLate',
    'lateByMs', 'clockSkew', 'stampedAt']) {
    it(`DENIES a create carrying the server field ${f}`, async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'B' });
      const data = row();
      data[f] = f === 'uploadedLate' ? false : 'x';
      await assertFails(addDoc(col(me()), data));
    });
  }

  it('DENIES a bad type, a string clientAt, a client receivedAt, ' +
     'schemaVersion 2, a missing field, an extra field', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
    await assertFails(addDoc(col(me()), row({ type: 'screen_view' })));
    await assertFails(addDoc(col(me()), row({ clientAt: '2026-10-20' })));
    await assertFails(addDoc(col(me()), row({ receivedAt: Timestamp.now() })));
    await assertFails(addDoc(col(me()), row({ schemaVersion: 2 })));
    const missing = row();
    delete missing.buildNumber;
    await assertFails(addDoc(col(me()), missing));
    await assertFails(addDoc(col(me()), row({ text: '今日好開心' })));
  });

  it('DENIES another participant, an unblinded or a blinded account',
    async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      await seed('users/u1/usage_events/e1', row({ receivedAt: Timestamp.now() }));
      await assertFails(addDoc(col(other()), row()));
      await assertFails(getDoc(doc(other(), 'users', 'u1', 'usage_events', 'e1')));
      await assertFails(addDoc(col(unblinded()), row()));
      await assertFails(getDoc(doc(unblinded(), 'users', 'u1', 'usage_events', 'e1')));
      await assertFails(addDoc(col(blinded()), row()));
      await assertFails(getDoc(doc(blinded(), 'users', 'u1', 'usage_events', 'e1')));
    });

  describe('1020c reader rows', () => {
    const reader = (type, extra) =>
      row(Object.assign({ type, unitId: 'u2_why_it_matters' }, extra || {}));

    for (const cohort of ['phase_b', 'pilot']) {
      it(`ALLOWS the four reader rows for an enrolled owner (${cohort})`,
        async () => {
          await seed('users/u1', { uid: 'u1', cohort, arm: 'B' });
          await assertSucceeds(addDoc(col(me()), reader('reader_open')));
          await assertSucceeds(addDoc(col(me()),
            reader('reader_section', { sectionId: 's2_middle' })));
          for (const cta of ['small_action', 'plan', 'thought', 'chat_siu_yan']) {
            await assertSucceeds(addDoc(col(me()),
              reader('reader_cta', { cta })));
          }
          await assertSucceeds(addDoc(col(me()),
            reader('reader_close', { seconds: 0 })));
          await assertSucceeds(addDoc(col(me()),
            reader('reader_close', { seconds: 86400 })));
        });
    }

    it('DENIES reader rows before registration', async () => {
      await seed('users/u1', { uid: 'u1', isTester: true });
      await assertFails(addDoc(col(me()), reader('reader_open')));
    });

    it('DENIES text in any field and malformed ids', async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      await assertFails(addDoc(col(me()),
        reader('reader_open', { unitId: '點解孤單要理' })));
      await assertFails(addDoc(col(me()),
        reader('reader_open', { unitId: 'U2 why' })));
      await assertFails(addDoc(col(me()),
        reader('reader_open', { unitId: 'x'.repeat(49) })));
      await assertFails(addDoc(col(me()),
        reader('reader_section', { sectionId: '我讀到第二節' })));
      await assertFails(addDoc(col(me()),
        reader('reader_cta', { cta: 'call_hotline' })));
      await assertFails(addDoc(col(me()),
        reader('reader_open', { text: '今日好開心' })));
    });

    it('DENIES a missing or a foreign extra field', async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      const noUnit = reader('reader_open');
      delete noUnit.unitId;
      await assertFails(addDoc(col(me()), noUnit));
      await assertFails(addDoc(col(me()), reader('reader_section')));
      await assertFails(addDoc(col(me()), reader('reader_cta')));
      await assertFails(addDoc(col(me()), reader('reader_close')));
      await assertFails(addDoc(col(me()),
        reader('reader_open', { seconds: 3 })));
      await assertFails(addDoc(col(me()),
        reader('reader_section', { sectionId: 's1', cta: 'plan' })));
      await assertFails(addDoc(col(me()),
        reader('reader_close', { seconds: 5, sectionId: 's1' })));
    });

    it('DENIES bad seconds and an unknown reader type', async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      await assertFails(addDoc(col(me()),
        reader('reader_close', { seconds: -1 })));
      await assertFails(addDoc(col(me()),
        reader('reader_close', { seconds: 86401 })));
      await assertFails(addDoc(col(me()),
        reader('reader_close', { seconds: 1.5 })));
      await assertFails(addDoc(col(me()),
        reader('reader_close', { seconds: '30' })));
      await assertFails(addDoc(col(me()), reader('reader_scroll')));
    });

    it('DENIES reader fields on a foreground / background row', async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      await assertFails(addDoc(col(me()),
        row({ unitId: 'u2_why_it_matters' })));
      await assertFails(addDoc(col(me()),
        row({ type: 'background', seconds: 3 })));
    });

    it('DENIES another account writing reader rows', async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
      await assertFails(addDoc(col(other(), 'u1'), reader('reader_open')));
      await assertFails(addDoc(col(unblinded(), 'u1'), reader('reader_open')));
    });
  });

  it('the generic owner rule still covers other sub-collections', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
    await assertSucceeds(setDoc(doc(me(), 'users', 'u1', 'events', 'x'),
      { name: 'app_foreground' }));
  });
});

/**
 * 1020l (1020j 一 (4)) — Firestore rules for
 * users/{uid}/chat_transcripts/{turnId} (the research transcript).
 *
 *   - Only while app_config/feature_flags.researchTranscriptEnabled is
 *     literally true.
 *   - An enrolled owner (cohort phase_b / rct / pilot) or a tester may
 *     create a row with exactly the transcript fields, turnId = doc id,
 *     receivedAt = server time, schemaVersion 1, size limits.
 *   - Not before registration (no cohort, not a tester) → refused.
 *   - Nobody reads, updates or deletes a row from a client — not the
 *     elder, not another account, not a researcher role.
 *   - The generic owner rule does not open the collection.
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
  doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection,
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

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

async function setup({ switchOn = true, user = { cohort: 'rct' } } = {}) {
  await seed('app_config/feature_flags',
    { researchTranscriptEnabled: switchOn });
  if (user) await seed('users/u1', user);
}

const ref = (db, id, uid) =>
  doc(db, 'users', uid || 'u1', 'chat_transcripts', id || 't1');

function row(extra) {
  return Object.assign({
    sessionId: 's1',
    turnId: 't1',
    agentId: 'siu_yan',
    moduleId: 'siu_yan_chat',
    userText: '今日去咗飲茶。',
    replyText: '聽落幾開心喎。',
    replyStatus: 'ok',
    userSentAt: Timestamp.fromDate(new Date('2026-10-20T10:00:00Z')),
    replyShownAt: Timestamp.fromDate(new Date('2026-10-20T10:00:03Z')),
    receivedAt: serverTimestamp(),
    schemaVersion: 1,
  }, extra || {});
}

describe('chat_transcripts: create', () => {
  it('enrolled owner, switch on: allowed (both arms, rule template too)',
    async () => {
      await setup();
      await assertSucceeds(setDoc(ref(me()), row()));
      await assertSucceeds(setDoc(ref(me(), 't2'),
        row({ turnId: 't2', replyStatus: 'rule_based', replyText: '多謝你講俾我聽。' })));
    });

  it('no free text (check-in reply after the buttons): userText null ok',
    async () => {
      await setup();
      await assertSucceeds(setDoc(ref(me()), row({ userText: null })));
    });

  it('crisis short-circuit: empty reply ok', async () => {
    await setup();
    await assertSucceeds(setDoc(ref(me()),
      row({ replyText: '', replyStatus: 'short_circuited' })));
  });

  it('pilot and phase_b cohorts and testers: allowed', async () => {
    for (const user of [{ cohort: 'pilot' }, { cohort: 'phase_b' },
      { isTester: true }]) {
      await testEnv.clearFirestore();
      await setup({ user });
      await assertSucceeds(setDoc(ref(me()), row()));
    }
  });

  it('switch off, missing or not literally true: refused', async () => {
    await setup({ switchOn: false });
    await assertFails(setDoc(ref(me()), row()));
    await seed('app_config/feature_flags',
      { researchTranscriptEnabled: 'true' });
    await assertFails(setDoc(ref(me()), row()));
    await testEnv.clearFirestore();
    await seed('users/u1', { cohort: 'rct' });
    await assertFails(setDoc(ref(me()), row()));
  });

  it('not registered (no cohort, not a tester): refused', async () => {
    await setup({ user: { email: 'x@example.com' } });
    await assertFails(setDoc(ref(me()), row()));
  });

  it('another account cannot write into u1', async () => {
    await setup();
    await seed('users/u2', { cohort: 'rct' });
    await assertFails(setDoc(ref(other()), row()));
  });

  it('bad rows: refused', async () => {
    await setup();
    const bad = [
      row({ turnId: 'other' }),
      row({ extra: 1 }),
      row({ arm: 'A' }),
      row({ receivedAt: Timestamp.fromDate(new Date('2026-10-20T10:00:05Z')) }),
      row({ schemaVersion: 2 }),
      row({ sessionId: '' }),
      row({ userText: 'x'.repeat(5001) }),
      row({ replyText: 'x'.repeat(10001) }),
      row({ replyText: null }),
      row({ userSentAt: '2026-10-20' }),
    ];
    for (const r of bad) await assertFails(setDoc(ref(me()), r));
    const missing = row();
    delete missing.moduleId;
    await assertFails(setDoc(ref(me()), missing));
  });

  it('size limits are inclusive', async () => {
    await setup();
    await assertSucceeds(setDoc(ref(me()),
      row({ userText: 'x'.repeat(5000), replyText: 'y'.repeat(10000) })));
  });
});

describe('chat_transcripts: no client reads, updates or deletes', () => {
  beforeEach(async () => {
    await setup();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(ref(ctx.firestore()), Object.assign(row(),
        { receivedAt: Timestamp.now() }));
    });
  });

  it('the elder cannot read their own rows', async () => {
    await assertFails(getDoc(ref(me())));
    await assertFails(getDocs(collection(me(), 'users', 'u1',
      'chat_transcripts')));
  });

  it('other accounts and researcher roles cannot read', async () => {
    await assertFails(getDoc(ref(other())));
    await assertFails(getDoc(ref(unblinded())));
  });

  it('no update, no overwrite, no delete', async () => {
    await assertFails(updateDoc(ref(me()), { replyText: '改咗' }));
    await assertFails(setDoc(ref(me()), row()));
    await assertFails(deleteDoc(ref(me())));
  });
});

/**
 * 1020l (1020j 一 (4)) — Firestore rules for
 * users/{uid}/chat_transcripts/{turnId} (the research transcript).
 * Decision 0069: schema 2 — `role` (elder / companion) and
 * `userInput` (text / voice / button); companion rows (openers) have no
 * elder fields; schema 1 rows from older App builds still pass.
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

/** Schema 1 (App builds before the 10/21 freeze). */
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

/** Schema 2, an elder row: a typed message and every bubble after it. */
function elder(extra) {
  return Object.assign({
    sessionId: 's1',
    turnId: 't1',
    agentId: 'siu_yan',
    moduleId: 'm2_check_in',
    role: 'elder',
    userText: '同阿女去咗飲茶。',
    userInput: 'text',
    replyText: '聽落幾開心喎。\n\n今日有咩打算？',
    replyStatus: 'ok',
    userSentAt: Timestamp.fromDate(new Date('2026-10-21T01:30:00Z')),
    replyShownAt: Timestamp.fromDate(new Date('2026-10-21T01:30:03Z')),
    receivedAt: serverTimestamp(),
    schemaVersion: 2,
  }, extra || {});
}

/** Schema 2, a companion row: lines with no elder message before them. */
function companion(extra) {
  return Object.assign({
    sessionId: 's1',
    turnId: 'c1',
    agentId: 'siu_yan',
    moduleId: 'm2_check_in',
    role: 'companion',
    userText: null,
    userInput: null,
    replyText: '早晨！想問下你尋日嘅情況，幾條就得。\n\n尋日成日整體過得點？',
    replyStatus: 'fixed_reply',
    userSentAt: null,
    replyShownAt: Timestamp.fromDate(new Date('2026-10-21T01:29:00Z')),
    receivedAt: serverTimestamp(),
    schemaVersion: 2,
  }, extra || {});
}

describe('chat_transcripts: create, schema 2 (decision 0069)', () => {
  it('elder rows: typed, spoken, button, unknown input — allowed',
    async () => {
      await setup();
      await assertSucceeds(setDoc(ref(me()), elder()));
      await assertSucceeds(setDoc(ref(me(), 't2'),
        elder({ turnId: 't2', userInput: 'voice' })));
      await assertSucceeds(setDoc(ref(me(), 't3'), elder({
        turnId: 't3', userText: '好', userInput: 'button',
        replyText: '尋日有冇同人傾過偈？', replyStatus: 'fixed_reply',
      })));
      await assertSucceeds(setDoc(ref(me(), 't4'),
        elder({ turnId: 't4', userText: null, userInput: null })));
      // Rule template, nothing shown (moderate, no line), crisis message.
      await assertSucceeds(setDoc(ref(me(), 't5'),
        elder({ turnId: 't5', replyStatus: 'rule_based' })));
      await assertSucceeds(setDoc(ref(me(), 't6'),
        elder({ turnId: 't6', replyText: '', replyStatus: 'rule_based' })));
      await assertSucceeds(setDoc(ref(me(), 't7'), elder({
        turnId: 't7', replyStatus: 'short_circuited',
        replyText: '如果你而家好唔開心、好難頂，請即刻打以下電話，有人會聽你講：\n'
          + '緊急服務 999\n〔打開緊急求助頁〕',
      })));
    });

  it('companion rows (openers, shown again): allowed', async () => {
    await setup();
    await assertSucceeds(setDoc(ref(me(), 'c1'), companion()));
    await assertSucceeds(setDoc(ref(me(), 'c2'),
      companion({ turnId: 'c2', replyStatus: 'shown_again' })));
    await assertSucceeds(setDoc(ref(me(), 'c3'),
      companion({ turnId: 'c3', replyStatus: 'rule_based' })));
  });

  it('switch off or not registered: refused (schema 2 too)', async () => {
    await setup({ switchOn: false });
    await assertFails(setDoc(ref(me()), elder()));
    await assertFails(setDoc(ref(me(), 'c1'), companion()));
    await testEnv.clearFirestore();
    await setup({ user: { email: 'x@example.com' } });
    await assertFails(setDoc(ref(me()), elder()));
    await assertFails(setDoc(ref(me(), 'c1'), companion()));
  });

  it('another account cannot write a companion row into u1', async () => {
    await setup();
    await seed('users/u2', { cohort: 'rct' });
    await assertFails(setDoc(ref(other(), 'c1'), companion()));
  });

  it('bad schema 2 rows: refused', async () => {
    await setup();
    const bad = [
      elder({ role: 'researcher' }),
      elder({ role: null }),
      elder({ userInput: 'typed' }),
      elder({ userSentAt: null }),
      elder({ schemaVersion: 1 }),
      elder({ schemaVersion: 3 }),
      elder({ arm: 'B' }),
      elder({ turnId: 'other' }),
      elder({ userText: 'x'.repeat(5001) }),
      elder({ replyText: 'x'.repeat(10001) }),
      elder({ replyStatus: 'x'.repeat(33) }),
      elder({ receivedAt: Timestamp.fromDate(new Date('2026-10-21T01:30:05Z')) }),
    ];
    for (const r of bad) await assertFails(setDoc(ref(me()), r));
    const badCompanion = [
      companion({ turnId: 'other' }),
      companion({ userText: '好' }),
      companion({ userInput: 'button' }),
      companion({ userSentAt: Timestamp.fromDate(new Date('2026-10-21T01:29:00Z')) }),
      companion({ replyText: '' }),
      companion({ replyText: 'x'.repeat(10001) }),
      companion({ schemaVersion: 1 }),
    ];
    for (const r of badCompanion) await assertFails(setDoc(ref(me(), 'c1'), r));
    // Schema 1 shape with schema 2 fields, and the reverse.
    const v1Plus = row({ role: 'elder', userInput: 'text' });
    await assertFails(setDoc(ref(me()), v1Plus));
    const v2Less = elder();
    delete v2Less.userInput;
    await assertFails(setDoc(ref(me()), v2Less));
    const v2NoRole = elder();
    delete v2NoRole.role;
    await assertFails(setDoc(ref(me()), v2NoRole));
  });

  it('size limits are inclusive (schema 2)', async () => {
    await setup();
    await assertSucceeds(setDoc(ref(me()),
      elder({ userText: 'x'.repeat(5000), replyText: 'y'.repeat(10000) })));
    await assertSucceeds(setDoc(ref(me(), 'c1'),
      companion({ replyText: 'y'.repeat(10000) })));
  });

  it('no update, overwrite, delete or read of schema 2 rows', async () => {
    await setup();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(ref(ctx.firestore(), 'c1'),
        Object.assign(companion(), { receivedAt: Timestamp.now() }));
    });
    await assertFails(getDoc(ref(me(), 'c1')));
    await assertFails(getDoc(ref(unblinded(), 'c1')));
    await assertFails(updateDoc(ref(me(), 'c1'), { replyText: '改咗' }));
    await assertFails(setDoc(ref(me(), 'c1'), companion()));
    await assertFails(deleteDoc(ref(me(), 'c1')));
  });
});

describe('chat_transcripts: create, schema 1 (older App builds)', () => {
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

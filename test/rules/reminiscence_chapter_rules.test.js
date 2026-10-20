/**
 * 1020d §6 — 小篇章 rules, users/{uid}/reminiscence_chapters/week_{N}:
 * the owner reads and writes only the client fields (weekIndex, source,
 * status → 'requested' (hybrid, new requestId) / 'ready' (rule),
 * requestId, requestedAt, input, ruleText, version (rule only),
 * editedText, editRatio, savedAt); the server fields (finalText, flags,
 * generatedAt, deletedSentences, failReason, the hybrid version, status
 * 'generating' / 'failed') and the runs/ archive are never
 * client-writable.  reminiscence_v2 and reminiscence_chapter_ratings stay
 * under the generic owner rule.
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
  doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp,
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

const me = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const ch = (db, week, uid) => doc(db, 'users', uid || 'u1',
  'reminiscence_chapters', `week_${week || 1}`);

const INPUT = {
  themeZh: '童年同屋企',
  items: [{ questionIndex: 1, question: '講下你細個住嘅地方，係點樣嘅？',
    answer: '細個住喺鄉下', skipped: false,
    followups: [{ q: '同邊個住？', a: '同阿嫲' }], reply: '同阿嫲住。' }],
  extras: [],
};

const hybridRequest = (extra) => Object.assign({
  weekIndex: 1,
  source: 'hybrid',
  status: 'requested',
  requestId: 'req-1',
  requestedAt: serverTimestamp(),
  input: INPUT,
}, extra || {});

const ruleChapter = (extra) => Object.assign({
  weekIndex: 1,
  source: 'rule',
  status: 'ready',
  requestId: 'rule-1',
  requestedAt: serverTimestamp(),
  input: INPUT,
  ruleText: '細個住嘅地方\n細個住喺鄉下',
  version: 1,
}, extra || {});

async function seed(data, week) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(ch(ctx.firestore(), week), data);
  });
}

// As the server leaves it after a generation.
const readyHybrid = () => Object.assign(hybridRequest({ requestedAt: new Date() }), {
  status: 'ready', finalText: '我細個住喺鄉下。', version: 1,
  generatedAt: new Date(), flags: [], deletedSentences: [],
});

describe('1020d reminiscence_chapters rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  it('owner creates a hybrid request and reads it back', async () => {
    await assertSucceeds(setDoc(ch(me()), hybridRequest()));
    await assertSucceeds(getDoc(ch(me())));
  });

  it('owner creates a rule-arm chapter (ready, own text, version)', async () => {
    await assertSucceeds(setDoc(ch(me()), ruleChapter()));
    // rule needs status ready, ruleText and an int version ≥ 1
    await testEnv.clearFirestore();
    await assertFails(setDoc(ch(me()), ruleChapter({ status: 'requested' })));
    await assertFails(setDoc(ch(me()), ruleChapter({ version: 0 })));
    const noText = ruleChapter();
    delete noText.ruleText;
    await assertFails(setDoc(ch(me()), noText));
  });

  it('another participant can neither read nor write it', async () => {
    await seed(readyHybrid());
    await assertFails(getDoc(ch(other(), 1, 'u1')));
    await assertFails(setDoc(ch(other(), 2, 'u1'), hybridRequest({ weekIndex: 2 })));
    await assertFails(updateDoc(ch(other(), 1, 'u1'), { editedText: 'x' }));
  });

  it('doc id must be week_{weekIndex}', async () => {
    await assertFails(setDoc(ch(me(), 2), hybridRequest()));
    await assertFails(setDoc(doc(me(), 'users', 'u1', 'reminiscence_chapters',
      'chapter_1'), hybridRequest()));
    await assertFails(setDoc(ch(me()), hybridRequest({ weekIndex: '1' })));
    await assertSucceeds(setDoc(ch(me(), 3), hybridRequest({ weekIndex: 3 })));
  });

  it('a hybrid request may not carry a status other than requested, a version or ruleText', async () => {
    for (const status of ['ready', 'generating', 'failed']) {
      await assertFails(setDoc(ch(me()), hybridRequest({ status })));
    }
    await assertFails(setDoc(ch(me()), hybridRequest({ version: 1 })));
    await assertFails(setDoc(ch(me()), hybridRequest({ ruleText: 'x' })));
    const noId = hybridRequest();
    delete noId.requestId;
    await assertFails(setDoc(ch(me()), noId));
    await assertFails(setDoc(ch(me()), hybridRequest({ requestId: '' })));
    await assertFails(setDoc(ch(me()), hybridRequest({ requestId: 'a/b' })));
    await assertFails(setDoc(ch(me()), hybridRequest({ source: 'llm' })));
  });

  it('server fields are never client-writable (create)', async () => {
    for (const extra of [
      { finalText: 'x' }, { rounds: [] }, { flags: [] },
      { generatedAt: serverTimestamp() }, { deletedSentences: [] },
      { failReason: 'x' },
    ]) {
      await assertFails(setDoc(ch(me()), hybridRequest(extra)));
      await assertFails(setDoc(ch(me()), ruleChapter(extra)));
    }
  });

  it('server fields are never client-writable (update)', async () => {
    await seed(readyHybrid());
    for (const patch of [
      { finalText: 'edited by hand' }, { rounds: [] }, { flags: ['无出处'] },
      { generatedAt: serverTimestamp() }, { deletedSentences: ['一句。'] },
      { failReason: 'x' }, { version: 9 },
      { status: 'generating' }, { status: 'failed' },
    ]) {
      await assertFails(updateDoc(ch(me()), patch));
    }
    // A hybrid doc that failed or is generating cannot be set ready.
    await seed(Object.assign(hybridRequest({ requestedAt: new Date() }),
      { status: 'failed', failReason: 'llm_error' }));
    await assertFails(updateDoc(ch(me()), { status: 'ready' }));
    await assertFails(updateDoc(ch(me()), { status: 'ready',
      finalText: 'x' }));
    await seed(Object.assign(hybridRequest({ requestedAt: new Date() }),
      { status: 'generating' }));
    await assertFails(updateDoc(ch(me()), { status: 'ready' }));
    await assertFails(updateDoc(ch(me()), { status: 'failed' }));
  });

  it('owner saves an edit (editedText, editRatio, savedAt)', async () => {
    await seed(readyHybrid());
    await assertSucceeds(updateDoc(ch(me()), {
      editedText: '我細個住喺鄉下，同阿嫲住。', editRatio: 0.2,
      savedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ch(me()), { editRatio: 'a lot' }));
    await assertFails(updateDoc(ch(me()), { editedText: 3 }));
  });

  it('re-request: status requested with a NEW requestId', async () => {
    await seed(readyHybrid());
    await assertFails(updateDoc(ch(me()), { status: 'requested' }),
      'same requestId');
    await assertFails(updateDoc(ch(me()), { status: 'requested',
      requestId: 'req-1' }));
    await assertSucceeds(updateDoc(ch(me()), { status: 'requested',
      requestId: 'req-2', requestedAt: serverTimestamp(),
      input: Object.assign({}, INPUT, { extras: [{ text: '再講多啲', reply: null }] }),
    }));
  });

  it('re-request also from failed or while generating', async () => {
    await seed(Object.assign(hybridRequest({ requestedAt: new Date() }),
      { status: 'failed', failReason: 'llm_error' }));
    await assertSucceeds(updateDoc(ch(me()), { status: 'requested',
      requestId: 'req-2' }));
    await seed(Object.assign(hybridRequest({ requestedAt: new Date() }),
      { status: 'generating' }));
    await assertSucceeds(updateDoc(ch(me()), { status: 'requested',
      requestId: 'req-3' }));
  });

  it('a new requestId only together with status requested', async () => {
    await seed(Object.assign(hybridRequest({ requestedAt: new Date() }),
      { status: 'generating' }));
    await assertFails(updateDoc(ch(me()), { requestId: 'sneaky' }));
  });

  it('a full overwrite that drops server fields is refused', async () => {
    await seed(readyHybrid());
    await assertFails(setDoc(ch(me()), hybridRequest({ requestId: 'req-2' })));
    // merge-set of client fields is fine
    await assertSucceeds(setDoc(ch(me()), { status: 'requested',
      requestId: 'req-2' }, { merge: true }));
  });

  it('rule-arm chapter: regenerate with a new text and version', async () => {
    await seed(ruleChapter({ requestedAt: new Date() }));
    await assertSucceeds(updateDoc(ch(me()), { ruleText: '新版', version: 2 }));
    await assertFails(updateDoc(ch(me()), { status: 'requested',
      requestId: 'x' }), 'rule status stays ready');
    await assertFails(updateDoc(ch(me()), { finalText: 'x' }));
    await assertSucceeds(updateDoc(ch(me()), { editedText: 'x', editRatio: 1,
      savedAt: serverTimestamp() }));
  });

  it('no client deletes', async () => {
    await seed(readyHybrid());
    await assertFails(deleteDoc(ch(me())));
  });

  it('the runs/ archive is server only (no read, no write)', async () => {
    await seed(readyHybrid());
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', 'u1', 'reminiscence_chapters',
        'week_1', 'runs', 'req-1'), { state: 'ready', rounds: [] });
    });
    const run = doc(me(), 'users', 'u1', 'reminiscence_chapters', 'week_1',
      'runs', 'req-1');
    await assertFails(getDoc(run));
    await assertFails(setDoc(run, { state: 'ready' }));
    await assertFails(deleteDoc(run));
    await assertFails(setDoc(doc(me(), 'users', 'u1', 'reminiscence_chapters',
      'week_1', 'runs', 'req-9'), { state: 'ready' }));
  });

  it('enrolment gate on: an unenrolled non-tester cannot request', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'app_config', 'feature_flags'),
        { enrollmentGateEnabled: true });
      await setDoc(doc(f, 'users', 'u1'), { arm: 'A' });
      await setDoc(doc(f, 'users', 'u2'), { arm: 'A', cohort: 'phase_b' });
    });
    await assertFails(setDoc(ch(me()), hybridRequest()));
    await assertSucceeds(setDoc(ch(other(), 1, 'u2'), hybridRequest()));
  });

  it('reminiscence_v2 and reminiscence_chapter_ratings: owner read/write ' +
      '(generic rule), nobody else', async () => {
    const v2 = (db, uid) => doc(db, 'users', uid || 'u1', 'reminiscence_v2',
      'week_1');
    const msg = (db, uid) => doc(db, 'users', uid || 'u1', 'reminiscence_v2',
      'week_1', 'messages', 'm1');
    const rating = (db, uid) => doc(db, 'users', uid || 'u1',
      'reminiscence_chapter_ratings', 'week_1_v1');
    await assertSucceeds(setDoc(v2(me()), { weekIndex: 1, currentQuestion: 3 }));
    await assertSucceeds(getDoc(v2(me())));
    await assertSucceeds(setDoc(msg(me()), { role: 'user', text: '細個住喺鄉下' }));
    await assertSucceeds(getDoc(msg(me())));
    // The rating carries studyWeek: allowed here (the server-only week
    // stamps apply to brief_pr / weekly_pr / pgic / the probe only).
    await assertSucceeds(setDoc(rating(me()), { weekIndex: 1, studyWeek: 1,
      source: 'hybrid', scores: { q1: 6, q2: 7, q3: null }, ratedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(rating(me())));
    await assertSucceeds(updateDoc(rating(me()), { 'scores.q3': 5 }));
    await assertFails(getDoc(v2(other(), 'u1')));
    await assertFails(getDoc(rating(other(), 'u1')));
    await assertFails(setDoc(rating(other(), 'u1'), { weekIndex: 1 }));
  });
});

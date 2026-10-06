/**
 * Firestore security-rules tests for the C04 model log (llm_calls).
 * Only Cloud Functions write it; no client may read or write, the
 * participant's own uid included.
 *
 * Run inside the emulator (see README.md).
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, getDocs, deleteDoc, addDoc, collection,
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
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'llm_calls', 'c1'), {
      uid: 'u1', call_type: 'chat', model_returned: 'deepseek-chat',
    });
  });
});

describe('llm_calls rules', () => {
  it('the participant cannot read their own rows', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(getDoc(doc(db, 'llm_calls', 'c1')));
    await assertFails(getDocs(collection(db, 'llm_calls')));
  });

  it('no client can create, overwrite or delete rows', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(addDoc(collection(db, 'llm_calls'),
        { uid: 'u1', call_type: 'chat' }));
    await assertFails(setDoc(doc(db, 'llm_calls', 'c1'), { uid: 'u1' }));
    await assertFails(deleteDoc(doc(db, 'llm_calls', 'c1')));
  });

  it('unauthenticated clients are denied too', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'llm_calls', 'c1')));
  });
});

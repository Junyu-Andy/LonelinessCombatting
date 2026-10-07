/**
 * Firestore security-rules tests for app_config/* (T20 adds
 * app_config/usage_copy).  Signed-in clients read; no client writes;
 * signed-out clients cannot read.
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
const {doc, setDoc, getDoc, updateDoc, deleteDoc} =
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
    await setDoc(doc(ctx.firestore(), 'app_config', 'usage_copy'), {
      siu_yan_tile_subtitle_zh: '【占位】',
    });
  });
});

describe('app_config/usage_copy rules', () => {
  it('a signed-in participant can read it', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(getDoc(doc(db, 'app_config', 'usage_copy')));
  });

  it('no client can create, change or delete it', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    const ref = doc(db, 'app_config', 'usage_copy');
    await assertFails(setDoc(ref, {siu_yan_tile_subtitle_zh: 'x'}));
    await assertFails(updateDoc(ref, {siu_yan_tile_subtitle_zh: 'x'}));
    await assertFails(deleteDoc(ref));
    await assertFails(setDoc(doc(db, 'app_config', 'new_doc'), {a: 1}));
  });

  it('signed-out clients cannot read it', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'app_config', 'usage_copy')));
  });
});

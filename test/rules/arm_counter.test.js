/**
 * Firestore security-rules tests for `meta/arm_counter` (the stratified RCT
 * arm-balance counter). Guards the invariant enforced in firestore.rules:
 * a valid write increments exactly ONE cell's aCount or bCount by exactly 1,
 * leaves the other three cells unchanged, and never decreases a count.
 *
 * The first two "allow" cases are the regression tests for the bare map-key
 * bug ({aCount: 0} vs {'aCount': 0}) that could silently DENY the first-ever
 * write and the first write into a cell.
 *
 * Run inside the emulator:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd test/rules && npm install && npm test"
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, serverTimestamp } = require('firebase/firestore');

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

const ref = (db) => doc(db, 'meta', 'arm_counter');

async function seed(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(ref(ctx.firestore()), data);
  });
}

const authed = () => testEnv.authenticatedContext('u1').firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

describe('meta/arm_counter security rules', () => {
  it('denies unauthenticated writes', async () => {
    await assertFails(
      setDoc(ref(anon()), {
        cell_0: { aCount: 1, bCount: 0 },
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('ALLOWS the first-ever write when the counter is empty '
    + '(regression: bare-key bug denied this)', async () => {
    await assertSucceeds(
      setDoc(ref(authed()), {
        cell_0: { aCount: 1, bCount: 0 },
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('ALLOWS the first write into a previously-empty cell', async () => {
    await seed({ cell_0: { aCount: 1, bCount: 0 } });
    await assertSucceeds(
      setDoc(
        ref(authed()),
        { cell_1: { aCount: 1, bCount: 0 }, updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });

  it('ALLOWS a single valid +1 increment in one cell', async () => {
    await seed({ cell_0: { aCount: 1, bCount: 0 } });
    await assertSucceeds(
      setDoc(
        ref(authed()),
        { cell_0: { aCount: 2, bCount: 0 }, updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });

  it('DENIES incrementing two cells at once', async () => {
    await seed({
      cell_0: { aCount: 1, bCount: 0 },
      cell_1: { aCount: 0, bCount: 0 },
    });
    await assertFails(
      setDoc(
        ref(authed()),
        {
          cell_0: { aCount: 2, bCount: 0 },
          cell_1: { aCount: 1, bCount: 0 },
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      ),
    );
  });

  it('DENIES a count decreasing', async () => {
    await seed({ cell_0: { aCount: 3, bCount: 2 } });
    await assertFails(
      setDoc(
        ref(authed()),
        { cell_0: { aCount: 2, bCount: 2 }, updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });

  it('DENIES an increment larger than +1', async () => {
    await seed({ cell_0: { aCount: 1, bCount: 0 } });
    await assertFails(
      setDoc(
        ref(authed()),
        { cell_0: { aCount: 3, bCount: 0 }, updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });
});

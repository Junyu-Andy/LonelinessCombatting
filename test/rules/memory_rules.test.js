/**
 * Firestore security-rules tests for memory v1 (users/{uid}/mem_*).
 * The owner may read and delete memory items and confirm a sensitive
 * fact; nobody may create or edit memory content from a client, and the
 * injection / extraction logs are server-only.
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
  doc, setDoc, getDoc, updateDoc, deleteDoc, addDoc, collection,
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

const owner = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();

async function seed(pathSegs, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), ...pathSegs), data);
  });
}

const FACT = ['users', 'u1', 'mem_facts', 'f1'];

describe('memory v1 rules', () => {
  it('owner can read and delete memory items', async () => {
    for (const col of ['mem_facts', 'mem_summaries', 'mem_followups']) {
      await seed(['users', 'u1', col, 'x'], { value: 'v', status: 'active' });
      const ref = doc(owner(), 'users', 'u1', col, 'x');
      await assertSucceeds(getDoc(ref));
      await assertSucceeds(deleteDoc(ref));
    }
  });

  it('owner cannot create memory (no fabricated memories)', async () => {
    for (const col of ['mem_facts', 'mem_summaries', 'mem_followups']) {
      await assertFails(
        addDoc(collection(owner(), 'users', 'u1', col), { value: 'fake' }),
      );
    }
  });

  it('owner cannot edit memory content', async () => {
    await seed(FACT, { value: '陳太', status: 'active' });
    await assertFails(updateDoc(doc(owner(), ...FACT), { value: '何太' }));
  });

  it('owner can confirm a pending sensitive fact, and only that', async () => {
    await seed(FACT, { value: '膝頭痛', status: 'pending_confirmation' });
    await assertFails(updateDoc(doc(owner(), ...FACT), {
      status: 'active', value: 'changed',
    }));
    await assertSucceeds(updateDoc(doc(owner(), ...FACT), { status: 'active' }));
  });

  it('owner cannot set or change layer / sourceAgent (T31)', async () => {
    await seed(FACT, {
      value: '膝頭痛', status: 'pending_confirmation',
      layer: 'private', sourceAgent: 'siu_yan',
    });
    await assertFails(updateDoc(doc(owner(), ...FACT), { layer: 'shared' }));
    await assertFails(updateDoc(doc(owner(), ...FACT), {
      status: 'active', layer: 'shared',
    }));
    await assertFails(updateDoc(doc(owner(), ...FACT), {
      sourceAgent: 'tung_tung',
    }));
    for (const col of ['mem_summaries', 'mem_followups']) {
      await seed(['users', 'u1', col, 'y'], { layer: 'private' });
      await assertFails(updateDoc(doc(owner(), 'users', 'u1', col, 'y'), {
        layer: 'shared',
      }));
    }
  });

  it('owner cannot re-activate a superseded fact', async () => {
    await seed(FACT, { value: '陳太', status: 'superseded' });
    await assertFails(updateDoc(doc(owner(), ...FACT), { status: 'active' }));
  });

  it('injection and extraction logs are server-only', async () => {
    for (const col of ['mem_injections', 'mem_extractions']) {
      await seed(['users', 'u1', col, 'x'], { a: 1 });
      await assertFails(getDoc(doc(owner(), 'users', 'u1', col, 'x')));
      await assertFails(deleteDoc(doc(owner(), 'users', 'u1', col, 'x')));
      await assertFails(setDoc(doc(owner(), 'users', 'u1', col, 'y'), {}));
    }
  });

  it('other users see nothing', async () => {
    await seed(FACT, { value: '陳太', status: 'active' });
    await assertFails(getDoc(doc(other(), ...FACT)));
    await assertFails(deleteDoc(doc(other(), ...FACT)));
  });

  it('the kill-switch config is not client-readable', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'meta', 'memory_config'),
        { enabled: true });
    });
    await assertFails(getDoc(doc(owner(), 'meta', 'memory_config')));
    await assertFails(setDoc(doc(owner(), 'meta', 'memory_config'),
      { enabled: false }));
  });

  it('non-memory subcollections keep owner read/write', async () => {
    const ref = doc(owner(), 'users', 'u1', 'agent_contexts', 'siu_yan');
    await assertSucceeds(setDoc(ref, { shortTermBuffer: [] }));
    await assertSucceeds(getDoc(ref));
  });
});

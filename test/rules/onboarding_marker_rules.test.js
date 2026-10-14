/**
 * T37 (registry C01, C19) — Firestore rules for the "onboarding finished"
 * marker `users/{uid}.onboardingCompletedAt`.
 *
 *   - The App writes it when the participant taps 「完成」, so the owner
 *     may set it on create and on update like any other profile field,
 *     also while the T21 enrolment gate is on (the profile doc is not
 *     research data; the gate only closes the sub-collections).
 *   - It must not open a door to the server-only assignment fields.
 *   - The researcher's pairing in enrollments/{uid} stays server-only:
 *     a pairing change on the onboarding slide can never touch it.
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
const { doc, setDoc, updateDoc, getDoc } = require('firebase/firestore');

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
const AT = '2026-10-14T03:00:00.000Z';

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

describe('T37: users/{uid}.onboardingCompletedAt', () => {
  it('ALLOWS the owner to create the profile with the marker', async () => {
    await assertSucceeds(setDoc(doc(owner(), 'users', 'u1'),
      { uid: 'u1', ahJanAhBakVariant: 'feminine', onboardingCompletedAt: AT }));
  });

  it('ALLOWS the owner to set the marker on an existing profile (merge, as the App does)',
    async () => {
      await seed('users/u1', { uid: 'u1', hasCompletedIntake: true });
      await assertSucceeds(setDoc(doc(owner(), 'users', 'u1'), {
        ahJanAhBakVariant: 'masculine',
        interests: ['yum_cha'],
        onboardingCompletedAt: AT,
      }, { merge: true }));
      const snap = await getDoc(doc(owner(), 'users', 'u1'));
      if (snap.get('onboardingCompletedAt') !== AT) {
        throw new Error('marker not written');
      }
    });

  it('ALLOWS the marker after registration, with the gate on (register-first order)',
    async () => {
      await seed('app_config/feature_flags', { enrollmentGateEnabled: true });
      // What enrollParticipant wrote: arm, cohort, the researcher's pairing.
      await seed('users/u1', {
        uid: 'u1', arm: 'B', armAssignmentMode: 'randomise',
        cohort: 'phase_b', ahJanAhBakVariant: 'masculine',
      });
      // 「完成」 with the pairing kept …
      await assertSucceeds(updateDoc(doc(owner(), 'users', 'u1'),
        { onboardingCompletedAt: AT, interests: [] }));
      // … or changed to the other companion.
      await assertSucceeds(updateDoc(doc(owner(), 'users', 'u1'),
        { ahJanAhBakVariant: 'feminine' }));
    });

  it('ALLOWS the marker for an unregistered account with the gate on (onboarding-first order)',
    async () => {
      await seed('app_config/feature_flags', { enrollmentGateEnabled: true });
      await seed('users/u1', { uid: 'u1' });
      await assertSucceeds(updateDoc(doc(owner(), 'users', 'u1'),
        { ahJanAhBakVariant: 'feminine', onboardingCompletedAt: AT }));
    });

  it('DENIES smuggling an assignment field in with the marker', async () => {
    await seed('users/u1', { uid: 'u1' });
    await assertFails(updateDoc(doc(owner(), 'users', 'u1'),
      { onboardingCompletedAt: AT, cohort: 'phase_b' }));
    await assertFails(updateDoc(doc(owner(), 'users', 'u1'),
      { onboardingCompletedAt: AT, arm: 'A' }));
    await assertFails(setDoc(doc(owner(), 'users', 'u1'),
      { uid: 'u1', onboardingCompletedAt: AT, w0Date: '2026-10-14' }));
  });

  it('DENIES the owner touching the registration pairing in enrollments/{uid}',
    async () => {
      await seed('enrollments/u1', { uid: 'u1', companionVariant: 'masculine' });
      await assertFails(updateDoc(doc(owner(), 'enrollments', 'u1'),
        { companionVariant: 'feminine' }));
      await assertFails(setDoc(doc(owner(), 'enrollments', 'u1'),
        { companionVariant: 'feminine' }, { merge: true }));
      await assertFails(getDoc(doc(owner(), 'enrollments', 'u1')));
    });
});

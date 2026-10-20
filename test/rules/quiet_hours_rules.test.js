/**
 * 1020o 第三节 (decision 0066) — Firestore rules for the elder's own
 * 安靜時段 (自己 → 我的設定, 「由」 / 「到」, both arms).
 *
 *   - users/{uid}.quietHoursStart / quietHoursEnd: the owner may set each
 *     to an allowed value only (【待 Junyu 定】 start 20:00–23:00, end
 *     06:00–08:00, half-hour steps; the same lists as
 *     functions/quiet_hours.js and lib/core/notifications/
 *     quiet_hours_range.dart).  Out-of-range, off-step, malformed or
 *     non-string values and removing a stored value are refused.
 *   - Ordinary profile saves (which leave both fields out) pass, also on a
 *     profile holding a value that is no longer allowed; the checks on
 *     arm / isTester / intakeGateUnlockedAt still hold together with it.
 *   - usage_events: quiet_hours_changed with exactly field (start / end),
 *     from ("HH:mm") and to (an allowed value for that field).
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
  doc, collection, setDoc, addDoc, updateDoc, deleteField, getDoc,
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

const owner = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const profile = (db) => doc(db, 'users', 'u1');

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

const STARTS = ['20:00', '20:30', '21:00', '21:30', '22:00', '22:30', '23:00'];
const ENDS = ['06:00', '06:30', '07:00', '07:30', '08:00'];

const enrolled = (arm, extra) => Object.assign({
  uid: 'u1', displayName: '陳婆婆', consent: { functionalData: true },
  arm, cohort: 'rct', armAssignmentMode: 'randomise', w0Date: '2026-10-19',
}, extra || {});

describe('1020o: users/{uid}.quietHoursStart / quietHoursEnd', () => {
  for (const arm of ['A', 'B']) {
    it(`ALLOWS every offered 「由」 and 「到」 (arm ${arm})`, async () => {
      await seed('users/u1', enrolled(arm));
      for (const v of STARTS) {
        await assertSucceeds(setDoc(profile(owner()),
          { quietHoursStart: v }, { merge: true }));
      }
      for (const v of ENDS) {
        await assertSucceeds(setDoc(profile(owner()),
          { quietHoursEnd: v }, { merge: true }));
      }
      const snap = await getDoc(profile(owner()));
      if (snap.get('quietHoursStart') !== '23:00' ||
          snap.get('quietHoursEnd') !== '08:00') {
        throw new Error('not stored as HH:mm');
      }
    });
  }

  it('REFUSES a start outside 20:00–23:00, off the half hour or malformed',
    async () => {
      await seed('users/u1', enrolled('A'));
      for (const v of ['19:30', '23:30', '00:00', '06:00', '21:15', '9pm',
        '2100', '21:00 ', '25:00', '']) {
        await assertFails(setDoc(profile(owner()),
          { quietHoursStart: v }, { merge: true }));
      }
      for (const v of [2100, true, null, { h: 21 }]) {
        await assertFails(setDoc(profile(owner()),
          { quietHoursStart: v }, { merge: true }));
      }
    });

  it('REFUSES an end outside 06:00–08:00, off the half hour or malformed',
    async () => {
      await seed('users/u1', enrolled('B'));
      for (const v of ['05:30', '08:30', '09:00', '22:00', '07:45', '7:00',
        '0600']) {
        await assertFails(setDoc(profile(owner()),
          { quietHoursEnd: v }, { merge: true }));
      }
      await assertFails(setDoc(profile(owner()),
        { quietHoursEnd: 600 }, { merge: true }));
    });

  it('REFUSES removing a stored value (the App never does)', async () => {
    await seed('users/u1', enrolled('A',
      { quietHoursStart: '21:00', quietHoursEnd: '07:00' }));
    await assertFails(updateDoc(profile(owner()),
      { quietHoursStart: deleteField() }));
    await assertFails(updateDoc(profile(owner()),
      { quietHoursEnd: deleteField() }));
  });

  it('ALLOWS an ordinary profile save that leaves both out — even when the ' +
    'stored value is no longer in the range', async () => {
    await seed('users/u1', enrolled('B',
      { quietHoursStart: '19:00', quietHoursEnd: '09:00' }));
    await assertSucceeds(setDoc(profile(owner()), {
      uid: 'u1', displayName: '陳婆婆（改）', memory_enabled: false,
      arm: 'B', consent: { functionalData: true },
    }, { merge: true }));
    // Re-sending the stored value unchanged is no change either.
    await assertSucceeds(setDoc(profile(owner()),
      { quietHoursStart: '19:00' }, { merge: true }));
    // But a new out-of-range value is refused.
    await assertFails(setDoc(profile(owner()),
      { quietHoursStart: '19:30' }, { merge: true }));
  });

  it('ALLOWS a profile created with allowed values; REFUSES other values',
    async () => {
      await assertSucceeds(setDoc(profile(owner()), {
        uid: 'u1', displayName: 'x',
        quietHoursStart: '22:00', quietHoursEnd: '08:00',
      }));
      await testEnv.clearFirestore();
      await assertFails(setDoc(profile(owner()), {
        uid: 'u1', displayName: 'x', quietHoursStart: '18:00',
      }));
      await assertFails(setDoc(profile(owner()), {
        uid: 'u1', displayName: 'x', quietHoursEnd: '10:00',
      }));
    });

  it('REFUSES another account; the other profile checks still hold',
    async () => {
      await seed('users/u1', enrolled('A'));
      await assertFails(setDoc(profile(other()),
        { quietHoursStart: '21:00' }, { merge: true }));
      await assertFails(setDoc(profile(owner()),
        { quietHoursStart: '21:00', arm: 'B' }, { merge: true }));
      await assertFails(setDoc(profile(owner()),
        { quietHoursStart: '21:00', isTester: true }, { merge: true }));
    });
});

const usage = (db) => collection(db, 'users', 'u1', 'usage_events');

function row(extra) {
  return Object.assign({
    type: 'quiet_hours_changed',
    clientAt: Timestamp.fromDate(new Date('2026-10-20T14:39:58Z')),
    receivedAt: serverTimestamp(),
    appVersion: '1.0.0',
    buildNumber: '3',
    platform: 'android',
    schemaVersion: 1,
    field: 'start',
    from: '22:00',
    to: '20:30',
  }, extra || {});
}

describe('1020o: usage_events quiet_hours_changed', () => {
  for (const arm of ['A', 'B']) {
    it(`ALLOWS a start or end change from an enrolled account (arm ${arm})`,
      async () => {
        await seed('users/u1', enrolled(arm));
        await assertSucceeds(addDoc(usage(owner()), row()));
        await assertSucceeds(addDoc(usage(owner()),
          row({ field: 'end', from: '08:00', to: '06:00' })));
      });
  }

  it('REFUSES a missing, extra or malformed field', async () => {
    await seed('users/u1', enrolled('A'));
    const noFrom = row();
    delete noFrom.from;
    await assertFails(addDoc(usage(owner()), noFrom));
    await assertFails(addDoc(usage(owner()), row({ note: '瞓唔著' })));
    await assertFails(addDoc(usage(owner()), row({ field: 'both' })));
    await assertFails(addDoc(usage(owner()), row({ from: '10pm' })));
    await assertFails(addDoc(usage(owner()), row({ from: 2200 })));
    // `to` must be an allowed value for that field.
    await assertFails(addDoc(usage(owner()), row({ to: '19:00' })));
    await assertFails(addDoc(usage(owner()), row({ to: '06:00' })));
    await assertFails(addDoc(usage(owner()),
      row({ field: 'end', from: '08:00', to: '22:00' })));
  });

  it('REFUSES before registration and from another account', async () => {
    await seed('users/u1', { uid: 'u1', displayName: 'x', arm: 'A' });
    await assertFails(addDoc(usage(owner()), row()));
    await seed('users/u1', enrolled('A'));
    await assertFails(addDoc(usage(other()), row()));
  });
});

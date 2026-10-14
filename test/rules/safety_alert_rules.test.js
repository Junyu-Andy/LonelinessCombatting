/**
 * T34 — safety alert rules:
 *   safety_events: the server-only sources `questionnaire` /
 *     `assessor_entry` and the `alwaysAlert` flag are refused from any
 *     client; `crisisPageShown` is accepted as a boolean (both arms).
 *   pi_alerts: readable by `unblinded` only; no client writes (the
 *     acknowledgement goes through the acknowledgeAlert callable).
 *   alert_audit_log, meta/alert_config: closed to every client.
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
  doc, getDoc, getDocs, addDoc, collection, updateDoc, deleteDoc, setDoc,
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

const participant = () => testEnv.authenticatedContext('alice').firestore();
const unblinded = () => testEnv.authenticatedContext('junyu',
    {role: 'unblinded'}).firestore();
const blinded = () => testEnv.authenticatedContext('assessor',
    {role: 'blinded'}).firestore();
const legacyPi = () => testEnv.authenticatedContext('oldpi',
    {role: 'pi'}).firestore();

const event = (over) => Object.assign({
  uid: 'alice',
  source: 'user_input',
  inputPoint: 'check_in_note',
  turnId: 't1',
  textHash: 'abc',
  level: 'acute',
  tier: 'acute',
  crisisPageShown: true,
}, over);

describe('safety_events (T34)', () => {
  it('accepts crisisPageShown true / false from the participant (both arms)',
      async () => {
        const c = collection(participant(), 'safety_events');
        await assertSucceeds(addDoc(c, event({crisisPageShown: true,
          source: 'ai_output_scan'})));
        await assertSucceeds(addDoc(c, event({crisisPageShown: false,
          source: 'rule_turn', level: 'moderate',
          tier: 'moderate_interrupt'})));
        // Older builds without the field still write.
        const e = event();
        delete e.crisisPageShown;
        await assertSucceeds(addDoc(c, e));
      });

  it('rejects a non-boolean crisisPageShown', async () => {
    const c = collection(participant(), 'safety_events');
    await assertFails(addDoc(c, event({crisisPageShown: 'yes'})));
    await assertFails(addDoc(c, event({crisisPageShown: 1})));
  });

  it('rejects the server-only sources from every client', async () => {
    for (const db of [participant(), unblinded(), blinded()]) {
      const c = collection(db, 'safety_events');
      await assertFails(addDoc(c, event({source: 'questionnaire'})));
      await assertFails(addDoc(c, event({source: 'assessor_entry'})));
    }
    // The unblinded researcher cannot write one for a participant either.
    await assertFails(addDoc(collection(unblinded(), 'safety_events'),
        event({uid: 'junyu', source: 'assessor_entry', instrument: 'PHQ-9',
          item: 9, rawValue: 2})));
  });

  it('rejects alwaysAlert from a client', async () => {
    await assertFails(addDoc(collection(participant(), 'safety_events'),
        event({alwaysAlert: true})));
    await assertFails(addDoc(collection(participant(), 'safety_events'),
        event({alwaysAlert: false})));
  });
});

describe('pi_alerts (T34)', () => {
  const seed = async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pi_alerts', 'a1'), {
        uid: 'alice', researchId: 'PB-A01', level: 'acute',
        sourceGroup: 'participant_input', alertVersion: 3,
        acknowledgedAt: null, escalationPending: true,
      });
    });
  };

  it('unblinded reads the list and a single alert', async () => {
    await seed();
    await assertSucceeds(getDoc(doc(unblinded(), 'pi_alerts', 'a1')));
    await assertSucceeds(getDocs(collection(unblinded(), 'pi_alerts')));
  });

  it('blinded, participant, legacy pi and anonymous read nothing',
      async () => {
        await seed();
        for (const db of [blinded(), participant(), legacyPi(),
          testEnv.unauthenticatedContext().firestore()]) {
          await assertFails(getDoc(doc(db, 'pi_alerts', 'a1')));
          await assertFails(getDocs(collection(db, 'pi_alerts')));
        }
      });

  it('no client writes — acknowledgement is not a client update',
      async () => {
        await seed();
        for (const db of [unblinded(), blinded(), participant()]) {
          await assertFails(updateDoc(doc(db, 'pi_alerts', 'a1'),
              {acknowledgedAt: new Date(), acknowledgedBy: 'junyu'}));
          await assertFails(deleteDoc(doc(db, 'pi_alerts', 'a1')));
          await assertFails(addDoc(collection(db, 'pi_alerts'),
              {uid: 'alice', level: 'acute'}));
        }
      });
});

describe('alert_audit_log and meta/alert_config (T34)', () => {
  it('closed to every client, including unblinded', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore(); // once per context
      await setDoc(doc(admin, 'alert_audit_log', 'l1'),
          {type: 'email_sent', alertId: 'a1'});
      await setDoc(doc(admin, 'meta', 'alert_config'),
          {enabled: true, primaryEmail: 'x@y.hk'});
    });
    for (const db of [unblinded(), blinded(), participant()]) {
      await assertFails(getDoc(doc(db, 'alert_audit_log', 'l1')));
      await assertFails(addDoc(collection(db, 'alert_audit_log'),
          {type: 'acknowledged'}));
      await assertFails(getDoc(doc(db, 'meta', 'alert_config')));
      await assertFails(updateDoc(doc(db, 'meta', 'alert_config'),
          {primaryEmail: 'attacker@y.hk'}));
      await assertFails(setDoc(doc(db, 'meta', 'alert_config'),
          {enabled: false}));
    }
  });
});

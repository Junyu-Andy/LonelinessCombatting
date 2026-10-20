/**
 * tool/update_login_email.js (dev-tasks 1020j §7) on the Auth + Firestore
 * emulators with synthetic accounts.  Run from the repository root:
 *
 *   firebase emulators:exec --config test/delete_participant/firebase.json \
 *     --only auth,firestore,storage --project loneliness-pilot-dev \
 *     'NODE_PATH=functions/node_modules node test/admin_tools/update_login_email_test.js'
 *
 * Checks: the dry run changes nothing; --confirm changes the login e-mail
 * (and the App's copy), resets the password, and writes one log record
 * with only the last four characters of each address; refusals (e-mail
 * taken, unknown ID, ambiguous target, real project without --production)
 * change nothing and log nothing.
 */
'use strict';

const assert = require('assert');
const path = require('path');
const {spawnSync} = require('child_process');
const admin = require('firebase-admin');
const tool = require('../../tool/update_login_email');

if (!process.env.FIRESTORE_EMULATOR_HOST ||
  !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('run inside the Auth + Firestore emulators');
  process.exit(1);
}
admin.initializeApp({projectId: 'loneliness-pilot-dev'});
const db = admin.firestore();
const auth = admin.auth();
const SCRIPT = path.resolve(__dirname, '../../tool/update_login_email.js');

let passed = 0;
function ok(name) {
  passed++;
  console.log(`ok - ${name}`);
}

function run(args, env) {
  return spawnSync(process.execPath, [SCRIPT].concat(args),
      {env: Object.assign({}, process.env, env || {}), encoding: 'utf8'});
}

async function logRows() {
  return (await db.collection(tool.LOG_COLLECTION).get()).docs
      .map((d) => d.data());
}

async function signIn(email, password) {
  const res = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}` +
    '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=x', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true})});
  return res.ok;
}

(async () => {
  await db.recursiveDelete(db.collection('users'));
  await db.recursiveDelete(db.collection('research_ids'));
  await db.recursiveDelete(db.collection(tool.LOG_COLLECTION));
  for (const u of (await auth.listUsers()).users) await auth.deleteUser(u.uid);

  await auth.createUser({uid: 'uidElder01', email: 'chan1234@example.com',
    password: 'oldpass123'});
  await auth.createUser({uid: 'uidOther01', email: 'taken@example.com',
    password: 'otherpass1'});
  await db.doc('research_ids/RCT-001').set({uid: 'uidElder01'});
  await db.doc('users/uidElder01').set({email: 'chan1234@example.com',
    isTester: false, arm: 'A'});
  await db.doc('randomization_state/rct').set({next: 3});

  // Pure helpers.
  assert.strictEqual(tool.last4('chan1234@example.com'), '1234');
  assert.strictEqual(tool.last4('ab@x.com'), 'ab');
  const pw = tool.randomPassword();
  assert.strictEqual(pw.length, tool.PASSWORD_LENGTH);
  assert.ok([...pw].every((c) => tool.PASSWORD_CHARS.indexOf(c) >= 0));
  assert.ok(tool.parseRequest({'uid': 'uidElder01'}).error);
  assert.ok(tool.parseRequest({'uid': 'uidElder01', 'research-id': 'RCT-001',
    'reset-password': true}).error);
  assert.ok(tool.parseRequest({'research-id': 'RCT-001',
    'new-email': 'not-an-email'}).error);
  ok('helpers: last four before @, readable random password, request checks');

  // Dry run.
  let r = run(['--research-id=RCT-001', '--new-email=Wong5678@Example.com']);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(r.stdout.indexOf('chan1234@example.com  →  wong5678@example.com') >= 0,
      r.stdout);
  assert.ok(/空跑/.test(r.stdout));
  assert.strictEqual((await auth.getUser('uidElder01')).email,
      'chan1234@example.com');
  assert.deepStrictEqual(await logRows(), []);
  ok('dry run shows before → after and changes nothing');

  // Real change on the emulator.
  r = run(['--research-id=rct-001', '--new-email=wong5678@example.com',
    '--confirm']);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual((await auth.getUser('uidElder01')).email,
      'wong5678@example.com');
  assert.strictEqual((await db.doc('users/uidElder01').get()).get('email'),
      'wong5678@example.com');
  assert.ok(await signIn('wong5678@example.com', 'oldpass123'));
  let rows = await logRows();
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].status, 'done');
  assert.strictEqual(rows[0].action, 'email');
  assert.strictEqual(rows[0].researchId, 'RCT-001');
  assert.strictEqual(rows[0].oldEmailLast4, '1234');
  assert.strictEqual(rows[0].newEmailLast4, '5678');
  assert.strictEqual(rows[0].by, 'emulator');
  assert.ok(JSON.stringify(rows[0]).indexOf('@') < 0, 'no full address logged');
  ok('--confirm changes the login e-mail and the App copy, logs last four only');

  // Password reset by uid.
  r = run(['--uid=uidElder01', '--reset-password', '--confirm']);
  assert.strictEqual(r.status, 0, r.stderr);
  const m = r.stdout.match(/新密码（只显示这一次）：(\S+)/);
  assert.ok(m, r.stdout);
  assert.ok(await signIn('wong5678@example.com', m[1]));
  assert.ok(!(await signIn('wong5678@example.com', 'oldpass123')));
  rows = await logRows();
  assert.strictEqual(rows.length, 2);
  const pwRow = rows.find((x) => x.action === 'password');
  assert.strictEqual(pwRow.researchId, 'RCT-001', 'found back from the uid');
  assert.strictEqual(pwRow.passwordReset, true);
  assert.ok(JSON.stringify(pwRow).indexOf(m[1]) < 0, 'password not logged');
  ok('--reset-password sets a new password, printed once, not logged');

  // Refusals: nothing changes, nothing logged.
  const refusals = [
    [['--research-id=RCT-001', '--new-email=taken@example.com', '--confirm'],
      {}, /another account/],
    [['--research-id=RCT-404', '--new-email=x1@example.com', '--confirm'], {},
      /not found/],
    [['--research-id=RCT-001', '--new-email=x2@example.com', '--confirm',
      '--production'], {}, /emulator variables are set/],
    [['--research-id=RCT-001', '--new-email=x3@example.com', '--confirm'],
      {FIREBASE_AUTH_EMULATOR_HOST: ''}, /ambiguous/],
    [['--research-id=RCT-001', '--new-email=x4@example.com', '--confirm'],
      {FIREBASE_AUTH_EMULATOR_HOST: '', FIRESTORE_EMULATOR_HOST: '',
        GOOGLE_APPLICATION_CREDENTIALS: '/nonexistent/key.json'},
      /add --production/],
    [['--research-id=RCT-001', '--new-email=x5@example.com'],
      {FIREBASE_AUTH_EMULATOR_HOST: '', FIRESTORE_EMULATOR_HOST: '',
        GOOGLE_APPLICATION_CREDENTIALS: ''}, /GOOGLE_APPLICATION_CREDENTIALS/],
  ];
  for (const [args, env, re] of refusals) {
    r = run(args, env);
    assert.strictEqual(r.status, 2, `${args.join(' ')}: ${r.stdout}${r.stderr}`);
    assert.ok(re.test(r.stderr), r.stderr);
  }
  assert.strictEqual((await auth.getUser('uidElder01')).email,
      'wong5678@example.com');
  assert.strictEqual((await logRows()).length, 2);
  assert.strictEqual((await db.doc('randomization_state/rct').get())
      .get('next'), 3);
  ok('refusals change nothing and log nothing');

  console.log(`all ${passed} update_login_email tests passed`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

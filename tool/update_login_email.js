#!/usr/bin/env node
/**
 * tool/update_login_email.js — change a participant's login e-mail and/or
 * reset the password (dev-tasks 1020j §7, Junyu 10/20).  An operations
 * tool after the freeze: no App, Functions or rules change.
 *
 * Finds the account by research ID (research_ids/{RID}.uid) or by uid,
 * then, through the Firebase Admin SDK:
 *   --new-email=<address>   sets the Auth login e-mail (and the copy in
 *                           users/{uid}.email, which the App shows), after
 *                           checking no other account already uses it;
 *   --reset-password        sets a new random password, printed once at
 *                           the end of the real run (give it to the elder;
 *                           the phone will ask them to sign in again).
 *
 * Dry run by default: shows the account and what would change (before →
 * after).  --confirm makes the change; outside the emulator --confirm also
 * needs --production.  Every real change writes one record to
 * account_admin_log (server only — the rules give clients no access):
 * who ran it, when, which research ID / uid, what changed, and the last
 * four characters before "@" of the old and new e-mail (the whole address
 * ends in ".com" too often to tell them apart).  The record is written
 * before the change ("pending") and closed with "done" or "failed".
 *
 * Never reads randomization_sequences, randomization_state, sequence
 * versions, allocation logs or correctArm records (dev-tasks rule 6).
 *
 * Usage (repository root):
 *   export GOOGLE_APPLICATION_CREDENTIALS=<admin key outside the repo>
 *   NODE_PATH=functions/node_modules node tool/update_login_email.js \
 *       --research-id=RCT-001 --new-email=new@example.com          # dry run
 *   ... --research-id=RCT-001 --new-email=new@example.com --confirm --production
 *   ... --uid=abc123 --reset-password --confirm --production
 * Emulator: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST set,
 * --confirm alone is enough.  Guide: docs/release/update-login-email.md.
 */
'use strict';

const crypto = require('crypto');
const os = require('os');

const PROJECT = 'loneliness-pilot-dev';
const LOG_COLLECTION = 'account_admin_log';
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RESEARCH_ID = /^[A-Z][A-Z0-9-]{2,39}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
/** No 0/O, 1/l/I: easy to read out to an elder. */
const PASSWORD_CHARS = 'abcdefghjkmnpqrstuvwxyz23456789';
const PASSWORD_LENGTH = 10;

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
    else if (a.startsWith('--')) out[a.slice(2)] = true;
  }
  return out;
}

/** The last four characters before "@" (all of it when shorter). */
function last4(email) {
  if (typeof email !== 'string' || !email) return null;
  const local = email.split('@')[0];
  return local.slice(-4);
}

function randomPassword(randomBytes) {
  const bytes = (randomBytes || crypto.randomBytes)(PASSWORD_LENGTH);
  let out = '';
  for (let i = 0; i < PASSWORD_LENGTH; i++) {
    out += PASSWORD_CHARS[bytes[i] % PASSWORD_CHARS.length];
  }
  return out;
}

/**
 * Where we are and whether the run may change anything.
 * @return {{ok: boolean, reason: string, emulator: boolean,
 *     confirm: boolean}}
 */
function checkMode(env, args) {
  const fsEmu = !!env.FIRESTORE_EMULATOR_HOST;
  const authEmu = !!env.FIREBASE_AUTH_EMULATOR_HOST;
  const confirm = args.confirm === true;
  if (fsEmu !== authEmu) {
    return {ok: false, emulator: false, confirm, reason:
      'only one of FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST ' +
      'is set; refusing an ambiguous target'};
  }
  if (fsEmu) {
    if (args.production) {
      return {ok: false, emulator: true, confirm, reason:
        '--production given but the emulator variables are set; refusing'};
    }
    return {ok: true, emulator: true, confirm, reason: 'emulator'};
  }
  if (!env.GOOGLE_APPLICATION_CREDENTIALS) {
    return {ok: false, emulator: false, confirm, reason:
      'not on the emulator and GOOGLE_APPLICATION_CREDENTIALS is not set'};
  }
  if (confirm && args.production !== true) {
    return {ok: false, emulator: false, confirm, reason:
      'not on the emulator: add --production to really change the account'};
  }
  return {ok: true, emulator: false, confirm, reason:
    `REAL PROJECT ${PROJECT}`};
}

/** Validated request, or an error message. */
function parseRequest(args) {
  const rid = typeof args['research-id'] === 'string' ?
    args['research-id'].trim().toUpperCase() : null;
  const uid = typeof args.uid === 'string' ? args.uid.trim() : null;
  if (!!rid === !!uid) return {error: 'give exactly one of --research-id or --uid'};
  if (rid && !RESEARCH_ID.test(rid)) return {error: `bad research ID ${rid}`};
  if (uid && !UID.test(uid)) return {error: 'bad uid'};
  let newEmail = null;
  if (args['new-email'] !== undefined) {
    newEmail = String(args['new-email']).trim().toLowerCase();
    if (!EMAIL.test(newEmail)) return {error: `not an e-mail address: ${newEmail}`};
  }
  const resetPassword = args['reset-password'] === true;
  if (!newEmail && !resetPassword) {
    return {error: 'nothing to change: give --new-email and/or --reset-password'};
  }
  return {researchId: rid, uid, newEmail, resetPassword};
}

/**
 * @param {{db: object, auth: object}} deps
 * @return {Promise<object>} the account and the planned change
 */
async function plan(deps, req) {
  let uid = req.uid;
  let researchId = req.researchId;
  if (researchId) {
    const ridSnap = await deps.db.collection('research_ids').doc(researchId)
        .get();
    uid = ridSnap.exists ? ridSnap.get('uid') : null;
    if (!uid) return {error: `research ID ${researchId} not found`};
  } else {
    const back = await deps.db.collection('research_ids')
        .where('uid', '==', uid).limit(1).get();
    researchId = back.empty ? null : back.docs[0].id;
  }
  let user;
  try {
    user = await deps.auth.getUser(uid);
  } catch (err) {
    return {error: `no Auth account for uid ${uid}`};
  }
  const profile = await deps.db.collection('users').doc(uid).get();
  const profileEmail = profile.exists ? (profile.get('email') || null) : null;
  if (req.newEmail) {
    if (req.newEmail === (user.email || '').toLowerCase()) {
      return {error: 'the account already uses this e-mail'};
    }
    try {
      const other = await deps.auth.getUserByEmail(req.newEmail);
      if (other && other.uid !== uid) {
        return {error: 'another account already uses this e-mail'};
      }
    } catch (err) {
      if (!err || err.code !== 'auth/user-not-found') throw err;
    }
  }
  return {
    uid, researchId,
    isTester: profile.exists && profile.get('isTester') === true,
    oldEmail: user.email || null,
    newEmail: req.newEmail,
    profileEmail,
    updateProfileEmail: !!req.newEmail && profile.exists &&
      profileEmail !== null,
    resetPassword: req.resetPassword,
    lastSignIn: user.metadata && user.metadata.lastSignInTime || null,
  };
}

function describe(p) {
  const lines = [
    `账号：uid ${p.uid}${p.researchId ? `，研究编号 ${p.researchId}` : '，没有研究编号'}` +
      (p.isTester ? '（测试账号）' : ''),
    `最后登录：${p.lastSignIn || '—'}`,
  ];
  if (p.newEmail) {
    lines.push(`登录电邮：${p.oldEmail || '（没有）'}  →  ${p.newEmail}`);
    lines.push(p.updateProfileEmail ?
      `App 资料里的电邮（users/${p.uid}.email）：${p.profileEmail} → ${p.newEmail}` :
      'App 资料里没有电邮字段，不改');
  }
  if (p.resetPassword) {
    lines.push('密码：重设为新的随机密码（正式改时只显示一次）；手机上要用新密码重新登录');
  }
  return lines;
}

/**
 * Applies the plan.  Writes the log record first, then the change.
 * @return {Promise<{password: ?string}>}
 */
async function apply(deps, p, meta) {
  const logRef = deps.db.collection(LOG_COLLECTION).doc();
  const action = [p.newEmail ? 'email' : null, p.resetPassword ? 'password' :
    null].filter(Boolean).join('+');
  await logRef.set({
    tool: 'tool/update_login_email.js',
    action,
    researchId: p.researchId || null,
    uid: p.uid,
    oldEmailLast4: p.newEmail ? last4(p.oldEmail) : null,
    newEmailLast4: p.newEmail ? last4(p.newEmail) : null,
    passwordReset: p.resetPassword,
    by: meta.by,
    operator: meta.operator,
    status: 'pending',
    at: deps.serverTimestamp(),
  });
  const update = {};
  if (p.newEmail) update.email = p.newEmail;
  const password = p.resetPassword ? randomPassword(deps.randomBytes) : null;
  if (password) update.password = password;
  try {
    await deps.auth.updateUser(p.uid, update);
    if (p.updateProfileEmail) {
      await deps.db.collection('users').doc(p.uid)
          .set({email: p.newEmail}, {merge: true});
    }
  } catch (err) {
    await logRef.set({status: 'failed',
      error: String(err && (err.code || err.message) || err).slice(0, 200),
      finishedAt: deps.serverTimestamp()}, {merge: true});
    throw err;
  }
  await logRef.set({status: 'done', finishedAt: deps.serverTimestamp()},
      {merge: true});
  return {password, logId: logRef.id};
}

/** Who is running this: the key's account and the computer user. */
function whoRuns(env, fsModule) {
  let by = 'emulator';
  const key = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (key && !env.FIRESTORE_EMULATOR_HOST) {
    try {
      by = JSON.parse(fsModule.readFileSync(key, 'utf8')).client_email ||
        'unknown key';
    } catch (_) {
      by = 'unreadable key';
    }
  }
  let operator = null;
  try {
    operator = os.userInfo().username;
  } catch (_) {
    operator = null;
  }
  return {by, operator};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const mode = checkMode(process.env, args);
  if (!mode.ok) {
    console.error(`✗ ${mode.reason}`);
    process.exit(2);
  }
  const req = parseRequest(args);
  if (req.error) {
    console.error(`✗ ${req.error}`);
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || PROJECT});
  const deps = {
    db: admin.firestore(),
    auth: admin.auth(),
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  };
  console.log(`目标：${mode.reason}`);
  const p = await plan(deps, req);
  if (p.error) {
    console.error(`✗ ${p.error}`);
    process.exit(2);
  }
  for (const line of describe(p)) console.log(`  ${line}`);
  if (!mode.confirm) {
    console.log('空跑：什么都没改。确认无误后加 --confirm' +
      (mode.emulator ? '' : ' --production') + ' 再跑一次。');
    return;
  }
  const out = await apply(deps, p, whoRuns(process.env, require('fs')));
  console.log(`✓ 已修改。记录：${LOG_COLLECTION}/${out.logId}`);
  if (out.password) {
    console.log(`新密码（只显示这一次）：${out.password}`);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(`✗ ${err && (err.code || err.message) || err}`);
    process.exit(1);
  });
}

module.exports = {PROJECT, LOG_COLLECTION, PASSWORD_CHARS, PASSWORD_LENGTH,
  parseArgs, last4, randomPassword, checkMode, parseRequest, plan, describe,
  apply, whoRuns};

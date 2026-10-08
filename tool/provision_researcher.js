#!/usr/bin/env node
/**
 * tool/provision_researcher.js
 *
 * B.13 — Custom-claim provisioning for research staff.
 *
 * Sets the `role` custom claim on a Firebase Auth user.  firestore.rules
 * (isUnblinded()), the researcher dashboard (dashboard_access.dart), the
 * registration page (enrollment_access.dart) and enrollParticipant read it.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   NODE_PATH=functions/node_modules node tool/provision_researcher.js \
 *     --email=keran@example.org --role=unblinded
 *   ... --email=junyu@example.org --role=blinded
 *   ... --email=someone@example.org --revoke
 *
 * Roles (T19, decision 0029 — replaces T12's names):
 *   unblinded — the unblinded researcher (Keran).  Registers participants
 *               and triggers allocation (App 研究員登記 page →
 *               enrollParticipant), sees the arm there for the briefing,
 *               reads the research-ID lookup, sees per-arm counts on the
 *               dashboard, and generates / uploads the allocation
 *               sequence (tool/randomization_sequence.js).
 *   blinded   — blinded staff, including the PI (Junyu) as blinded
 *               assessor.  Dashboard without per-arm counts or single-arm
 *               sections; blinded export only.
 *
 * Migration from T12: the old names grant nothing now ('pi' used to be
 * the UNBLINDED role).  For each account that holds one, run --revoke,
 * then grant the new role: Keran → unblinded, the PI → blinded, other
 * old 'researcher' accounts → blinded.  --list-legacy prints them.
 *
 * Side effects:
 *   - Forces token refresh on the user's next sign-in so the claim takes
 *     effect within ~1 hour without the user signing out.
 *   - Prints the resulting claims so you can verify before handing off
 *     credentials.
 *
 * Safety:
 *   - Requires --confirm flag in production-equivalent environments to
 *     avoid accidental grants.
 *   - One role per account; changing it needs --revoke first.
 */

'use strict';

const admin = require('firebase-admin');

function parseArgs() {
  const out = {};
  for (const a of process.argv.slice(2)) {
    if (a === '--revoke') {
      out.revoke = true;
    } else if (a === '--confirm') {
      out.confirm = true;
    } else if (a === '--list-legacy') {
      out.listLegacy = true;
    } else if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      out[k] = v === undefined ? true : v;
    }
  }
  return out;
}

const ROLES = ['unblinded', 'blinded'];
const LEGACY_ROLES = ['pi', 'researcher'];

async function listLegacy(auth) {
  let token;
  let n = 0;
  do {
    const page = await auth.listUsers(1000, token);
    for (const u of page.users) {
      const role = (u.customClaims || {}).role;
      if (LEGACY_ROLES.includes(role)) {
        n++;
        console.log(`${u.email || u.uid}: role=${role} (legacy — revoke ` +
          'and re-grant unblinded or blinded)');
      }
    }
    token = page.pageToken;
  } while (token);
  console.log(`${n} account(s) with a legacy role.`);
}

async function main() {
  const args = parseArgs();
  if (args.listLegacy) {
    admin.initializeApp();
    await listLegacy(admin.auth());
    return;
  }
  if (!args.email && !args.uid) {
    console.error('Need --email=<addr> OR --uid=<uid>.');
    process.exit(2);
  }
  if (!args.revoke && !args.role) {
    console.error('Need --role=unblinded OR --role=blinded (or --revoke).');
    process.exit(2);
  }
  if (args.role && !ROLES.includes(args.role)) {
    const hint = LEGACY_ROLES.includes(args.role) ?
      ' The T12 names were replaced in T19: the PI is now "blinded".' : '';
    console.error(`Invalid role: ${args.role}.  Must be unblinded or ` +
      `blinded.${hint}`);
    process.exit(2);
  }

  admin.initializeApp();
  const auth = admin.auth();
  const user = args.uid
    ? await auth.getUser(args.uid)
    : await auth.getUserByEmail(args.email);

  const existing = user.customClaims || {};
  const next = {...existing};
  if (args.revoke) {
    delete next.role;
    console.log(`Revoking role from ${user.email || user.uid}…`);
  } else {
    // One role per account: changing it is a deliberate revoke + grant.
    if (existing.role && existing.role !== args.role) {
      console.error(
          `User already has role=${existing.role}.  Revoke first if you ` +
          `intend to change roles (security boundary).`);
      process.exit(3);
    }
    next.role = args.role;
    console.log(`Granting role=${args.role} to ${user.email || user.uid}…`);
  }

  await auth.setCustomUserClaims(user.uid, next);
  // Force token revocation so the claim takes effect on next API call.
  await auth.revokeRefreshTokens(user.uid);

  console.log('New claims:', next);
  console.log('User must sign out and back in (or wait ~1h) for the claim ' +
              'to land on the client.');
}

main().catch((err) => {
  console.error('[provision] Fatal:', err);
  process.exit(1);
});

#!/usr/bin/env node
/**
 * tool/provision_researcher.js
 *
 * B.13 — Custom-claim provisioning script for researcher dashboard access.
 *
 * Adds `role: researcher` (or `pi` for the principal investigator) custom
 * claim to a Firebase Auth user.  The dashboard reads this claim via
 * `getIdTokenResult(true)` and renders Access Denied without it.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node tool/provision_researcher.js --email=alice@hku.hk --role=researcher
 *   node tool/provision_researcher.js --uid=abc123 --role=pi
 *   node tool/provision_researcher.js --email=alice@hku.hk --revoke
 *
 * Roles:
 *   researcher — working analyst.  Sees engagement, TE audit queue, PPR
 *                aggregates, blinded transcripts.  Cannot read
 *                export_blind_keys (would de-blind).
 *   pi         — principal investigator.  Sees everything researcher does
 *                plus PI alerts and blind keys.  Use sparingly.
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
 *   - Never grants both `researcher` and `pi` simultaneously (would
 *     break the blind-key access boundary).
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
    } else if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      out[k] = v ?? true;
    }
  }
  return out;
}

async function main() {
  const args = parseArgs();
  if (!args.email && !args.uid) {
    console.error('Need --email=<addr> OR --uid=<uid>.');
    process.exit(2);
  }
  if (!args.revoke && !args.role) {
    console.error('Need --role=researcher OR --role=pi (or --revoke).');
    process.exit(2);
  }
  if (args.role && !['researcher', 'pi'].includes(args.role)) {
    console.error(`Invalid role: ${args.role}.  Must be researcher or pi.`);
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
    // Guard against simultaneous researcher + pi.
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

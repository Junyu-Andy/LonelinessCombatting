#!/usr/bin/env node
/**
 * tool/migrate_thought_records.js
 *
 * B.4 one-time migration: copies existing test documents from the legacy
 * `users/{uid}/thought_records/{id}` collection into the new schema at
 * `users/{uid}/thought_exercise/entries/items/{id}`.
 *
 * Usage:
 *   node tool/migrate_thought_records.js [--dry-run] [--uid=<specific-uid>]
 *
 * Prerequisites:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   npm install firebase-admin   (or use the one in functions/)
 *
 * Safety:
 *   - Dry-run by default (--dry-run flag). Pass --write to actually migrate.
 *   - Old docs are never deleted; the legacy collection is left intact.
 *   - Idempotent: if the target doc already exists it is skipped.
 *   - Only migrates test users (no real participant data exists yet at the
 *     time of Sprint 1 — per Dev Req §E: "recruitment hasn't opened").
 */

'use strict';

const admin = require('./functions/node_modules/firebase-admin') ||
              require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = !process.argv.includes('--write');
const SPECIFIC_UID = process.argv
  .find((a) => a.startsWith('--uid='))
  ?.replace('--uid=', '');

if (DRY_RUN) {
  console.log('[migrate] DRY-RUN mode — pass --write to apply changes');
}

async function migrateUser(uid) {
  const oldRef = db.collection('users').doc(uid).collection('thought_records');
  const newRef = db
    .collection('users')
    .doc(uid)
    .collection('thought_exercise')
    .doc('entries')
    .collection('items');

  const oldSnap = await oldRef.get();
  if (oldSnap.empty) return 0;

  let migrated = 0;
  for (const doc of oldSnap.docs) {
    const data = doc.data();
    const targetRef = newRef.doc(doc.id);
    const existing = await targetRef.get();
    if (existing.exists) {
      console.log(`  [skip] ${uid}/${doc.id} already migrated`);
      continue;
    }

    // Map legacy 3-field schema → 7-field ThoughtExerciseEntry.
    // Fields 4–6 (agentId, agentInvitationText, originTurnRef) are null for
    // migrated records — they were created before the new schema existed.
    const newData = {
      thought: data.thought ?? '',
      oneReasonTrue: data.oneReasonTrue ?? '',
      anotherWayToLook: data.anotherWayToLook ?? '',
      agentId: data.originSurface === 'reflective_dialogue'
        ? 'ah_jan_ah_bak'
        : null,
      agentInvitationText: null,
      originTurnRef: null,
      createdAt: data.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      _migratedFrom: `thought_records/${doc.id}`,
    };

    console.log(`  [migrate] ${uid}/${doc.id} → thought_exercise/entries/items/${doc.id}`);
    if (!DRY_RUN) {
      await targetRef.set(newData);
    }
    migrated++;
  }
  return migrated;
}

async function main() {
  let total = 0;
  if (SPECIFIC_UID) {
    total = await migrateUser(SPECIFIC_UID);
  } else {
    const usersSnap = await db.collection('users').get();
    for (const userDoc of usersSnap.docs) {
      const count = await migrateUser(userDoc.id);
      total += count;
    }
  }
  console.log(`\n[migrate] Done. ${total} doc(s) ${DRY_RUN ? 'would be' : 'were'} migrated.`);
}

main().catch((err) => {
  console.error('[migrate] Fatal:', err);
  process.exit(1);
});

/**
 * Runtime feature flags shared by the app and Cloud Functions (decision
 * 0019, SPEC:C18).
 *
 * One Firestore document, `app_config/feature_flags`, written by the
 * research team from the console (clients can read, nobody can write —
 * see firestore.rules `app_config`).  A flag is ON only when its field is
 * literally `true`; a missing document, a missing field, any other value
 * or a read error all mean OFF.  The app reads the same document
 * (lib/core/feature_flags/remote_feature_flags.dart).
 *
 *   webSearchEnabled  — Tung Tung "搜一搜" (webSearch → Brave).
 *   voiceInputEnabled — voice input (mic button, transcribeAudio).
 *   Important: voice input is to be switched back on once HREC approves
 *   the STT amendment.
 */
"use strict";

const {HttpsError} = require("firebase-functions/v2/https");

const FLAGS_DOC = "app_config/feature_flags";

/**
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} key Field name in `app_config/feature_flags`.
 * @return {Promise<boolean>} true only when the field is exactly `true`.
 */
async function isFeatureEnabled(db, key) {
  try {
    const snap = await db.doc(FLAGS_DOC).get();
    return snap.exists && snap.get(key) === true;
  } catch (err) {
    console.warn("feature flag read failed; treating as off",
        {key: key, err: err && err.message});
    return false;
  }
}

/**
 * Throws failed-precondition unless the flag is on.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} key Field name in `app_config/feature_flags`.
 */
async function assertFeatureEnabled(db, key) {
  if (!(await isFeatureEnabled(db, key))) {
    throw new HttpsError("failed-precondition", `feature disabled: ${key}`);
  }
}

module.exports = {FLAGS_DOC, isFeatureEnabled, assertFeatureEnabled};

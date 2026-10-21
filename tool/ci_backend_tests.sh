#!/usr/bin/env bash
# Backend tests: Cloud Functions unit tests and the local ops dashboard's
# unit tests, then everything that needs the Firestore emulator (security
# rules + functions *_emulator_test.js + the dashboard), then
# tool/delete_participant.js, tool/set_shared_context_consent.js and
# tool/purge_tester_data.js and tool/update_login_email.js on the Auth +
# Firestore + Storage emulators.
#
# Needs Node, Java 21+ and the Firebase CLI (npm i -g firebase-tools).
# Usage: tool/ci_backend_tests.sh

set -euo pipefail
cd "$(dirname "$0")/.."

echo "::group::functions unit tests"
(
  cd functions
  for t in test/*_test.js; do
    case "$t" in *_emulator_test.js) continue ;; esac
    echo "--- $t"
    node "$t"
  done
)
echo "::endgroup::"

echo "::group::local ops dashboard unit tests (decision 0061)"
NODE_PATH=functions/node_modules node tool/dashboard/test/dashboard_unit_test.js
echo "::endgroup::"

echo "::group::rules + emulator tests"
(cd test/rules && npm install --no-audit --no-fund)
firebase emulators:exec --only firestore --project loneliness-pilot-dev '
  set -e
  (cd test/rules && npm test)
  cd functions
  for t in test/*_emulator_test.js; do
    [ -e "$t" ] || continue
    echo "--- $t"
    node "$t"
  done
  cd ..
  # Last: it empties the emulator, then seeds its own synthetic data.
  NODE_PATH=functions/node_modules node tool/dashboard/test/dashboard_emulator_test.js
'
echo "::endgroup::"

echo "::group::privacy and account scripts: deletion + shared-context consent + tester purge + login e-mail change (auth + firestore + storage emulators)"
firebase emulators:exec --config test/delete_participant/firebase.json \
  --only auth,firestore,storage --project loneliness-pilot-dev \
  'set -e
   NODE_PATH=functions/node_modules node test/delete_participant/delete_participant_test.js
   NODE_PATH=functions/node_modules node test/delete_participant/set_shared_context_consent_test.js
   NODE_PATH=functions/node_modules node test/delete_participant/purge_tester_data_test.js
   NODE_PATH=functions/node_modules node test/admin_tools/update_login_email_test.js'
echo "::endgroup::"
echo "All backend tests passed."

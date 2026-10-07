#!/usr/bin/env bash
# Backend tests: Cloud Functions unit tests, then everything that needs the
# Firestore emulator (security rules + functions *_emulator_test.js), then
# tool/delete_participant.js on the Auth + Firestore + Storage emulators.
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
'
echo "::endgroup::"

echo "::group::whole-participant deletion (auth + firestore + storage emulators)"
firebase emulators:exec --config test/delete_participant/firebase.json \
  --only auth,firestore,storage --project loneliness-pilot-dev \
  'NODE_PATH=functions/node_modules node test/delete_participant/delete_participant_test.js'
echo "::endgroup::"
echo "All backend tests passed."

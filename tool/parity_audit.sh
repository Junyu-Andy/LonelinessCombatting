#!/usr/bin/env bash
# P5.2 — arm-parity audit harness.
#
# Usage:
#   tool/parity_audit.sh           run the suite (CI mode, fails on
#                                  any golden mismatch)
#   tool/parity_audit.sh --update  regenerate goldens (developer
#                                  workflow — review the diff before
#                                  committing)
#
# Pre-flight:
#   - `flutter pub get` must have been run successfully.
#   - For full-page tests that depend on Firebase / network, those
#     services need to be stubbed (TODO under test/parity/_mocks/).

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--update" ]]; then
  echo "[parity] regenerating goldens"
  flutter test --update-goldens test/parity/
else
  echo "[parity] verifying goldens (CI mode)"
  flutter test test/parity/
fi

#!/usr/bin/env bash
# Flutter test suites for CI and local runs.
#
# Runs every build variant the tests care about and reports all failures
# at the end instead of stopping at the first one:
#   1. default (Phase A) build — the full suite
#   2. PHASE_B=true           — arm gating / parity tests
#   3. PHASE_B + FORCE_ARM=B  — Arm B pages (rule-based Tung Tung)
#   4. MEMORY_V1=true         — memory v1 client tests (memory branch)
#   5. RULE_TEMPLATE_REPLIES=true — placeholder guard keeps pages unchanged
#   6. RULE_TEMPLATE_REPLIES + ALLOW_PLACEHOLDER — Arm B template replies
#      (decision 0023)
#
# Usage: tool/ci_flutter_tests.sh

set -uo pipefail
cd "$(dirname "$0")/.."

failed=()

run() {
  local name="$1"; shift
  echo "::group::$name"
  if flutter test "$@"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    failed+=("$name")
  fi
  echo "::endgroup::"
}

run "phase A (default build)"
run "phase B arm gating" --dart-define=PHASE_B=true \
  test/arm_gate_test.dart test/parity/ test/memory_v1_client_test.dart \
  test/djg_w2_test.dart \
  test/ada_test.dart
run "phase B arm B pages" \
  --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
  test/tung_tung_arm_b_test.dart test/my_story_arm_test.dart
[ -f test/memory_v1_client_test.dart ] && run "memory v1 client" \
  --dart-define=MEMORY_V1=true test/memory_v1_client_test.dart
run "rule template replies (placeholder guard)" \
  --dart-define=RULE_TEMPLATE_REPLIES=true \
  test/rule_reply_pool_test.dart test/rule_reply_pages_test.dart
run "rule template replies on" \
  --dart-define=RULE_TEMPLATE_REPLIES=true \
  --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true \
  test/rule_reply_pool_test.dart test/rule_reply_pages_test.dart

if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed suites: ${failed[*]}"
  exit 1
fi
echo "All Flutter suites passed."

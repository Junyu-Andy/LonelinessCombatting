#!/usr/bin/env bash
# Flutter test suites for CI and local runs.
#
# Runs every build variant the tests care about and reports all failures
# at the end instead of stopping at the first one:
#   1. default (Phase A) build — the full suite
#   2. PHASE_B=true           — arm gating / parity tests; the safety
#                               classifier (T26: same in every build)
#   3. PHASE_B + FORCE_ARM=B  — Arm B pages (rule-based Tung Tung)
#      (1020e §2.14: the researcher intake gate runs in 1, 2 and 3 — the
#      same page and flow for both arms)
#      (1020c 小讀本: test/reader_test.dart runs in 2 and 3 for the
#      「問下通通」 split — Hybrid only, no LLM path for the rule arm)
#   4. MEMORY_V1=true         — memory v1 client tests (memory branch)
#   5. RULE_TEMPLATE_REPLIES=true — final templates on (T33: no placeholder
#      left, so the switch alone turns them on)
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
  test/djg_w2_test.dart test/phase_b_hidden_surfaces_test.dart \
  test/suggestions_use_profile_test.dart \
  test/ada_test.dart test/safety_classifier_test.dart \
  test/weekly_schedule_test.dart test/weekly_bundle_flow_test.dart \
  test/tester_arm_switch_test.dart test/tester_weekly_bundle_page_test.dart \
  test/tester_tools_1020f_test.dart \
  test/reminiscence_avoid_topics_test.dart \
  test/memory_handover_pages_test.dart \
  test/check_in_chat_v2_test.dart \
  test/siu_yan_prompts_mood_1020l_test.dart \
  test/keyboard_compact_header_test.dart \
  test/action_plan_simplified_test.dart \
  test/reminiscence_v2_test.dart \
  test/profile_editor_keyboard_test.dart \
  test/home_v2_test.dart test/mood_row_v2_test.dart \
  test/researcher_intake_gate_test.dart \
  test/reader_test.dart \
  test_manual/ui_text_scale_sweep_test.dart
run "phase B arm B pages" \
  --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
  test/tung_tung_arm_b_test.dart test/my_story_arm_test.dart \
  test/memory_handover_pages_test.dart \
  test/siu_yan_prompts_mood_1020l_test.dart \
  test/keyboard_compact_header_test.dart \
  test/home_v2_test.dart test/mood_row_v2_test.dart \
  test/action_plan_simplified_test.dart \
  test/researcher_intake_gate_test.dart \
  test/reader_test.dart \
  test_manual/ui_text_scale_sweep_test.dart
[ -f test/memory_v1_client_test.dart ] && run "memory v1 client" \
  --dart-define=MEMORY_V1=true test/memory_v1_client_test.dart
run "rule template replies (switch only)" \
  --dart-define=RULE_TEMPLATE_REPLIES=true \
  test/rule_reply_pool_test.dart test/rule_reply_pages_test.dart
run "rule template replies on" \
  --dart-define=RULE_TEMPLATE_REPLIES=true \
  --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true \
  test/rule_reply_pool_test.dart test/rule_reply_pages_test.dart \
  test/siu_yan_prompts_mood_1020l_test.dart

if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed suites: ${failed[*]}"
  exit 1
fi
echo "All Flutter suites passed."

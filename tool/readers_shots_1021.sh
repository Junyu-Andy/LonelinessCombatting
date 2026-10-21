#!/usr/bin/env bash
# 1021 小讀本 — screenshots for Junyu, both arms, phone 360 × 800 at the
# largest App text size (1.30), of whatever units are in assets/readers/:
#   list_<arm>.png, list_full_<arm>.png   讀少少 (first screen, whole list)
#   toc_<arm>.png      one unit's contents, inside the native top bar
#   section_<arm>.png  its first section
#   done_<arm>.png     its contents once all sections are read (小欣 block)
# into docs/dev-reports/readers-1021-shots/ (<arm> = hybrid / rule).
# The WebView part is the unit's real HTML as the App prepares it,
# rendered by headless Chromium; every unit is also checked there (see
# tool/render_reader_shots.js).
#
#   tool/readers_shots_1021.sh [unit id]     (default: the first unit)
#
# Needs: Flutter 3.44.1 on PATH, Node with Playwright (npm root -g) and
# Chromium (CHROMIUM_PATH or /opt/pw-browsers/chromium), the WenQuanYi Zen
# Hei font.  Uses the phase_b_templates defines (the arm comes from the
# profile).  Afterwards analysis_options.yaml / pubspec.lock are restored.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
UNIT="${1:-}"
DEFINES=(--dart-define=SHOTS=true --dart-define=PHASE_B=true
  --dart-define=RULE_TEMPLATE_REPLIES=true)
[ -n "$UNIT" ] && DEFINES+=("--dart-define=READER_SHOT_UNIT=$UNIT")

restore() { git checkout -- analysis_options.yaml pubspec.lock 2>/dev/null || true; }
trap restore EXIT

rm -rf build/readers_shots_1021
echo "== 1/3 the pages the App would load"
flutter test test_manual/readers_shots_1021_test.dart "${DEFINES[@]}" \
  --dart-define=READER_SHOTS_STEP=prepare --plain-name 'step 1'
echo "== 2/3 headless Chromium (pictures + checks of every unit)"
NODE_PATH="$(npm root -g)" node tool/render_reader_shots.js \
  build/readers_shots_1021/jobs.json
echo "== 3/3 the App screens"
flutter test test_manual/readers_shots_1021_test.dart "${DEFINES[@]}" \
  --dart-define=READER_SHOTS_STEP=frame --plain-name 'step 3' --update-goldens
echo "Shots: docs/dev-reports/readers-1021-shots/"

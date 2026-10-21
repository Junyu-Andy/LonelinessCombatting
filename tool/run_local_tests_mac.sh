#!/usr/bin/env bash
# tool/run_local_tests_mac.sh — every test CI runs, on the research lead's
# Mac (1020i §1).  Emulator and synthetic data only: it refuses to start
# when the environment points at a real project.
#
# Order: flutter analyze (+ the 小讀本 HTML check) → the six Flutter suites
# (tool/ci_flutter_tests.sh, the same list as CI) → Functions unit tests →
# Firestore rules tests + Functions emulator tests (one Firestore emulator,
# started and stopped by `firebase emulators:exec`) → the privacy scripts
# (Auth + Firestore + Storage emulators).  Each step prints 通过 / 失败; a
# failed step does not stop the later ones; a summary with times comes
# last.  Full logs go to build/local-tests/<time>/.
#
# Usage (repository root):
#   bash tool/run_local_tests_mac.sh                  # everything
#   bash tool/run_local_tests_mac.sh --only flutter   # one group
#   bash tool/run_local_tests_mac.sh --only rules,functions
# Groups: analyze, flutter, functions, rules (alias: emulator), privacy.
# Written for the bash 3.2 that macOS ships (no associative arrays).
# Guide: docs/release/local-tests-mac.md

cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

ALL_GROUPS="analyze flutter functions rules privacy"
ONLY=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --only=*) ONLY="${1#--only=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不认识的参数：$1（用 --help 看用法）"; exit 2 ;;
  esac
done

GROUPS_TO_RUN=""
if [ -z "$ONLY" ]; then
  GROUPS_TO_RUN="$ALL_GROUPS"
else
  for g in $(echo "$ONLY" | tr ',' ' '); do
    case "$g" in
      analyze|flutter|functions|rules|privacy) ;;
      emulator) g=rules ;;
      *) echo "不认识的组：$g（可选：analyze flutter functions rules privacy）"; exit 2 ;;
    esac
    GROUPS_TO_RUN="$GROUPS_TO_RUN $g"
  done
fi
wants() { case " $GROUPS_TO_RUN " in *" $1 "*) return 0 ;; esac; return 1; }

# --- Emulator only: refuse anything that points at a real project --------
refuse() {
  echo ""
  echo "✗ 停止：$1"
  echo "  这份脚本只连本机模拟器。请在这个终端里先运行上面那行 unset，再重跑。"
  exit 2
}
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  refuse "设了正式项目的钥匙 GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS
  unset GOOGLE_APPLICATION_CREDENTIALS"
fi
for v in GCLOUD_PROJECT GOOGLE_CLOUD_PROJECT FIREBASE_CONFIG; do
  eval "val=\${$v:-}"
  if [ -n "$val" ]; then
    refuse "设了 $v=$val，会让脚本指向真实项目
  unset $v"
  fi
done
for v in FIRESTORE_EMULATOR_HOST FIREBASE_AUTH_EMULATOR_HOST \
    FIREBASE_STORAGE_EMULATOR_HOST; do
  eval "val=\${$v:-}"
  case "$val" in
    ""|localhost:*|127.0.0.1:*|"[::1]:"*) ;;
    *) refuse "$v=$val 不是本机地址
  unset $v" ;;
  esac
done
# Hide any `gcloud auth application-default login` credentials from the
# test processes, so nothing can reach a real project by accident.
CLOUDSDK_CONFIG="$(mktemp -d "${TMPDIR:-/tmp}/local-tests-gcloud.XXXXXX")"
export CLOUDSDK_CONFIG
unset GOOGLE_APPLICATION_CREDENTIALS

STAMP="$(date +%Y%m%d-%H%M%S)"
LOGDIR="$ROOT/build/local-tests/$STAMP"
mkdir -p "$LOGDIR"
START_ALL=$(date +%s)

# Flutter rewrites these two files; put them back at the end if they were
# unchanged before the run (CLAUDE.md).
RESTORE_FILES=""
for f in analysis_options.yaml pubspec.lock; do
  if [ -f "$f" ] && git diff --quiet -- "$f" 2>/dev/null; then
    RESTORE_FILES="$RESTORE_FILES $f"
  fi
done

# --- Result table (parallel lists; bash 3.2) ------------------------------
R_NAMES=()
R_STATES=()
R_SECS=()
R_NOTES=()
record() { # name state secs note
  R_NAMES[${#R_NAMES[@]}]="$1"
  R_STATES[${#R_STATES[@]}]="$2"
  R_SECS[${#R_SECS[@]}]="$3"
  R_NOTES[${#R_NOTES[@]}]="$4"
}
fmt() { printf '%d 分 %02d 秒' $(($1 / 60)) $(($1 % 60)); }

# run_step <name> <log file> <command...>: runs the command with output to
# the log, prints 通过 / 失败 and the last lines of the log on failure.
run_step() {
  local name="$1" log="$2"; shift 2
  local t0=$(date +%s)
  echo ""
  echo "▶ $name …（日志：${log#$ROOT/}）"
  if "$@" >"$log" 2>&1; then
    local s=$(( $(date +%s) - t0 ))
    echo "  ✓ 通过  $name（$(fmt $s)）"
    record "$name" "通过" "$s" ""
    return 0
  else
    local s=$(( $(date +%s) - t0 ))
    echo "  ✗ 失败  $name（$(fmt $s)）。日志最后 25 行："
    tail -n 25 "$log" | sed 's/^/    | /'
    record "$name" "失败" "$s" "${STEP_NOTE:-}"
    return 1
  fi
}
skip_step() { # name reason
  echo ""
  echo "▶ $1"
  echo "  ✗ 失败  $1：$2"
  record "$1" "失败" 0 "$2"
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- Prerequisites (printed, never fatal) ---------------------------------
echo "== 环境 =="
NEED_FLUTTER=0; NEED_NODE=0; NEED_FIREBASE=0
wants analyze && NEED_FLUTTER=1
wants flutter && NEED_FLUTTER=1
wants functions && NEED_NODE=1
wants rules && { NEED_NODE=1; NEED_FIREBASE=1; }
wants privacy && { NEED_NODE=1; NEED_FIREBASE=1; }
FLUTTER_OK=1; NODE_OK=1; FIREBASE_OK=1; JAVA_OK=1
if [ $NEED_FLUTTER = 1 ]; then
  if have flutter; then
    fv="$(flutter --version 2>/dev/null | head -n 1)"
    echo "  Flutter：$fv"
    case "$fv" in *"3.44.1"*) ;; *) echo "  ⚠ CI 用 Flutter 3.44.1，你的版本不同，结果可能不一样" ;; esac
  else
    echo "  ✗ 没有 flutter（安装见 docs/release/local-tests-mac.md）"; FLUTTER_OK=0
  fi
fi
if [ $NEED_NODE = 1 ]; then
  if have node; then
    nv="$(node -v)"; echo "  Node：$nv"
    case "$nv" in v24.*) ;; *) echo "  ⚠ CI 用 Node 24，你的版本是 $nv" ;; esac
  else
    echo "  ✗ 没有 node"; NODE_OK=0
  fi
fi
if [ $NEED_FIREBASE = 1 ]; then
  if have firebase; then
    echo "  firebase-tools：$(firebase --version 2>/dev/null)"
  else
    echo "  ✗ 没有 firebase 命令（npm install -g firebase-tools）"; FIREBASE_OK=0
  fi
  # The version line, not a "Picked up JAVA_TOOL_OPTIONS" line before it.
  jv=""
  have java && jv="$(java -version 2>&1 | grep -m 1 'version')"
  jmajor="$(echo "$jv" | sed -n -E 's/.*version "([0-9]+)[^"]*".*/\1/p')"
  if [ -n "$jmajor" ] && [ "$jmajor" -ge 21 ] 2>/dev/null; then
    echo "  Java：$jv"
  else
    echo "  ✗ 模拟器要 Java 21 或更新，现在是：${jv:-没有 Java}"; JAVA_OK=0
  fi
fi

# --- Steps ------------------------------------------------------------------
if wants analyze; then
  if [ $FLUTTER_OK = 1 ]; then
    run_step "准备：flutter pub get" "$LOGDIR/pub_get.log" flutter pub get
    run_step "flutter analyze" "$LOGDIR/analyze.log" \
      flutter analyze --no-fatal-infos --no-fatal-warnings
    # Only errors fail the step (as in CI); show the count to compare with CI.
    n_issues="$(grep -Eo '[0-9]+ issues? found' "$LOGDIR/analyze.log" | head -n 1 | grep -Eo '^[0-9]+')"
    n_errors="$(grep -cE '^ *error ' "$LOGDIR/analyze.log")"
    [ -n "$n_issues" ] && R_NOTES[$((${#R_NOTES[@]} - 1))]="共 $n_issues 条提示，其中 error $n_errors 条"
  else
    skip_step "flutter analyze" "没有 flutter"
  fi
  if [ $NODE_OK = 1 ] || have node; then
    run_step "小讀本 HTML 检查" "$LOGDIR/reader_html.log" \
      sh -c 'node tool/check_reader_html.js && node test/reader_html_check/check_reader_html_test.js && node test/reader_html_check/add_readers_test.js'
  else
    skip_step "小讀本 HTML 检查" "没有 node"
  fi
fi

if wants flutter; then
  if [ $FLUTTER_OK = 1 ]; then
    wants analyze || run_step "准备：flutter pub get" "$LOGDIR/pub_get.log" flutter pub get
    STEP_NOTE=""
    if ! run_step "Flutter 测试（6 套，和 CI 同一份清单）" "$LOGDIR/flutter.log" \
        bash tool/ci_flutter_tests.sh; then
      :
    fi
    # Per-suite lines from tool/ci_flutter_tests.sh ("PASS  name" / "FAIL  name").
    echo "  各套结果："
    grep -E '^(PASS|FAIL)  ' "$LOGDIR/flutter.log" | sed -e 's/^PASS  /    ✓ /' -e 's/^FAIL  /    ✗ /'
    failed_suites="$(grep -E '^FAIL  ' "$LOGDIR/flutter.log" | sed 's/^FAIL  //' | tr '\n' ';')"
    if [ -n "$failed_suites" ]; then
      R_NOTES[$((${#R_NOTES[@]} - 1))]="失败的套：$failed_suites"
    fi
  else
    skip_step "Flutter 测试（6 套）" "没有 flutter"
  fi
fi

ensure_functions_deps() {
  if [ ! -d functions/node_modules ]; then
    run_step "准备：安装 Functions 依赖（npm ci）" "$LOGDIR/npm_functions.log" \
      npm ci --prefix functions --no-audit --no-fund
    return $?
  fi
  return 0
}

if wants functions; then
  if [ $NODE_OK = 1 ] && ensure_functions_deps; then
    run_step "Functions 单元测试" "$LOGDIR/functions_unit.log" sh -c '
      cd functions || exit 2
      fails=""
      for t in test/*_test.js; do
        case "$t" in *_emulator_test.js) continue ;; esac
        echo "--- $t"
        node "$t" || fails="$fails $t"
      done
      if [ -n "$fails" ]; then echo "FAILED:$fails"; exit 1; fi'
    ff="$(grep '^FAILED:' "$LOGDIR/functions_unit.log" | sed 's/^FAILED: *//')"
    if [ -n "$ff" ]; then
      echo "    失败的文件：$ff"
      R_NOTES[$((${#R_NOTES[@]} - 1))]="失败的文件：$ff"
    fi
  else
    skip_step "Functions 单元测试" "没有 node，或 npm ci 失败"
  fi
fi

port_busy() { # port → prints "port (PID …)" when something listens on it
  have lsof || return 1
  local pid
  pid="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -n 1)"
  [ -n "$pid" ] && { echo "$1（进程 $pid：$(ps -p "$pid" -o comm= 2>/dev/null)）"; return 0; }
  return 1
}
busy_ports() { # ports… → list of busy ones
  local out="" p b
  for p in "$@"; do b="$(port_busy "$p")" && out="$out $b"; done
  echo "${out# }"
}

if wants rules; then
  busy="$(busy_ports 8080 4400 4500 9150)"
  if [ $NODE_OK = 0 ] || [ $FIREBASE_OK = 0 ] || [ $JAVA_OK = 0 ]; then
    skip_step "Firestore 规则测试 + Functions 模拟器测试" "缺 node、firebase-tools 或 Java 21（见上面「环境」）"
  elif [ -n "$busy" ]; then
    skip_step "Firestore 规则测试 + Functions 模拟器测试" "端口被占用：$busy。先关掉占用的程序（见说明「常见报错」）"
  elif ensure_functions_deps; then
    run_step "准备：安装规则测试依赖" "$LOGDIR/npm_rules.log" \
      sh -c 'cd test/rules && npm install --no-audit --no-fund'
    RES="$LOGDIR/emulator_results.txt"; : >"$RES"
    run_step "Firestore 规则测试 + Functions 模拟器测试（自动起停模拟器）" \
      "$LOGDIR/rules_emulator.log" \
      firebase emulators:exec --only firestore --project loneliness-pilot-dev "
        res='$RES'
        if (cd test/rules && npm test); then echo 'rules PASS' >>\"\$res\"; else echo 'rules FAIL' >>\"\$res\"; fi
        cd functions || exit 2
        fails=''
        for t in test/*_emulator_test.js; do
          [ -e \"\$t\" ] || continue
          echo \"--- \$t\"
          node \"\$t\" || fails=\"\$fails \$t\"
        done
        if [ -n \"\$fails\" ]; then echo \"emulator FAIL\$fails\" >>\"\$res\"; else echo 'emulator PASS' >>\"\$res\"; fi
        ! grep -q FAIL \"\$res\""
    echo "  分开看："
    note=""
    if grep -q '^rules PASS' "$RES"; then echo "    ✓ Firestore 规则测试"
    else echo "    ✗ Firestore 规则测试（或模拟器没起来）"; note="规则测试失败；"; fi
    em="$(grep '^emulator ' "$RES")"
    case "$em" in
      "emulator PASS") echo "    ✓ Functions 模拟器测试" ;;
      "emulator FAIL"*) echo "    ✗ Functions 模拟器测试，失败的文件：${em#emulator FAIL }"
        note="${note}模拟器测试失败的文件：${em#emulator FAIL }" ;;
      *) echo "    ✗ Functions 模拟器测试没有跑（模拟器没起来，看日志）"
        note="${note}模拟器没起来，看日志" ;;
    esac
    [ -n "$note" ] && R_NOTES[$((${#R_NOTES[@]} - 1))]="$note"
  else
    skip_step "Firestore 规则测试 + Functions 模拟器测试" "npm ci 失败"
  fi
fi

if wants privacy; then
  busy="$(busy_ports 9099 8080 9199 4400 4500 9150)"
  if [ $NODE_OK = 0 ] || [ $FIREBASE_OK = 0 ] || [ $JAVA_OK = 0 ]; then
    skip_step "隐私脚本测试（删除参与者等）" "缺 node、firebase-tools 或 Java 21"
  elif [ -n "$busy" ]; then
    skip_step "隐私脚本测试（删除参与者等）" "端口被占用：$busy"
  elif ensure_functions_deps; then
    run_step "隐私脚本测试（删除参与者、共享同意、清测试员）" "$LOGDIR/privacy.log" \
      firebase emulators:exec --config test/delete_participant/firebase.json \
        --only auth,firestore,storage --project loneliness-pilot-dev \
        'fails=""
         for t in delete_participant_test set_shared_context_consent_test purge_tester_data_test; do
           echo "--- $t"
           NODE_PATH=functions/node_modules node "test/delete_participant/$t.js" || fails="$fails $t"
         done
         [ -z "$fails" ] || { echo "FAILED:$fails"; exit 1; }'
  else
    skip_step "隐私脚本测试" "npm ci 失败"
  fi
fi

# --- Restore, summary ----------------------------------------------------
for f in $RESTORE_FILES; do git checkout -- "$f" 2>/dev/null; done
rm -rf "$CLOUDSDK_CONFIG"

TOTAL=$(( $(date +%s) - START_ALL ))
echo ""
echo "================= 汇总 ================="
n_fail=0
i=0
while [ $i -lt ${#R_NAMES[@]} ]; do
  st="${R_STATES[$i]}"
  [ "$st" = "失败" ] && n_fail=$((n_fail + 1))
  mark="✓"; [ "$st" = "失败" ] && mark="✗"
  line="$mark $st  ${R_NAMES[$i]}（$(fmt "${R_SECS[$i]}")）"
  [ -n "${R_NOTES[$i]}" ] && line="$line —— ${R_NOTES[$i]}"
  echo "$line"
  i=$((i + 1))
done
echo "----------------------------------------"
echo "总用时 $(fmt $TOTAL)。日志：${LOGDIR#$ROOT/}/"
if [ $n_fail -eq 0 ]; then
  echo "全部通过。"
  exit 0
fi
echo "$n_fail 步失败。把上面这段汇总和对应的日志文件发给开发窗口。"
exit 1

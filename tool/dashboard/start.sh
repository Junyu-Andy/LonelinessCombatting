#!/usr/bin/env bash
# tool/dashboard/start.sh — open the local ops dashboard (decision 0061).
# Guide: docs/release/ops-dashboard-local.md
#
#   bash tool/dashboard/start.sh            real project, read only, with the
#                                           dashboard's own viewer key
#   bash tool/dashboard/start.sh --demo     Firestore emulator + synthetic
#                                           data (no key, nothing real)
#
# The key: DASHBOARD_KEY=<path>, default ~/dev/keys/dashboard-viewer.json.
# It must be outside the repository and readable only by you (chmod 600).
# Stop the dashboard with Ctrl+C.

cd "$(dirname "$0")/../.." || exit 2
PORT="${DASHBOARD_PORT:-8787}"
URL="http://127.0.0.1:${PORT}/"

if ! command -v node >/dev/null 2>&1; then
  echo "✗ 没有 node。安装见 docs/release/local-tests-mac.md 第一节。"; exit 2
fi
if [ ! -d functions/node_modules ]; then
  echo "第一次运行：安装依赖（npm ci，约 1 分钟）……"
  npm ci --prefix functions --no-audit --no-fund >/dev/null || {
    echo "✗ npm ci 失败，检查网络后重试。"; exit 2; }
fi
export NODE_PATH="$PWD/functions/node_modules"

open_browser() { # seconds to wait for the server first
  ( sleep "$1"; command -v open >/dev/null 2>&1 && open "$URL" ) &
}

if [ "${1:-}" = "--demo" ]; then
  if ! command -v firebase >/dev/null 2>&1; then
    echo "✗ 演示要 firebase-tools：npm install -g firebase-tools"; exit 2
  fi
  echo "演示模式：模拟器 + 合成数据，不连正式项目。"
  open_browser 15
  unset GOOGLE_APPLICATION_CREDENTIALS
  # A demo- project id keeps the CLI fully offline (no real project).
  exec firebase emulators:exec --only firestore --project demo-dashboard \
    "node tool/dashboard/test/seed_synthetic.js && DASHBOARD_NOW=2026-11-20T02:00:00Z node tool/dashboard/server.js --emulator --port=${PORT}"
fi

KEY="${DASHBOARD_KEY:-$HOME/dev/keys/dashboard-viewer.json}"
if [ ! -f "$KEY" ]; then
  echo "✗ 找不到看板的只读钥匙：$KEY"
  echo "  按说明第一节建只读服务账号、下载钥匙，放到这个位置；"
  echo "  或者用 DASHBOARD_KEY=<钥匙路径> bash tool/dashboard/start.sh"
  exit 2
fi
perm="$(stat -c '%a' "$KEY" 2>/dev/null || stat -f '%Lp' "$KEY" 2>/dev/null)"
if [ -n "$perm" ] && [ "$perm" != "600" ] && [ "$perm" != "400" ]; then
  echo "⚠ 钥匙文件别人也能读（权限 $perm）。建议先运行：chmod 600 \"$KEY\""
fi
unset FIRESTORE_EMULATOR_HOST
export GOOGLE_APPLICATION_CREDENTIALS="$KEY"
open_browser 4
exec node tool/dashboard/server.js --port="${PORT}"

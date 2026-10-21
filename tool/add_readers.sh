#!/usr/bin/env bash
# 1021 — 小讀本一步加入和检查（docs/release/readers-file-format.md）。
#
#   tool/add_readers.sh [--keep] <zip 路径>
#
# 把写读本的窗口交来的 zip 里的单元放进 assets/readers/：
#   - 在临时目录里解开（zip 当作不可信的数据：路径穿越、链接、加密、解压后过大
#     都整个拒收；不运行里面的任何东西）；
#   - 每个单元跑 1020c 第三节六项检查（tool/check_reader_html.js）；
#   - 只有通过的单元进 assets/readers/ 和 manifest.json，不通过的列出原因；
#   - 默认 zip 是整套；--keep 保留 zip 里没有的、原来已通过的单元；
#   - 可以重跑；除了 assets/readers/ 和临时目录，什么都不碰。
# 退出码：0 全部通过；2 有单元不通过（通过的已放进去）；1 没有处理（没改任何东西）。
#
# 逻辑在 tool/add_readers.js（只用 Node 自带模块）；测试：
#   node test/reader_html_check/add_readers_test.js
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "需要 Node.js（node 命令）。" >&2
  exit 1
fi

exec node "$ROOT/tool/add_readers.js" "$@"

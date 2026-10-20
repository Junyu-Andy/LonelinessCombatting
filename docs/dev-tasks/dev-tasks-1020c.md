# 开发窗口交接 1020c：「讀少少」内嵌 HTML 小读本

产品窗口 10/19 晚写，放进仓库 docs/dev-tasks/。依据：claude/decisions-log.md 10/19 第 38 条。内容规格见 claude/孤单小读本-内容大纲-1019.md（Junyu 会一并放进仓库 docs/spec/copy/）。本交接和 1020、1020b 冲突时，以 1020b 的冻结规则为准。

## 共同规则

(1) 不推 main，只开 PR 草稿。
(2) 不碰生产数据，只用 emulator 和合成数据。
(3) 新行为放在开关后：`htmlReadersEnabled`，默认 false。
(4) 老人看得到的文字只写草稿；小读本正文由 Junyu 提供，开发不改字。
(5) 不改热线号码；小读本里不得出现任何电话号码。
(6) 不读、不改、不删序列、`randomization_state`、分配日志和 `correctArm` 记录。

## 期限和范围

(1) 代码要在 10/21 冻结前合并。Junyu 10/20 22:00 前定稿的单元文件才放进冻结版本；之后的单元留到 Phase B 结束后，不在研究中途加。
(2) 这一项的优先级排在 1020b 第一节 C 和第 2 至 4 批之后。时间不够时，先保住 C 和第 2 至 4 批。
(3) 两组看到的小读本内容和界面完全相同。唯一的组间差异沿用登记表 C08：Hybrid 组在页底多一个「問下通通」，Rule-based 组没有。

## 第一节 技术做法

(1) 依赖：仓库现在没有 WebView。请评估 `webview_flutter`（官方包）加进 iOS 和安卓的影响：最低系统版本、包体积、iOS pod 和 Codemagic、安卓 GitHub Actions 是否要改。在 PR 里写清楚，再动手。
(2) 文件：单元文件随 App 打包，放 `assets/readers/`。每个单元两个文件：`<id>.html`（显示用）和 `<id>.txt`（纯文字，给「問下通通」）。另有 `assets/readers/manifest.json`：

```
[{"id": "u2_why_it_matters", "titleZh": "點解孤單要理", "minutes": 10, "order": 2}]
```

不从网络加载任何内容，也不设远程更新。
(3) 显示：
- 从 asset 读入 HTML，JavaScript 开启；
- 禁止一切外部网络请求和外部导航；只放行 `peizhu://` 链接，其他链接一律拦下不打开；
- 注入 CSS 变量 `--fs`，值等于 App 当前字號倍数（標準、大、特大）；
- 关闭页面缩放手势，避免老人误触放大后找不回原样；
- 返回键和返回手势回到「讀少少」列表。
(4) 行动按钮：拦截下面三个链接，转去 App 原生页面：
- `peizhu://cta/small_action`：今日小行動（建议页）
- `peizhu://cta/plan`：我嘅計劃，新建
- `peizhu://cta/thought`：望一望心入面
(5) 记录（过程数据，写进现有的使用事件，不含任何文字）：
- `reader_open`：单元 id；
- `reader_section`：读到哪一节（页面里 `data-section` 进入视窗时发，经 JS channel 回传）；
- `reader_cta`：撳了哪个行动按钮；
- `reader_close`：停留秒数。
(6) 「問下通通」（只 Hybrid 组）：沿用 `education_article_page` 现有的问答，文章文字换成 `<id>.txt` 的内容；提示词按 1020b 之后那段 prompt 第二项改为「電腦程式夥伴」的写法。Rule-based 组不显示这个按钮，和现有文章一致。

## 第二节 列表页

(1) 「讀少少」页顶部加一节「小讀本」，按 `order` 列出已打包的单元：标题、约几分钟、读过的打勾（按 `reader_close` 记录，本机显示即可）。
(2) 下面照旧列出现有 15 篇短文，不改。
(3) 页顶一行说明草稿：「每隔幾日睇一篇就得，唔使一次睇晒。」

## 第三节 检查脚本

写 `tool/check_reader_html.js`，对 `assets/readers/` 每个文件检查，不通过就报错，CI 也跑：
(1) 没有外部资源：`http://`、`https://`、`//` 开头的 src、href、`@import`、`url(`；
(2) 没有 `fetch(`、`XMLHttpRequest`、`WebSocket`、`localStorage`、`<form`、`<input`、`<textarea`、`tel:`；
(3) 没有电话号码样式的数字串（8 位数字或「xxxx xxxx」）；
(4) 正文里没有「AI」「模型」「機械人」「版本」「組」这几个字眼（注释里的不算）；
(5) 有 `data-section`；有同名 `.txt`；`manifest.json` 里有这个 id；
(6) 单个文件小于 1 MB。

## 第四节 测试和验收

(1) 用一份测试单元（开发自己写的占位 HTML，内容写明“測試”，不进正式构建）在 emulator 和真机上走：打开、滚动、三个行动按钮、返回、字號標準和特大、断网时照常显示。
(2) 两组各截一张图：Hybrid 组有「問下通通」，Rule-based 组没有，其余完全一样。
(3) 撳任何外部链接都不会打开浏览器。
(4) 使用事件四种都写入，且不含文字。
(5) iPhone 和安卓各测一次。

## 第五节 研究侧会同步改的（开发不用做）

(1) 登记表 C08 加一句：小读本两组相同，「問下通通」只在 Hybrid 组（沿用 C08）。
(2) B07 §5 教育内容的描述加“图文互动小读本”；B13 加一行；小读本正文列入修订包「App 内固定文字」附件。
(3) ICF 不改：小读本不收集任何文字。

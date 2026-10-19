# NNNN：「讀少少」加「小讀本」，用官方 WebView（`webview_flutter` 4.13.1）显示随 App 打包的 HTML，开关默认关（编号待 Junyu 给）

- 日期：2026-10-20
- 状态：提议中（依据 1020c；Junyu 审）
- 影响范围：pilot / phase_b × 两组（两组内容和界面相同；「問下通通」只在 Hybrid 组，沿用登记表 C08）
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-readers`（PR #130）；评估报告 `docs/dev-reports/webview-eval-20261020.md`

## 背景

产品窗口 10/19 决定（decisions-log 第 38 条）在「讀少少」加图文小读本。小读本由 Junyu 写成 HTML，页面里要跑一点 JS（报告读到哪一节）。App 之前没有 WebView。评估结论：官方包 `webview_flutter` 4.13.1 在锁定的 Flutter 3.35.3 上能用，系统版本不用改，包约大 1 MB；但它拦不住页面里图片、样式这类"附带请求"。

## 决定

1. **依赖**：`webview_flutter: 4.13.1`，写死版本（`pubspec.lock` 同时锁定 `webview_flutter_android` 4.12.0、`webview_flutter_wkwebview` 3.25.0、`webview_flutter_platform_interface` 2.15.1）。冻结前不升级。
2. **只用打包的内容**：单元文件放 `assets/readers/`（`<id>.html`、`<id>.txt`、`manifest.json`），随 App 打包。不从网络加载，不设远程更新。仓库里的 `manifest.json` 先是空表 `[]`，Junyu 10/20 22:00 前定稿的单元才放进冻结版本。
3. **两层断网**：
   - App 载入时把 HTML 读成字符串，在 `<head>` 最前面加一条严格的安全规则（CSP：`default-src 'none'`，只准页面自己写在文件里的样式和脚本、`data:` 图片和字体，`connect-src`/`frame-src`/`form-action` 全部 `'none'`），再用 `loadHtmlString`（不给 baseUrl）显示。
   - `tool/check_reader_html.js` 在 CI 里检查每个文件：没有外部链接和资源、没有 `fetch(` 等联网写法、没有电话号码、正文没有「AI」「模型」「機械人」「版本」「組」、有 `data-section`、有同名 `.txt`、在 `manifest.json` 里、小于 1 MB。不过就报错。
   - 导航只放行首次载入和 `peizhu://cta/…` 三个行动按钮；其他链接一律拦下，不开浏览器。
4. **开关**：`app_config/feature_flags.htmlReadersEnabled`，只认布尔 `true`，默认关。关着时「讀少少」和现在完全一样。开着但没有单元时，也不显示「小讀本」一节。
5. **两组**：小读本内容、列表、阅读页、三个行动按钮两组相同。唯一的组间差异沿用登记表 C08：Hybrid 组页底多一个「問下通通」（打开通通的文章问答，文章文字用 `<id>.txt`）；规则组没有这个按钮，也没有任何 LLM 路径。
6. **记录**：`reader_open`、`reader_section`、`reader_cta`、`reader_close` 写进现有的使用事件（`users/{uid}/usage_events`），跟 `usageEventsEnabled` 和"已入组"同一道闸。只记单元编号、节编号、按钮代号和秒数，不含任何文字。
7. **字号**：App 把它实际用的字号倍数（五档 1.06–1.30，`appFontScaleOnlyEnabled` 也已算在内）作为 CSS 变量 `--fs` 传给页面；安卓固定 `setTextZoom(100)`，不再叠加手机系统字号。关掉双指和双击放大。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 不用 WebView，把 HTML 转成 Flutter 原生界面（`flutter_widget_from_html_core`） | 不跑 JS，读到哪一节要另写；CSS 只支持一部分；Junyu 在浏览器里看到的效果和 App 里会不一样。读本只有图文时可以再考虑 |
| `flutter_inappwebview` | 能逐个拦请求，但稳定版停在 2024-10，之后只有测试版；我们用不到它多出来的功能 |
| 单元从网络下载或远程更新 | 1020c 明确不要；研究中途内容不能变 |
| 让 HTML 自己写 CSP | 靠写稿时记得加，不可靠；由 App 统一加 |

## 后果

- 对研究：登记表 C08 加一句（研究侧做，1020c 第五节）；B07 §5、B13、修订包「App 内固定文字」附件加小读本（研究侧做）。ICF 不改：小读本不收集文字。使用事件多四种类型，过程数据。
- 对开发：新原生组件，合并前必须在 GitHub Actions 打一次 APK、在 Codemagic 打一次 iOS 包，并在 iPhone 和安卓真机按 1020c 第四节测过。服务器端 `functions/usage_events.js` 给新类型盖研究编号；`functions/ops_dashboard.js` 算前台分钟时只看前台／后台两种。
- 对论文：方法部分教育内容一节写"随 App 打包的图文小读本，两组相同；Hybrid 组可就读本内容提问"。

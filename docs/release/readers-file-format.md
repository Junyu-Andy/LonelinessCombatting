# 小讀本文件格式（给写读本的窗口）

> 2026-10-21 第一版。按 App 代码实际接受的写（`lib/features/education/`、`tool/check_reader_html.js`、`tool/add_readers.sh`）。10/21 的 14 篇（readers-1021.zip）就是照这个格式，全部通过。

## 结论

- **交一个 zip。** 里面一个 `manifest.json`，加每篇三个文件：`<id>.html`、`<id>.txt`、`<id>.explain.json`。
- **开发收到后跑一条命令** `tool/add_readers.sh <zip>`：逐篇检查，**过了的才放进 App**，不过的列出原因，不放进去。
- **每篇网页要自成一体**：不连网，图片、样式、脚本都写在文件里。字号用 `var(--fs)`。
- **链接只用下面几种 `peizhu://`**。撳了要么打开 App 的页面，要么换到另一篇；别的链接一律不放。
- **两组看到的网页一字一图一样。** App 只告诉网页两件事：`data-chrome="app"`（两组都有），`data-ask="on"`（只 Hybrid 组）。
- 交之前，自己先跑一次检查（第十一节），看到「通过」再交。

## 一、zip 怎么放

- 文件可以直接放在 zip 最上层，也可以整个放在**一个**文件夹里（例如 `readers/`）。
- 只收这四种文件名：`manifest.json`、`<id>.html`、`<id>.txt`、`<id>.explain.json`。
- 不收、也不会报错的：`__MACOSX/`、`.DS_Store`、`._xxx` 这类电脑自动加的文件。
- 不收、会列出来的：子文件夹里的文件、图片文件、其他名字的文件。
- **整个包拒收**（一个文件都不放）的情况：文件名带 `..`、以 `/` 开头、用反斜杠 `\`；快捷方式（symlink）；加了密码；一个文件解压后大于 8 MB；同一个名字出现两次；不是 zip。
- **默认 zip 就是整套**：放进去之后，App 里只有这个 zip 里通过的篇。所以每次都交全部篇数，不要只交改过的那一篇。（开发有一个 `--keep` 选项可以只换一篇，一般不用。）

例子：

```
readers-1021.zip
└── readers/
    ├── manifest.json
    ├── what_is_loneliness.html
    ├── what_is_loneliness.txt
    ├── what_is_loneliness.explain.json
    ├── how_lonely_am_i.html
    ├── …
```

## 二、manifest.json

一个列表，每篇一项。按 `order` 排在「讀少少」里，按 `part` 分组。

| 字段 | 必须 | 写法 | App 用来做什么 |
|---|---|---|---|
| `id` | 必须 | 编号，规则见第四节 | 文件名、使用记录 |
| `titleZh` | 必须 | 篇名，不能空 | 列表和顶栏显示 |
| `minutes` | 必须 | 正整数 | 列表右边「約 n 分鐘」，顶栏也显示 |
| `order` | 必须 | 整数，越小越前 | 列表顺序（同一个数字时按 id） |
| `part` | 可选 | 1、2、3… | 分组。组标题显示「第一部分：…」 |
| `partTitleZh` | 可选 | 组名，不要写「第一部分」 | 组标题后半句。同一个 `part` 的每一项要写得一样 |
| `icon` | 可选 | Material Icons 名称，小写加下划线 | 列表左边的图标 |

- 没有 `part` 的篇排在最前，没有组标题。
- `icon` 现在 App 认得这 14 个：`help_outline`、`self_improvement`、`tune`、`favorite_border`、`science`、`stairs`、`family_restroom`、`psychology`、`videocam`、`directions_walk`、`local_florist`、`location_city`、`support_agent`、`smartphone`。写别的名字不会出错，但会显示一本书的默认图标（检查会提示）。要新图标，先告诉开发加进 App。
- 其他字段 App 不读，可以有，但不要靠它。
- 篇名和组名也会查电话号码和不准用的字（第七节）。

完整例子（两组、三篇）：

```json
[
 {
  "id": "what_is_loneliness",
  "titleZh": "孤單係咩",
  "minutes": 7,
  "order": 1,
  "part": 1,
  "partTitleZh": "認識孤單",
  "icon": "help_outline"
 },
 {
  "id": "how_lonely_am_i",
  "titleZh": "我有幾孤單",
  "minutes": 7,
  "order": 2,
  "part": 1,
  "partTitleZh": "認識孤單",
  "icon": "self_improvement"
 },
 {
  "id": "small_steps",
  "titleZh": "由一小步開始",
  "minutes": 7,
  "order": 6,
  "part": 2,
  "partTitleZh": "自己同身邊嘅人可以做咩",
  "icon": "stairs"
 }
]
```

10/21 正式的 14 篇见 `assets/readers/manifest.json`。

## 三、每篇的文件

| 文件 | 必须 | 是什么 |
|---|---|---|
| `<id>.html` | 必须 | 老人看到的网页 |
| `<id>.txt` | 必须 | 同一篇的纯文字。Hybrid 组撳右上角「?」问通通时，通通只根据这段回答。规则组不读 |
| `<id>.explain.json` | 可以有 | 每张卡的解释。**这次随包放进去，但 App 还不读、也不显示**（每卡「?」解释面板这次不做）。要求：有效的 JSON（`{…}` 或 `[…]`）、小于 1 MB、有同名 `.html`。里面的电话号码、不准用的字只作提示，不算不通过；以后要显示时再按正式规则查。坏的 `.explain.json` 加入时会被丢掉，那一篇照常放进去 |

三个文件的 `<id>` 一样，也和 manifest 里的 `id` 一样。

## 四、编号（id）规则

- 只用**小写英文字母、数字、`_`、`-`**；第一个字要是字母或数字；最长 48 个字。
- 例子：`what_is_loneliness`、`after_loss`。不可以：`After Loss`、`第一篇`、`_x`。
- 编号一旦用了就不要改（使用记录靠它）。改篇名只改 `titleZh`。
- `zz_test` 开头的编号留给开发测试用，正式包里不要用（CI 会拦）。
- 同一套规则也用于 `data-section` 的节编号。

## 五、data-section 怎么写

- 每一节放在一个有 `data-section="节编号"` 的元素里，例如 `<section id="s1" data-section="s1">…</section>`。
- 节编号按第四节的规则，一篇里不能重复。现在 14 篇都是 `s1`、`s2`、`s3`。
- 至少要有一个 `data-section`。
- App 用它记两件事，**只记编号，不记文字**：
  - 老人打开了哪一节（使用记录 `reader_section`）；
  - 哪几节读过（只存在这部手机，给目录打「✓ 已讀」，列表打「✓ 讀完」）。
- 一次只显示一节的写法（现在 14 篇都是）：不显示的节加 `hidden`，App 只记真正显示出来的那一节。

## 六、大小

- **每个文件要小于 1 MB**（1,048,576 字节）。现在最大的一篇约 60 KB。
- 图片要压小，用 `data:` 写进 html（现在用的是 webp）。
- 整包没有硬上限，但包越大 App 越大，尽量保持现在的大小。

## 七、不可以有的东西（六项检查，白话）

`tool/add_readers.sh` 和 CI 都按这六项查，每篇分开查。

1. **不连外网，不引用别的文件。** 不可以有 `http://`、`https://`、`//` 开头的图片、样式、脚本、链接；不可以 `@import`；`url(...)` 不可以指向外面。图片、样式、脚本也不能引用 zip 里别的文件（App 里载不到），一律写在 html 里。链接只可以是第九节那几种，或页内 `#`。
2. **不联网、不存东西、不让人打字。** 不可以有 `fetch(`、`XMLHttpRequest`、`WebSocket`、`localStorage`、`sessionStorage`、`indexedDB`、`sendBeacon`、`EventSource`、`<form`、`<input`、`<textarea`、`<iframe`、`<object`、`<embed`、`<base`、`tel:`。
3. **没有电话号码。** 连续 8 位数字，或「xxxx xxxx」（中间空格或连字号，全角数字也算），html、txt、篇名都查。
   - 不算电话的：`data:` 图片里的字、SVG 坐标、颜色码；参考资料里「年;卷(期):页码」格式的页码（例如 `2015;63(10):2014-2022`）。
   - 「防騙易」18222 是 5 位数字，不触发；Junyu 已同意第 9 篇保留（decisions-log 10/21）。
4. **正文没有这几个字眼：**「AI」「模型」「機械人」「版本」「組」（简体「机械人」「组」也查）。正文包括：看得到的字、图片说明（`alt`、`title`、`aria-label`）、`<script type="application/json">` 里网页会显示的字、`.txt`、篇名和组名。注释、普通 `<script>`、`<style>` 里的不算。「組」很常见（小組、組織），要换说法。
5. **三样对得上。** `.html` 有 `data-section`；有同名 `.txt`；`manifest.json` 里有这个 `id`；manifest 里的每个 `id` 都有 `.html` 和 `.txt`；`peizhu://reader/open?id=` 指向的那一篇也要在包里。
6. **每个文件小于 1 MB。**

另外两条（也算不通过）：页面要用到 `var(--fs)`（第八节）；`peizhu://explain` 只可以放在 `class="ask"` 的按钮上（第九节）。

一篇不通过，**只有那一篇**不放进去；指向它的「讀下一篇」那一篇也会跟着不放（免得撳了打不开）。

## 八、字号：--fs

- App 在页面里设 CSS 变量 `--fs`，值是老人在 App 里选的字号倍数：五档 1.06、1.12、1.18、1.24、1.30（特大）。
- 字号一律写成「基本大小 × `var(--fs, 1)`」，例如 `font-size: calc(17px * var(--fs, 1));`。其他用 `em` 跟着走。
- 不用 `--fs` 的页面不通过检查（App 的字号对它不起作用）。
- App 会另外关掉缩放（双指、双击都不能放大），关掉长按选字。
- 要在 360 宽的手机上、`--fs` 1.30 时不横向滚动。开发的截图脚本会逐篇查（现在 14 篇都过）。

## 九、链接（peizhu://）

**规矩：网页里每一个 `peizhu://` 链接 App 都要接得住，撳了不会开浏览器，也不会没反应。** CI 有测试逐个扫描包里的文件。

| 链接 | 撳了之后 | 两组 |
|---|---|---|
| `peizhu://cta/small_action` | 今日嘅小邀請（今日小行動） | 两组 |
| `peizhu://cta/plan` | 我嘅計劃，新建（各组自己的计划页） | 两组 |
| `peizhu://cta/thought` | 望一望心入面 | 两组 |
| `peizhu://cta/chat_siu_yan` | 同小欣傾偈（小欣聊天页） | 两组 |
| `peizhu://reader/open?id=<id>` | 在同一个阅读页换成那一篇（「讀下一篇」）；先存好这一篇读到哪里；返回仍回「讀少少」 | 两组 |
| `peizhu://explain?card=<…>` | **这次不做**。只可以放在 `class="ask"` 的按钮上；网页只在 `data-explain="on"` 时显示这些按钮，App 不设，所以看不到、撳不到 | — |

- 从这些页面返回，回到阅读页原处。
- 其他链接（网址、`tel:`、`mailto:`、别的 `peizhu://`）检查不通过；万一漏进去，App 也会拦下，什么都不打开。
- 10/21 的 14 篇里共有：`chat_siu_yan` 28 个、`small_action` 10 个、`thought` 3 个、`reader/open` 13 个（第 1 至 13 篇各一个，第 14 篇没有下一篇）、`explain` 72 个（都看不到）。`plan` 没有用到。

## 十、App 和网页之间的接口

App 用自己的顶栏（白底、深色字、主色按钮），网页不画顶栏。

**App 给网页的：**

- `<html data-chrome="app">`：两组都有。网页看到它就收起自己的「‹ 目錄」条。
- `<html data-ask="on">`：只 Hybrid 组有。网页看到它就在「睇完」一块显示那句「內容有唔明，可以撳右上角「?」問通通」。规则组没有这句。这是登记表 C08 的一部分。
- `data-explain`：App 不设。
- `--fs`（第八节）。
- 打开时，App 在网页自己的脚本之后调用 `window.peizhuReader.setRead(["s1","s2"])`，告诉网页上次读过哪几节。

**网页要提供的（`window.peizhuReader`）：**

| 名字 | App 什么时候用 | 要返回 |
|---|---|---|
| `back()` | 老人撳顶栏「‹」或手机的返回键 | `true`：网页已从某一节回到目录（App 留在阅读页）；`false`：已经在目录（App 关掉阅读页，回「讀少少」） |
| `current()` | 打开时 | `{view:'toc' 或 节编号, index, total, title}` |
| `setRead(ids)` | 打开时 | 目录给这些节打「✓ 已讀」；三节都读过，目录显示「睇完」一块和「讀下一篇」 |
| `readIds()` | 每次换页、离开时 | 读过的节编号列表。离开某一节就算读过 |

**网页要发的事件：** 每次换到目录或某一节，`window.dispatchEvent(new CustomEvent('peizhu:view', {detail: {view, index, total, title}}))`。App 用它换顶栏中间的字：在目录显示篇名和「約 n 分鐘」，在某一节显示「第 2／3 節」和篇名。`title` App 不用、不记。

**不要用的名字：** `window.PeizhuReader`（大写 P）是 App 自己的通道，网页不要定义它。

**App 另外加的（不用写）：** 安全规则（只准用页面自己的东西）、禁止缩放、`--fs`、一小段记录节的脚本。

## 十一、交之前自己查

在仓库里跑：

```bash
node tool/check_reader_html.js 放文件的文件夹
```

逐篇显示「通过」或「不通过」和原因，最后一行「小讀本检查通过：N 个单元」才算过。

开发加入时跑：

```bash
tool/add_readers.sh readers.zip
```

退出码：0 全部通过；2 有篇不通过（通过的已放进去）；1 包没有处理（例如不安全），什么都没改。

## 十二、相关文件

- 检查：`tool/check_reader_html.js`；加入：`tool/add_readers.sh`（逻辑在 `tool/add_readers.js`）；两者的测试在 `test/reader_html_check/`。
- 截图和逐篇在浏览器里的检查：`tool/readers_shots_1021.sh`。
- App：`lib/features/education/data/reader_html.dart`（加工网页、链接）、`reader_unit.dart`（manifest）、`reader_read_marks.dart`（读过的节）、`presentation/pages/reader_page.dart`（阅读页和顶栏）、`education_library_page.dart`（「讀少少」列表）。
- 决策：0056（小讀本用 WebView）、0070（原生顶栏和读过的节）。

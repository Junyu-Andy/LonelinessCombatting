# 0070：小讀本用 App 自己的顶栏，「?」只给 Hybrid；读过哪几节只存在手机里；14 篇随冻结构建进包

- 日期：2026-10-21
- 状态：已采纳（decisions-log 10/21 第 109–113 条；交接「开发窗口交接-1021-小读本」T-R1 至 T-R5、T-R4b）
- 影响范围：pilot / phase_b × 两组（网页内容两组相同；右上角「?」问通通只在 Hybrid 组，沿用登记表 C08）
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-readers-1021`（并入冻结合并分支 #151）；在 0056 之上补充，0056 其余不变

## 背景

产品窗口 10/21 交来 14 篇小讀本（readers-1021.zip）。新网页每篇分目录和三节，一次只显示一节，自己带顶栏；要 App 换上原生顶栏，并告诉网页哪几节读过。0056 时阅读页只有一个底部「問下通通」按钮，没有顶栏，也没有"读过"的记录。Junyu 10/21 定：14 篇全部进冻结版，「讀下一篇」要做，每卡「?」解释不做，不加新开关。

## 决定

1. **列表**：「讀少少」的小讀本按 manifest 的 `part` 分组（「第一部分：認識孤單」），每行左边 manifest 指定的 Material 图标（App 内固定的 14 个名字，其他显示默认书本），右边「約 n 分鐘」；三节都读过的加「✓ 讀完」（图标加文字，不用 emoji）。
2. **顶栏**：App 画，白底、深色字、主色按钮。左「‹」先问网页 `peizhuReader.back()`：true 留在阅读页（网页已回目录），false 关掉回列表。手机返回键在某一节时同样先问网页；在目录时直接关（和 back() 返回 false 的结果一样），这样 iPhone 左缘右滑在目录页也能用。中间字跟网页的 `peizhu:view` 换：目录时篇名和「約 n 分鐘」，某一节时「第 i／n 節」和篇名。右边圆形「?」只 Hybrid 组有，打开通通的文章问答（原来页底的「問下通通」按钮拿走）；规则组同一位置留空，布局一样。App 给网页设 `data-chrome="app"`，Hybrid 再设 `data-ask="on"`；不设 `data-explain`。
3. **读过的节**：网页离开一节就算读过；App 每次换页时收到 `readIds()`，按篇存在手机里（`shared_preferences`，不上传），下次打开在网页脚本之后调 `setRead(ids)`。三节都读过 = 讀完。研究记录仍只用现有 `reader_section`（不加新表）；隐藏的节不再被误记。
4. **小欣按钮**：新链接 `peizhu://cta/chat_siu_yan` 打开小欣聊天（`CheckInPage`，和首页小欣卡同一个入口，两组都有）。`reader_cta` 的 `cta` 多一个值，规则同步。
5. **讀下一篇**：`peizhu://reader/open?id=` 在同一阅读页换成那一篇，先存当前篇读过的节，记一次 `reader_close` 和新篇的 `reader_open`；返回仍回列表。
6. **每个 `peizhu://` 都要接得住**：检查脚本只放行 App 处理的链接，CI 测试逐个扫描打包的文件；`peizhu://explain` 只在隐藏的 `class="ask"` 按钮上。
7. **加入流程**：`tool/add_readers.sh <zip>` 把交来的 zip 当不可信数据处理，逐篇检查，只放通过的篇。格式见 `docs/release/readers-file-format.md`。
8. 不加开关（仍在 `htmlReadersEnabled` 之下，生产值 10/21 定为开）；`--fs` 不变。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 网页自己画顶栏，App 只管返回 | 「?」要按组别显示，网页不能知道组别（两组网页必须一样） |
| 读过的节存到 Firestore | 交接 T-R3 要求不加新表；研究用的 `reader_section` 已经够 |
| 关闭时才问网页 `readIds()` | 安卓返回手势、App 被杀时可能来不及；改为每次换页都随事件带上，关闭时再问一次 |
| `setRead` 等页面加载完由 App 调 `runJavaScript` | 有时机问题；改为在网页自己的脚本之后插一段脚本，效果相同、不靠时机 |

## 后果

- 对研究：两组网页一样；组间差异仍只有 C08 的「?」问通通（Hybrid 另有 `data-ask` 那一句提示）。登记表 v10.17 记 C08 一行。使用事件的 `cta` 多 `chat_siu_yan`。读过的节只在手机上，换手机会丢，只影响打勾。
- 对开发：`reader_page.dart` 重写顶栏和返回；`reader_html.dart` 加接口；新 `reader_icons.dart`；`firestore.rules` 一处。合并后部署规则。iPhone 左缘右滑只在目录页能返回，在某一节里不能（要先回目录），用顶栏「‹」。真机要测：`back()`、`peizhu:view`、`setRead` 时机、`readIds()`。
- 对论文：方法部分教育内容一节写"14 篇随 App 打包的图文小读本，分三部分，两组相同；Hybrid 组可撳「?」就该篇提问"。

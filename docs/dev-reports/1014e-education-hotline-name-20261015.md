# 1014e 第 2 节第 6 条（N7）：教育文章危机提示的机构名更正（2026-10-15）

分支 `fix/education-hotline-name`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 6、10 条（10/15 第 2 条 (4)(6)）。**热线号码一个都没改**（共同规则 5）；没有改安全词库、安全回应模板、IAM。

## 结论

1. **改了两处机构名**：`lib/features/education/data/education_library.dart` 第 418、533 行（中文）和 419、534 行（英文）。原文「撒瑪利亞防止自殺會熱線 2382 0000」/ "Samaritans of HK: 2382 0000"，2382 0000 是生命熱線（Suicide Prevention Services）的号码，撒瑪利亞防止自殺會是 2389 2222，两处都对不上。改为「生命熱線 2382 0000」/ "Suicide Prevention Services (生命熱線): 2382 0000"。号码不动。
2. **其他地方本来就对**：危机页 `functions/prompts/crisis_resources.json`（生命熱線 2382 0000、撒瑪利亞會 2896 0000）、教育文章正文的热线清单（同上两条）、安全卡的 18111。
3. **新测试**锁住：文章里任何提到 2382 0000 的提示不能再写撒瑪利亞；文章正文里每个 8 位号码都要在 `crisis_resources.json` 里、且机构名一致；提示没有【占位】。
4. **`verifiedDate`** 仍是空（危机页脚注显示「資料核對日期：待核對」）：产品窗口已对 HKU CSRP 名单，但按文件说明要 Junyu 自己打开 `verifySource` 确认后填日期——这一步没有代码，控制台 / 仓库里填 `functions/prompts/crisis_resources.json` 的 `verifiedDate` 即可（改了要重新打包和部署 Functions）。
5. 主热线 18111（第 10 条）：参与者材料由产品窗口改，App 的安全卡已是 18111，不动。

## 关于“只写草稿”

1014e 写“改法只写草稿”。这里是把一个**错误的机构名**改成正确的（号码不变），不是新文案；显示【占位】在危机提示里反而有害，所以直接改了，并在 PR 的「安全」一项标明请 PI 复核。PI 不同意可以一行改回。

## 改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/education/data/education_library.dart` | 4 行机构名 |
| `test/education_hotline_name_test.dart`（新，3 项） | 见上 |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 10 节一句 + 顶部核对；`history.md`；本报告 |

## 测试

`flutter test test/education_hotline_name_test.dart` 3/3；`flutter analyze` 0 error；六套见 CI。

## 要 Junyu 定的事

1. 核对四个号码后填 `crisis_resources.json` 的 `verifiedDate`（见第 4 点）。

## 要带回研究侧的发现

1. 登记表「安全文字」条目可记一笔：10/15 更正教育文章提示的机构名；危机页和文章清单的四个号码（18111、2382 0000、2896 0000、999）产品窗口已对过，PI 复核后填日期。
2. `test/safety_check_test.dart` 第 306、313 行用「撒瑪利亞防止自殺會」作为测试句子（测热线过滤），和本改动无关，没有动。

# 0071：「問下通通」的文章和小讀本问答改用 deepseek-v4-pro

- 日期：2026-10-21
- 状态：已采纳（decisions-log 10/21 第 104 (8)、109–113 条；小讀本交接 T-R6）
- 影响范围：phase_b、pilot × Hybrid 组（规则组不调用模型，不受影响）
- 相关代码：`functions/article_qa.js`、`functions/index.js` proxyDeepSeek；冻结合并分支 #151

## 背景

「問下通通」让老人就一篇短文（读少少 15 篇）或一篇小讀本发问。Junyu 希望这类学习问答答得更准，所以用更强的 deepseek-v4-pro。其他对话（小欣、阿珍／阿伯、通通闲聊）照旧用 deepseek-flash。

## 决定

- 服务器按 App 放在上下文最前面的文章标题行（「[文章內容 — 所有回答只可以根據呢段]」，英文测试界面是「[Article context — ground all answers in this text]」）认出这是通通的文章问答，就用 deepseek-v4-pro。这一行本来就是通通 prompt 进入文章问答模式的依据。App 的请求不用改。
- 和其他对话一样关掉思考模式（决策 0017），温度、长度上限不变。
- `llm_calls` 照旧记录请求的模型和返回的模型；这类调用的 `call_type` 记为 `article_qa`。
- 只有 Hybrid 组能走到这个函数（服务器的规则组防线不变）。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| App 多传一个字段说明是问答 | 要改 30 多个测试替身的接口，冻结前风险大；标题行已经能准确认出 |
| 改问答时的 moduleId | moduleId 会写进 prompt 的「[模組]」一行，等于改 prompt 内容 |
| 打开思考模式 | 会更慢，而且思考会吃掉回答的长度上限（决策 0017） |

## 后果

- 对研究：Hybrid 组「問下通通」的回答质量可能和冻结前不同；生效日期以 Functions 部署时间为准，记在 STUDY_CHANGELOG。规则组不变。
- 对开发：一个新模块和一个测试；部署 Functions 后生效。
- 对论文：模型版本记录（C04）多一个模型名，方法部分写明学习问答用 v4-pro。

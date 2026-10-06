# 0016：DeepSeek 请求改为 `deepseek-flash` 并关闭思考模式，实际用的模型不变

- 日期：2026-10-06
- 状态：已采纳
- 影响范围：所有 cohort（pilot / phase_a / phase_b）× Hybrid 组（规则组不调用 LLM）
- 相关代码：`functions/index.js` 顶部的 `DEEPSEEK_MODEL`、`DEEPSEEK_THINKING`；测试 `functions/test/deepseek_request_test.js`

## 背景

代码一直请求 `deepseek-chat`。2026-10-06 实测：

- DeepSeek 的模型列表（`/models`）里只有 `deepseek-flash`（DeepSeek-V4.1-Flash）和 `deepseek-v4-pro`，已经没有 `deepseek-chat`。
- 请求 `deepseek-chat` 时，返回的 `model` 字段是 `deepseek-flash`，且不"思考"（没有 reasoning token）。也就是说，参与者现在拿到的回复其实来自 DeepSeek-V4.1-Flash，不是 `docs/dev/architecture.md` 原来写的 DeepSeek-V3。
- `deepseek-chat` 是旧名字，DeepSeek 随时可能停用。停用后，所有 Hybrid 组的对话、转介判断、记忆整理都会报错。

## 决定

- 三处调用（`proxyDeepSeek` 对话、`referralJudgement` 转介判断、`callDeepSeekJson` 记忆整理）都改为请求 `deepseek-flash`，并加 `thinking: {type: "disabled"}`。
- 关闭思考是必须的。直接写 `deepseek-flash` 而不关思考，模型默认先"思考"再回答。实测：
  - 转介判断这类 `max_tokens: 200` 的 JSON 调用，200 个 token 全部用在思考上，返回空内容；
  - 普通对话每次多出 100 多个思考 token，费用和延迟都增加；
  - 思考模式下 `temperature`、`top_p` 不起作用，各 agent 的温度设置会失效。
- 改后实测和 `deepseek-chat` 完全一致：返回的模型都是 `deepseek-flash`，没有思考 token，输入 token 数相同，同一个 JSON 抽取请求输出逐字相同。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 维持 `deepseek-chat` 不动 | 旧名字随时可能停用，停用当天 Hybrid 组全部失效 |
| 只改名字，不关思考 | 转介判断返回空；温度失效；费用和延迟上升。等于悄悄换了干预内容 |
| 改用 `deepseek-v4-pro` | 是另一个模型，回复风格、延迟、费用都会变，属于干预内容的改动，需要研究侧另行决定 |

## 后果

- 对研究：
  - 实际用的模型没有变，参与者感受不到差别。但研究文件里写的模型名要更正：参与者拿到的回复来自 DeepSeek-V4.1-Flash（非思考模式），不是 DeepSeek-V3。protocol、ICF、DMP、HREC 材料里凡写"DeepSeek-V3"或"deepseek-chat"的地方要对一下。
  - 登记表 C03 写的是 `deepseek-chat`，需要研究侧改成 `deepseek-flash`（思考关闭）。开发侧不改登记表。
  - `deepseek-flash` 也不是锁定版本，DeepSeek 升级时同一个名字可能指向新模型。C04（每次调用记录返回的 `model` 和 `system_fingerprint`）仍然必要。
- 对开发：改动很小，三处请求体各加一行、改一行。新增静态测试：每处调用都必须带这两个字段，任何服务器代码不得再请求 `deepseek-chat`。要部署 Functions 才生效。
- 对论文：Methods 写明模型为 DeepSeek-V4.1-Flash（非思考模式），经官方 API 调用、版本无法锁定；局限里保留"模型可能被供应商更新"一句。

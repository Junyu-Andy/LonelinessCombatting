# 0016：每次调用 DeepSeek 都在 `llm_calls` 记一条，记下返回的 `model`

- 日期：2026-10-06
- 状态：已采纳
- 影响范围：所有 cohort × Hybrid 组（规则组不调 LLM，不产生记录）
- 相关代码：`functions/llm_log.js`，分支 `feature/model-logging`（SPEC:C04）

## 背景

研究侧已定：继续用 DeepSeek 官方 API。请求的模型名见决策 0017（现在是 `deepseek-flash`，思考关闭）。DeepSeek 的模型名都没有固定日期的版本，名字背后的模型会被换掉，我们锁不住。之前只有聊天轮次在 `turns` 里由 App 记了 `model`；记忆抽取、转介判断没有记，App 没写成功的轮次也没有。论文要能说清楚每段时间实际用的是哪个模型。

## 决定

- 服务器上所有 DeepSeek 请求都走同一个函数 `deepSeekChat`（`functions/llm_log.js`），每次调用后写一条 `llm_calls`。出错也写。
- 字段只有：时间（UTC）、调用类型、agent（只接受三个陪伴者的 id，其他存空）、研究编号（Firebase uid）、请求的模型名（从实际请求体读）、返回的 `model`、`system_fingerprint`（用来发现同名模型被换）、prompt / completion / 思考 token 数、HTTP 状态码、延迟、是否出错。**不存 prompt 和回复原文。**
- 每次请求有超时（比所在函数的时限短），超时也记一条 `error: true`。写日志最多等 2 秒，超时只打服务器日志，不耽误老人收到回复。
- `llm_calls` 是独立的顶层集合，只有服务器能写，App 不能读也不能写。
- 规则组的服务器防线不变：被拒绝的请求根本到不了 DeepSeek，所以也不写记录。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 继续只靠 App 写进 `turns` 的 `model` | 只覆盖聊天；App 断网或写失败就丢；记忆抽取和转介判断完全没有 |
| 放在 `users/{uid}/llm_calls` 子集合 | 用户子集合默认本人可读写，要另开规则；顶层集合和 `safety_events` 一样，更容易整体导出 |
| 同时存 prompt hash 或模块名 | 任务单只要求上面这些字段；调用类型已经能区分对话、总结、问答等 |

## 后果

- 对研究：
  - 可以按日期统计实际返回的模型和 `system_fingerprint`；token 数可用于成本估算。
  - **研究编号目前就是 Firebase uid 原值**，没有另外编码。这是假名化的个人数据，要写进 DMP（存在哪里、保存多久、退出研究时是否删除）。
  - **只有 Hybrid 组会有 `llm_calls` 记录。** 某个 uid 有没有记录就等于告诉别人他在哪一组。揭盲前不能把这个集合原样导出给盲法人员。
- 对开发：每次 LLM 调用多一次 Firestore 写入（几十毫秒）。盲法导出（`blindedDataExport`）暂未包含 `llm_calls`；以后要加，必须先想好怎么不泄露分组（backlog 第 21 项）。
- 对论文：Methods 里写「每次调用记录 DeepSeek 返回的模型标识」；局限里提模型版本无法锁定。

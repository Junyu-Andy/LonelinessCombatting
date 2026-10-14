# 记忆 v1 验收测试集（T4，2026-10-06）

结论先说：这里是 30 段合成粤语对话、每段的标准答案，以及在 Firebase 模拟器上跑真实服务器代码的脚本。结果和判定写在 `docs/dev-reports/T4-memory-acceptance-20261006.md`。

## 文件

| 位置 | 内容 |
|---|---|
| `dialogues/D01–D30.json` | 合成对话。10 位虚构长者（P01–P10），每位 3 段，分给三个陪伴者。全部自己编写，没有用任何真实对话 |
| `gold/D01–D30.json` | 标准答案（运行前写在工作区，运行后未改；与结果同时提交，git 无法证明先后）：应抽取的事实（`required` = 必须有，其余 = 可以有）、应有的跟进日期、不应进入记忆的内容（`forbidden`）、应被取代的旧事实、前后矛盾 |
| `run_eval.js` | 跑一轮：分组 B 检查 → 30 段抽取 → 跨陪伴者泄露检查 → 删除检查 |
| `score.js` | 按标准答案打分，生成 `results/<run>/score.json` 和逐条判定 `appendix.md` |
| `adjudication/<run>.json` | 标准答案判不了的条目的人工判定（附理由）。研究侧可以直接改这里再重算 |
| `results/ledger.json` | 每段对话累计调用 DeepSeek 的次数（上限 3 次，脚本强制） |

「今天」固定为 **2026-10-07（星期三，香港时间）**。D07、D17、D26 设在凌晨（香港 01:30 / 03:15 / 05:45），那时 UTC 还是 10-06，用来检查时区。

## 怎么跑

```bash
cd functions && npm ci && cd ..
npm i -g firebase-tools           # 需要 Java 21

# 1. 先用「标准答案当模型」跑一次，检查脚本本身（不联网）
firebase emulators:exec --only firestore --project demo-t4memeval \
  "node tool/memory_eval/run_eval.js --mode=stub --run=stub"
node tool/memory_eval/score.js --run=stub

# 2. 真实调用 DeepSeek（每段 1 次；Node 的 fetch 要加 NODE_USE_ENV_PROXY=1 才走代理）
NODE_USE_ENV_PROXY=1 firebase emulators:exec --only firestore --project demo-t4memeval \
  "node tool/memory_eval/run_eval.js --mode=live --run=run3"
node tool/memory_eval/score.js --run=run3          # 缺人工判定时会列出来并停下
```

- 项目名必须是 `demo-` 开头：模拟器保证不会连到真实项目。
- 密钥用占位值即可（`DEEPSEEK_API_KEY` 不设时脚本自动填 `placeholder`）。
- 聊天回复（`proxyDeepSeek`）**不会**真的发出去：脚本只截下要发送的 system prompt 来检查记忆块，然后本地回一句假回复。
- 每次改抽取 prompt 或换模型都应重跑（见 `docs/dev/memory-and-entry-spec.md` 3.1）。

## T10 重跑（2026-10-07）

- 结果：`results/t10_run1`–`t10_run4`（真实 DeepSeek），`t10_run3_replay`、`t10_run4_replay`（用第 3、4 轮录下的模型输出重放，不联网）。报告 `docs/dev-reports/T10-memory-fix-20261007.md`。
- 调用次数另记在 `results/ledger_t10.json`（第 1、2 轮）和 `ledger_t10_final.json`（第 3、4 轮），每段每批不超过 3 次。
- 新参数：`--ledger=<文件名>`；`--mode=replay --from=<run>`。`score.js --review-summaries` 要求每条摘要都有人工判定（摘要层也评）；编造按类型分开（`hypothetical_joke` 假设或玩笑、`misattributed` 陪伴者的话或被否认的猜测、`invented` 凭空）。
- 给第二位判定人的表：`second_rater_t10.csv`，由 `make_rater_csv.js` 生成，每条记忆一行，判定栏留空，不含第一位判定人的结果。

```bash
NODE_USE_ENV_PROXY=1 firebase emulators:exec --only firestore --project demo-t4memeval \
  "node tool/memory_eval/run_eval.js --mode=live --run=t10_run5 --ledger=ledger_t10_next.json"
node tool/memory_eval/score.js --run=t10_run5 --review-summaries
```

## T31 抽取 prompt v3 分层（2026-10-10）

- 脚本 `run_v3_layers.js`：用 v3 跑 30 段一次，按服务器规则（`functions/memory.js` `layerFor`）列出每条事实进共享层还是私有层。不经 Firestore，每段从空记忆开始；「唔好記住」的段落不调用模型。
- 结果 `results/t31_v3_run1/`（`layers.md` 逐条，`raw.json` 原始输出）；调用次数记在 `results/ledger_t31.json`（每段上限 3 次）。`--mode=replay` 用录下的输出重算，不联网。报告 `docs/dev-reports/T31-memory-layers-20261010.md`。

```bash
NODE_USE_ENV_PROXY=1 node tool/memory_eval/run_v3_layers.js --run=t31_v3_run1
node tool/memory_eval/run_v3_layers.js --run=t31_v3_run1 --mode=replay
```

## 不进 CI 的原因

它会真实调用 DeepSeek，而且有一部分要人工判定。不需要模型的那几项（规则组零抽取零注入、分层共享不泄露、删除后不注入、香港日期）另写成 `functions/test/memory_acceptance_emulator_test.js`，CI 会跑。

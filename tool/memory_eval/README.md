# 记忆 v1 验收测试集（T4，2026-10-06）

结论先说：这里是 30 段合成粤语对话、每段的标准答案，以及在 Firebase 模拟器上跑真实服务器代码的脚本。结果和判定写在 `docs/dev-reports/T4-memory-acceptance-20261006.md`。

## 文件

| 位置 | 内容 |
|---|---|
| `dialogues/D01–D30.json` | 合成对话。10 位虚构长者（P01–P10），每位 3 段，分给三个陪伴者。全部自己编写，没有用任何真实对话 |
| `gold/D01–D30.json` | 标准答案，**跑之前写好**：应抽取的事实（`required` = 必须有，其余 = 可以有）、应有的跟进日期、不应进入记忆的内容（`forbidden`）、应被取代的旧事实、前后矛盾 |
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

## 不进 CI 的原因

它会真实调用 DeepSeek，而且有一部分要人工判定。不需要模型的那几项（规则组零抽取零注入、分层共享不泄露、删除后不注入、香港日期）另写成 `functions/test/memory_acceptance_emulator_test.js`，CI 会跑。

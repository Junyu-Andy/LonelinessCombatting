# 记忆使用画像（T16，2026-10-07）

结论先说：这里是 4 种合成老人画像、在 Firebase 模拟器上模拟 4 周使用的脚本，以及统计脚本。结果写在 `docs/dev-reports/T16-memory-profiles-20261007.md`。

## 文件

| 位置 | 内容 |
|---|---|
| `profiles.js` | 4 种画像（全部虚构，电话、地址、身份证号码都是假的）：每次会话的日期、陪伴者、轮数，以及要追踪的「固定台词」 |
| `run_profiles.js` | 跑一种画像的 4 周。陪伴者回复、记忆抽取、摘要、注入都走真实服务器代码（`proxyDeepSeek`、`memoryEndSession`）和真实 DeepSeek |
| `analyze.js` | 统计，生成 `results/<run>/summary.json` 并打印表格 |
| `results/pilot/` | 试跑（P1 全部、P2 前 2 次会话） |
| `results/full/` | 正式结果，每种画像一个 JSON（含全部对话、每次调用的 token 和延迟、最终记忆） |

## 哪些是真实调用，哪些是脚本

- **真实**：陪伴者每一轮回复（`proxyDeepSeek`，内含记忆注入）；每次会话结束的抽取和摘要（`memoryEndSession`）。
- **脚本**：老人一方。`profiles.js` 里的固定台词原样放进对话；其余老人台词每次会话用 **1 次** DeepSeek 调用整段生成（调用类型 `elder_script`，不算产品用量）。老人台词不会根据陪伴者的回复调整。
- 模仿 App：记忆缓冲区最多 20 条消息（`lib/core/agent_context/agent_context_service.dart` 的 `bufferCap`），离开聊天页时调 `memoryEndSession`。
- 抽取失败时按 `memorySweep` 的方式重试（同一个 `processExtraction`）；没有直接调用 `memorySweep`，因为它会碰到并行跑的其他画像。

## 怎么跑

```bash
cd functions && npm ci && cd ..
npm i -g firebase-tools            # 需要 Java 21
firebase emulators:start --only firestore --project demo-t16memprof &

export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 NODE_USE_ENV_PROXY=1
node tool/memory_profiles/run_profiles.js --profile=P1_light --run=pilot --max-calls=60
node tool/memory_profiles/run_profiles.js --profile=P3_heavy --run=full --max-calls=1350
node tool/memory_profiles/analyze.js --run=full
```

- `--max-calls` 是这个进程最多调用 DeepSeek 的次数，到了就停并在结果里写 `stopped`。
- 项目名必须 `demo-` 开头，模拟器保证不连真实项目。密钥用占位值，代理会换上真实密钥。
- 「今天」是模拟时钟：第 0 天 = 2026-10-07（香港时间）。

# 备份 PILOT 和 PB- 的 agent_contexts（只读）

> 2026-10-20 第一版（1020j 第一节 (3)）。`tool/export_agent_contexts.js`。

## 结论

- 把 PILOT- 和 PB- 账号在 `users/{uid}/agent_contexts` 里的内容，导出到你 Mac 上的一个文件。只读，不写回 Firestore。
- 要知道：App 每次会话结束时，会把这次的原话折叠成一段摘要，然后**清空**原话。所以这里通常只有每位陪伴者的摘要、人名地名、话题线索；只有正在进行、还没结束的会话，才有原话。
- 文件里有对话内容：只放在你的电脑上（开着 FileVault 加密），不要发邮件，不要放进仓库。

## 怎么跑

新开一个终端，在仓库根目录。看板的只读钥匙就够，管理钥匙也可以：

```bash
cd ~/dev/LonelinessCombatting
export GOOGLE_APPLICATION_CREDENTIALS=~/dev/keys/dashboard-viewer.json
NODE_PATH=functions/node_modules node tool/export_agent_contexts.js \
  --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
```

终端只显示每个编号有几份文档、缓冲区有几轮、有几份摘要，不显示内容。文件默认存到 `~/dev/backups/agent_contexts_<香港时间>.json`，只有你能读。

- 换位置：加 `--out=<文件路径>`。路径不能在仓库里面。
- 换编号前缀：加 `--prefix=PILOT-,PB-,RCT-`。

## 读了什么

- `enrollments`：只取研究编号（字段投影），用来挑出 PILOT- 和 PB-；
- `users/{uid}/agent_contexts/*`：整份，这就是要备份的内容。

不读序列、`randomization_state` 和分配日志。

## 测试

`functions/test/export_agent_contexts_emulator_test.js`：模拟器加合成账号，CI 的模拟器测试会自动跑。

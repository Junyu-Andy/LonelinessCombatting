# Phase A 基线版 — 版本钉死表（V-1，进 Manual §13）

> 由 `tool/export_spec_inputs.py` 生成，日期 2026-09-16，仓库 HEAD `c80a2ab`。 参与者 1 入组前重新运行一次并把本表贴进 Manual。

* appVersion `1.0.0` · buildNumber `3` · lexiconVersion `v5-2026-09`
* **promptBundleHash** `e45bf221b5a470242e2f11f151b7aae12086d336edc5bf1dff0608038610510d`（前 8 位 `e45bf221`，关于页可核对）
* 词条数：acute 160 · moderate_interrupt 48 · moderate_review 19 · low 42

| 工件 | 路径 | commit | SHA-256 |
| --- | --- | --- | --- |
| siu_yan_v1.txt | `functions/prompts/siu_yan_v1.txt` | `b0a4503` | `7f77797921ed36086abcd1740bd40d0edd6c205509cb9a027172316b5ec78290` |
| ah_jan_ah_bak_v1.txt (rev 2026-09) | `functions/prompts/ah_jan_ah_bak_v1.txt` | `b0a4503` | `8efcae4cd46ba28f219bb0e49c6f533d5877950ffb21da5e29c8a73e148d6347` |
| tung_tung_v1.txt | `functions/prompts/tung_tung_v1.txt` | `b0a4503` | `251584dc7f1e503d63dc81e78b823e541342a75b9f7ed8b88d4457053bc08ecc` |
| context suffix 模板（persona_resolver.dart 输出格式 + V-2 注入） | `docs/prompts/context_suffix_template.txt` | `uncommitted` | `a068c471634e6577a47eec379578334318d100df228ca1fed4e416c0702b2a22` |
| safety_acknowledgements.json | `functions/prompts/safety_acknowledgements.json` | `77a378b` | `96fd03c84e3ece63216420de7e8ae60600daf2d798fde45865fe4075ab2db218` |
| crisis_resources.json（S-4，号码待 PI 核对） | `functions/prompts/crisis_resources.json` | `uncommitted` | `95c3e56aa879e960e089072afae5c6b83292b9d55a5346a71b085dd1d29f0c66` |
| distress_detector.dart 词表（v5-2026-09） | `lib/core/safety/distress_detector.dart` | `449dfff` | `079af7a7741614501950f51f3c1537c3bc5e2bdccf9e6a59daf7001ead0b4cc7` |
| summariser prompt（rolling_summary_compiler.dart，LLM 生成） | `lib/core/agent_context/rolling_summary_compiler.dart` | `2a3eb5d` | `7c40aba941ac663d9028f4e959dceb7b8c23e325f3818ff2f583e1f15a12f026` |
| fallback 文案 JSON | `assets/config/llm_fallback_messages.json` | `uncommitted` | `2a495b99b4d715e5a745acaeb2a174c13b05d823a38d2ff18f911f63bc2e799c` |
| functions/index.js（proxyDeepSeek：temperature / max_tokens / top_p / stripPII） | `functions/index.js` | `b2cad9d` | `498542fcf393f991b7b46aeffe28e8da7f49d50b1c7c867d022e90bfcac140c3` |
| 三个 temperature | `functions/index.js` | `b2cad9d` | siu_yan 0.7 / ah_jan_ah_bak 0.5 / tung_tung 0.85 |

promptBundleHash 计算方式：按固定顺序（三份 prompt → suffix 模板 → safety_acknowledgements.json → crisis_resources.json → llm_fallback_messages.json）对每个文件拼接 `路径\n` + 原始字节 + `\n` 后取 SHA-256。 `test/phase_a_version_pin_test.dart` 用同一配方复算，生成值过期即测试失败。

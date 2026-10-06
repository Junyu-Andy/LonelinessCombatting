# 补充：安全回应、热线和 AI 失败时的后备文字

**结论**：任务单没有单列，但这些是老人会看到的固定文字，一并导出。
- 安全回应模板和热线：两组相同（`functions/prompts/safety_acknowledgements.json`、`crisis_resources.json`，App 和服务器读同一份）。
- AI 失败时的后备句（`assets/config/llm_fallback_messages.json`）：**只有 Hybrid 组**会看到，规则组不调用 AI。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`
（`lib/main.dart` 第 115 行也传 `Locale('zh')`）。所以 `isEn ? 英文 : 中文` 和 `…Zh / …En` 成对的文字里，**只有中文版会显示**。
英文版照样导出，老人看不到。`app_zh_Hant_HK.arb` 虽然编译进去了，但 app 从不选 `zh_Hant_HK`，实际用的是 `app_zh.arb`；
本文件的内容都写在 Dart / JS 源码里，不在 ARB 文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 安全回应模板 | 6 | safety_acknowledgements.json：3 个陪伴者 × moderate/acute |
| AI 后备句 | 4 | llm_fallback_messages.json：3 个陪伴者 + `_default` |

来源：`functions/prompts/safety_acknowledgements.json`（整个文件，共 34 行，SHA-256 `96fd03c84e3ece63…`）

```json
{
  "_comment": "Templated per-agent safety acknowledgements (Dev Req §9; Phase A baseline S-2/S-3 2026-09). Surfaced verbatim in addition to the LLM reply when the detector raises moderate_interrupt; shown instead of any reply at acute. moderate_review shows nothing. {{HOTLINE_NAME}} / {{HOTLINE_NUMBER}} are filled from crisis_resources.json (item flagged acuteTemplateReference) so the number always matches the crisis page. Wording pending PI confirmation — edit strings here only, never in code.",
  "_version": "v2-2026-09",
  "siu_yan": {
    "moderate": {
      "zh": "聽起上嚟今日好沉重。等我哋停一停 —— 呢度有資源可以幫到你嘅。",
      "en": "That sounds very heavy today. Let's pause for a moment — there's support here that can help."
    },
    "acute": {
      "zh": "你啱啱講嘅嘢我聽到。請即刻打{{HOTLINE_NAME}} {{HOTLINE_NUMBER}}，佢哋會聽你講。我會繼續喺度。",
      "en": "I heard what you just said. Please call {{HOTLINE_NAME}} at {{HOTLINE_NUMBER}} right now. I'll stay here."
    }
  },
  "ah_jan_ah_bak": {
    "moderate": {
      "zh": "咁樣聽起上嚟好沉重。我喺度聽。呢度亦有支援，要唔要睇下？",
      "en": "That weighs heavy. I'm listening. There's also support here — would you like to see it?"
    },
    "acute": {
      "zh": "多謝你信我，肯講出嚟。請即刻打{{HOTLINE_NAME}} {{HOTLINE_NUMBER}}。我都喺度。",
      "en": "Thank you for trusting me. Please call {{HOTLINE_NAME}} at {{HOTLINE_NUMBER}} right now. I'll be here."
    }
  },
  "tung_tung": {
    "moderate": {
      "zh": "呢度有支援資源，要唔要睇下？",
      "en": "There's support here — would you like to see it?"
    },
    "acute": {
      "zh": "你啱啱講嘅嘢非常重要。請即刻打{{HOTLINE_NAME}} {{HOTLINE_NUMBER}}。我會幫你搵小欣。",
      "en": "What you just said is very important. Please call {{HOTLINE_NAME}} at {{HOTLINE_NUMBER}} right now. I'll help you find Siu Yan."
    }
  }
}
```

来源：`functions/prompts/crisis_resources.json`（整个文件，共 57 行，SHA-256 `b8b0d47c5739f82e…`）

```json
{
  "_comment": "S-4 — crisis page resource list (HREC approval §8.1 order). Numbers are carried over from the pre-baseline page / public listings and were NOT verifiable from the build environment (official sites unreachable through the CI proxy). PI: open each `verifySource`, confirm the number, then set `verifiedDate` (YYYY-MM-DD). Until then the crisis page footer reads 資料核對日期：待核對. Item flagged acuteTemplateReference is the hotline named in the three acute templates and must stay at position 1 or 2.",
  "_version": "v1-2026-09",
  "verifiedDate": "",
  "headlineZh": "如果你有不安嘅諗法，可以即刻搵人傾",
  "headlineEn": "If you are having upsetting thoughts, reach someone now",
  "resources": [
    {
      "id": "sps",
      "nameZh": "生命熱線",
      "nameEn": "Suicide Prevention Services",
      "number": "2382 0000",
      "hoursZh": "24 小時",
      "hoursEn": "24 hours",
      "noteZh": "24 小時防止自殺熱線。",
      "noteEn": "24-hour suicide prevention hotline.",
      "acuteTemplateReference": false,
      "verifySource": "https://www.sps.org.hk/"
    },
    {
      "id": "samaritans_hk",
      "nameZh": "撒瑪利亞會",
      "nameEn": "The Samaritans Hong Kong",
      "number": "2896 0000",
      "hoursZh": "24 小時・多語",
      "hoursEn": "24 hours · multilingual",
      "noteZh": "可以粵語、普通話或英語溝通。",
      "noteEn": "Cantonese, Mandarin or English available.",
      "acuteTemplateReference": true,
      "verifySource": "https://samaritans.org.hk/"
    },
    {
      "id": "ha_mental_health_direct",
      "nameZh": "醫院管理局精神健康專線",
      "nameEn": "HA Mental Health Direct",
      "number": "2466 7350",
      "hoursZh": "24 小時",
      "hoursEn": "24 hours",
      "noteZh": "醫院管理局精神健康專線。",
      "noteEn": "Hospital Authority mental health line.",
      "acuteTemplateReference": false,
      "verifySource": "https://www.ha.org.hk/ (醫院管理局精神健康專線 2466 7350)"
    },
    {
      "id": "emergency_999",
      "nameZh": "急症室 / 999",
      "nameEn": "A&E / 999",
      "number": "999",
      "hoursZh": "緊急情況",
      "hoursEn": "Emergencies",
      "noteZh": "即時危險時請即刻撥打，或去最近嘅急症室。",
      "noteEn": "Call right away if in immediate danger, or go to the nearest A&E.",
      "acuteTemplateReference": false,
      "verifySource": "https://www.police.gov.hk/"
    }
  ]
}
```

来源：`lib/core/safety/safety_copy.dart`（整个文件，共 228 行，SHA-256 `6df027aea43a8e2e…`）

```dart
/// Participant-facing safety strings, all loaded from JSON so the PI can
/// change wording without a code edit (Phase A baseline S-3 / S-4 / S-6):
///
///   • `functions/prompts/safety_acknowledgements.json` — per-agent
///     moderate / acute templates (shared with the Cloud Function bundle).
///   • `functions/prompts/crisis_resources.json` — the four HREC §8.1
///     crisis resources in order, plus the verification date.
///   • `assets/config/llm_fallback_messages.json` — per-agent line shown
///     when the LLM call fails.
///
/// `{{HOTLINE_NAME}}` / `{{HOTLINE_NUMBER}}` in a template are filled from
/// the resource flagged `acuteTemplateReference`, so the acute template can
/// never drift from the crisis page.
///
/// All getters are synchronous after [SafetyCopy.load]; before that (or if
/// an asset fails to load) they fall back to a minimal built-in string so a
/// crisis surface is never blank.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class CrisisResource {
  final String id;
  final String nameZh;
  final String nameEn;
  final String number;
  final String hoursZh;
  final String hoursEn;
  final String noteZh;
  final String noteEn;
  final bool acuteTemplateReference;

  const CrisisResource({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.number,
    required this.hoursZh,
    required this.hoursEn,
    required this.noteZh,
    required this.noteEn,
    required this.acuteTemplateReference,
  });

  String name(bool isEn) => isEn ? nameEn : nameZh;
  String hours(bool isEn) => isEn ? hoursEn : hoursZh;
  String note(bool isEn) => isEn ? noteEn : noteZh;

  factory CrisisResource.fromMap(Map<String, dynamic> m) => CrisisResource(
        id: (m['id'] as String?) ?? '',
        nameZh: (m['nameZh'] as String?) ?? '',
        nameEn: (m['nameEn'] as String?) ?? '',
        number: (m['number'] as String?) ?? '',
        hoursZh: (m['hoursZh'] as String?) ?? '',
        hoursEn: (m['hoursEn'] as String?) ?? '',
        noteZh: (m['noteZh'] as String?) ?? '',
        noteEn: (m['noteEn'] as String?) ?? '',
        acuteTemplateReference: (m['acuteTemplateReference'] as bool?) ?? false,
      );
}

class CrisisResources {
  final List<CrisisResource> resources;

  /// `YYYY-MM-DD` the PI verified the numbers; empty until verified.
  final String verifiedDate;
  final String headlineZh;
  final String headlineEn;
  final String version;

  const CrisisResources({
    required this.resources,
    required this.verifiedDate,
    required this.headlineZh,
    required this.headlineEn,
    required this.version,
  });

  String headline(bool isEn) => isEn ? headlineEn : headlineZh;

  CrisisResource? get acuteReference {
    for (final r in resources) {
      if (r.acuteTemplateReference) return r;
    }
    return resources.isEmpty ? null : resources.first;
  }

  factory CrisisResources.fromMap(Map<String, dynamic> m) => CrisisResources(
        resources: [
          for (final r in (m['resources'] as List? ?? const []))
            if (r is Map) CrisisResource.fromMap(Map<String, dynamic>.from(r)),
        ],
        verifiedDate: (m['verifiedDate'] as String?) ?? '',
        headlineZh: (m['headlineZh'] as String?) ?? '',
        headlineEn: (m['headlineEn'] as String?) ?? '',
        version: (m['_version'] as String?) ?? '',
      );

  /// Built-in minimum so the crisis page is never empty if the asset is
  /// missing.  999 only — the hotline numbers must come from the verified
  /// JSON, never from code.
  static const fallback = CrisisResources(
    resources: [
      CrisisResource(
        id: 'emergency_999',
        nameZh: '急症室 / 999',
        nameEn: 'A&E / 999',
        number: '999',
        hoursZh: '緊急情況',
        hoursEn: 'Emergencies',
        noteZh: '即時危險時請即刻撥打。',
        noteEn: 'Call right away if in immediate danger.',
        acuteTemplateReference: true,
      ),
    ],
    verifiedDate: '',
    headlineZh: '如果你有不安嘅諗法，可以即刻搵人傾',
    headlineEn: 'If you are having upsetting thoughts, reach someone now',
    version: 'builtin',
  );
}

class SafetyCopy {
  SafetyCopy._();

  static Map<String, dynamic> _acks = const {};
  static Map<String, dynamic> _fallbacks = const {};
  static CrisisResources _crisis = CrisisResources.fallback;
  static bool _loaded = false;

  static bool get isLoaded => _loaded;
  static CrisisResources get crisis => _crisis;
  static String get ackVersion => (_acks['_version'] as String?) ?? 'unloaded';
  static String get fallbackVersion =>
      (_fallbacks['_version'] as String?) ?? 'unloaded';

  static const acksAsset = 'functions/prompts/safety_acknowledgements.json';
  static const crisisAsset = 'functions/prompts/crisis_resources.json';
  static const fallbackAsset = 'assets/config/llm_fallback_messages.json';

  /// Load all three assets.  Safe to call more than once; never throws.
  static Future<void> load() async {
    try {
      _acks = _decode(await rootBundle.loadString(acksAsset));
    } catch (e) {
      if (kDebugMode) debugPrint('[SafetyCopy] acks asset missing: $e');
    }
    try {
      _crisis = CrisisResources.fromMap(
          _decode(await rootBundle.loadString(crisisAsset)));
    } catch (e) {
      if (kDebugMode) debugPrint('[SafetyCopy] crisis asset missing: $e');
    }
    try {
      _fallbacks = _decode(await rootBundle.loadString(fallbackAsset));
    } catch (e) {
      if (kDebugMode) debugPrint('[SafetyCopy] fallback asset missing: $e');
    }
    _loaded = true;
  }

  /// Test hook — inject decoded JSON without the asset bundle.
  @visibleForTesting
  static void inject({
    Map<String, dynamic>? acks,
    Map<String, dynamic>? fallbacks,
    Map<String, dynamic>? crisis,
  }) {
    if (acks != null) _acks = acks;
    if (fallbacks != null) _fallbacks = fallbacks;
    if (crisis != null) _crisis = CrisisResources.fromMap(crisis);
    _loaded = true;
  }

  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(jsonDecode(s) as Map);

  /// S-3 — moderate_interrupt template for [agentId] (shown *with* the LLM
  /// reply).  Null when no template is configured for the agent.
  static String? moderateAck(String agentId, {required bool isEn}) =>
      _ack(agentId, 'moderate', isEn);

  /// S-3 — acute template for [agentId] (shown *instead of* any reply).
  /// Falls back to a hotline-only system line if the JSON is missing.
  static String acuteAck(String agentId, {required bool isEn}) {
    final t = _ack(agentId, 'acute', isEn);
    if (t != null && t.isNotEmpty) return t;
    final ref = _crisis.acuteReference;
    final name = ref?.name(isEn) ?? '';
    final num = ref?.number ?? '999';
    return isEn
        ? "What you've just said is heavy. Please call $name $num now."
        : '你頭先講嘅嘢好重。請即刻打$name $num。';
  }

  static String? _ack(String agentId, String level, bool isEn) {
    final agent = _acks[agentId];
    if (agent is! Map) return null;
    final lvl = agent[level];
    if (lvl is! Map) return null;
    final raw = (lvl[isEn ? 'en' : 'zh'] ?? lvl['zh']) as String?;
    return raw == null ? null : fillHotline(raw, isEn: isEn);
  }

  /// Substitute `{{HOTLINE_NAME}}` / `{{HOTLINE_NUMBER}}` from the crisis
  /// resource flagged `acuteTemplateReference`.
  static String fillHotline(String text, {required bool isEn}) {
    final ref = _crisis.acuteReference;
    return text
        .replaceAll('{{HOTLINE_NAME}}', ref?.name(isEn) ?? '')
        .replaceAll('{{HOTLINE_NUMBER}}', ref?.number ?? '');
  }

  /// S-6 — per-agent fallback line for a failed LLM call.
  static String llmFallback(String? agentId, {required bool isEn}) {
    final key = isEn ? 'en' : 'zh';
    final agent = agentId == null ? null : _fallbacks[agentId];
    if (agent is Map && agent[key] is String) return agent[key] as String;
    final def = _fallbacks['_default'];
    if (def is Map && def[key] is String) return def[key] as String;
    return isEn
        ? 'Sorry, I was slow just now. Could you say that again?'
        : '唔好意思，我啱啱行慢咗。可以再講多次嗎？';
  }
}
```

来源：`assets/config/llm_fallback_messages.json`（整个文件，共 20 行，SHA-256 `2a495b99b4d715e5…`）

```json
{
  "_comment": "S-6 — per-agent line shown when the LLM call fails (CF 55 s timeout, DeepSeek 4xx/5xx, network error, empty body). Wording pending PI confirmation — edit here only. The turn logs llm.status = fallback and is excluded from the five-flag tags and the Brief PR turn count.",
  "_version": "v1-2026-09",
  "siu_yan": {
    "zh": "唔好意思，我啱啱行慢咗。你講嘅嘢我聽到，可以再講多次嗎？",
    "en": "Sorry, I was a bit slow just now. I heard you — could you say that once more?"
  },
  "ah_jan_ah_bak": {
    "zh": "唔好意思，我啱啱走神咗。你頭先講嘅，再講多少少好嗎？",
    "en": "Sorry, my mind wandered for a moment. Could you tell me that again?"
  },
  "tung_tung": {
    "zh": "哎，我啱啱斷咗線。再講一次，我聽住。",
    "en": "Oops, I dropped off for a second. Say it again — I'm listening."
  },
  "_default": {
    "zh": "唔好意思，我啱啱行慢咗。可以再講多次嗎？",
    "en": "Sorry, I was slow just now. Could you say that again?"
  }
}
```

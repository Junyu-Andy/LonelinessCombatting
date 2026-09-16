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

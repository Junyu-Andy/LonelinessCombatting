/// W2/W4 Agent Differentiation assessment data model.
///
/// Stored at `users/{uid}/agent_diff/{auto-id}` with `timepoint` field
/// (Sprint 1 spec — was `w2|w4` doc id, now auto-id with timepoint
/// string `"week2"|"week4"`).

import 'package:cloud_firestore/cloud_firestore.dart';

class AgentDiffResponse {
  /// 2 or 4 (wave / week number).
  final int wave;

  /// Part A: usage frequency per agent (0-3).
  /// Keys are agent IDs: siu_yan, ah_jan_ah_bak, tung_tung.
  final Map<String, int> usageFreq;

  /// Part B: personality trait rating per agent (1-5).
  /// Outer key = traitId, inner key = agentId.
  final Map<String, Map<String, int>> personality;

  /// Part C: scenario → agent preference (W4 only, null for W2).
  final Map<String, String>? function;

  /// Part D: open-text free response.
  final String freeResponse;

  final DateTime answeredAt;

  const AgentDiffResponse({
    required this.wave,
    required this.usageFreq,
    required this.personality,
    this.function,
    required this.freeResponse,
    required this.answeredAt,
  });

  /// Sprint 1 timepoint string: `"week2"` or `"week4"`.
  String get timepoint => 'week$wave';

  Map<String, dynamic> toFirestore() => {
        'wave': wave,
        'timepoint': timepoint,
        'usageFreq': usageFreq,
        'personality': personality,
        'function': function,
        'freeResponse': freeResponse,
        'answeredAt': FieldValue.serverTimestamp(),
      };

  factory AgentDiffResponse.fromFirestore(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        final dynamic dyn = v;
        final result = dyn.toDate();
        if (result is DateTime) return result;
      } catch (_) {}
      return DateTime.now();
    }

    Map<String, int> parseIntMap(dynamic raw) {
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toInt(),
      };
    }

    Map<String, Map<String, int>> parseNestedIntMap(dynamic raw) {
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is Map)
            e.key as String: parseIntMap(e.value),
      };
    }

    Map<String, String>? parseStringMap(dynamic raw) {
      if (raw == null) return null;
      if (raw is! Map) return null;
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    }

    return AgentDiffResponse(
      wave: (map['wave'] as num?)?.toInt() ?? 2,
      usageFreq: parseIntMap(map['usageFreq']),
      personality: parseNestedIntMap(map['personality']),
      function: parseStringMap(map['function']),
      freeResponse: (map['freeResponse'] as String?) ?? '',
      answeredAt: parseDate(map['answeredAt']),
    );
  }
}

/// Agent IDs used across the assessment.
class AgentDiffAgents {
  static const siuYan = 'siu_yan';
  static const ahJanAhBak = 'ah_jan_ah_bak';
  static const tungTung = 'tung_tung';

  static const all = [siuYan, ahJanAhBak, tungTung];

  static const labels = {
    siuYan: '小欣',
    ahJanAhBak: '阿珍／阿伯',
    tungTung: '通通',
  };
}

/// Personality trait IDs used in Part B.
class AgentDiffTraits {
  static const warm = 'warm';
  static const sameAge = 'same_age';
  static const curious = 'curious';
  static const nonJudgmental = 'non_judgmental';
  static const empathetic = 'empathetic';

  static const all = [warm, sameAge, curious, nonJudgmental, empathetic];

  static const labels = {
    warm: '溫暖關心人',
    sameAge: '似自己同年紀嘅人',
    curious: '好奇鍾意問我嘢',
    nonJudgmental: '聽我講而唔評判我',
    empathetic: '感受到我嘅心情',
  };
}

/// Scenario IDs used in Part C (W4 only).
class AgentDiffScenarios {
  static const dailyChat = 'daily_chat';
  static const feelingSad = 'feeling_sad';
  static const memories = 'memories';
  static const learnNew = 'learn_new';
  static const planContact = 'plan_contact';

  static const all = [dailyChat, feelingSad, memories, learnNew, planContact];

  static const labels = {
    dailyChat: '想傾下日常瑣事',
    feelingSad: '心情唔好想傾下',
    memories: '想分享人生回憶',
    learnNew: '想學下新嘢或者查嘢',
    planContact: '想計劃同人聯絡',
  };
}

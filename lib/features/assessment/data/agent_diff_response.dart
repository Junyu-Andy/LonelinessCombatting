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
///
/// Aligned to Agent_Differentiation_Assessment_Final_v1.0 — exactly 4
/// traits. The design note intentionally excludes "remembers what I told
/// before" (shared memory store — non-differentiating) and "helps me think
/// differently" (Thought-Exercise-specific); an earlier `empathetic` trait
/// was also dropped to match the final 4-trait instrument.
class AgentDiffTraits {
  static const warm = 'warm';
  static const sameAge = 'same_age';
  static const curious = 'curious';
  static const nonJudgmental = 'non_judgmental';

  static const all = [warm, sameAge, curious, nonJudgmental];

  static const labels = {
    warm: '溫暖、關心人',
    sameAge: '似自己同年紀嘅人',
    curious: '好奇，鍾意問我嘢',
    nonJudgmental: '聽我講而唔評判我',
  };

  static const labelsEn = {
    warm: 'Warm and caring',
    sameAge: 'Feels like someone my own age',
    curious: 'Curious — asks me questions',
    nonJudgmental: 'Listens without judging me',
  };
}

/// Scenario IDs used in Part C (W4 only).
///
/// Aligned to Agent_Differentiation_Assessment_Final_v1.0 — exactly 5
/// scenarios (single-select among the 3 agents + "邊個都得／冇所謂").
class AgentDiffScenarios {
  static const dayRecap = 'day_recap';
  static const memories = 'memories';
  static const learnNew = 'learn_new';
  static const feelingDown = 'feeling_down';
  static const smallTalk = 'small_talk';

  static const all = [dayRecap, memories, learnNew, feelingDown, smallTalk];

  static const labels = {
    dayRecap: '講下今日點過',
    memories: '講下舊時嘅回憶、人生經歷',
    learnNew: '學啲新嘢',
    feelingDown: '心情唔好嘅時候',
    smallTalk: '日常閒聊',
  };

  static const labelsEn = {
    dayRecap: 'Talk about how my day went',
    memories: 'Share old memories / life experiences',
    learnNew: 'Learn something new',
    feelingDown: "When I'm feeling down",
    smallTalk: 'Everyday small talk',
  };
}

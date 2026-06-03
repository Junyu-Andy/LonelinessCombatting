/// Seeds each companion's first-conversation memory from the onboarding
/// intake (Demo Sprint Plan §1D + Appendix C).
///
/// This is intentionally a pure, Firebase-free helper: given an
/// [IntakeResponse] (+ the curated `profile.interests`) it returns a short
/// Cantonese seed paragraph per agent, or null when there's nothing worth
/// seeding. The caller (PersonaResolver) persists the result into
/// `agent_contexts/{agentId}.rollingSummary` exactly once, the first time
/// the user opens a room with an empty summary.
///
/// Field routing follows Appendix C:
///   • 小欣 (siu_yan)      = goals + typicalDay + interests + avoidTopics(tone)
///   • 通通 (tung_tung)    = interests/topics + goals
///   • 阿珍/阿伯 (ah_jan)  = goals only (lifeChapters HOLD → Phase B)
///
/// HARD RULES honoured here (Sprint Plan §0):
///   • `onMind` is NEVER read or seeded.
///   • `importantPeople` / `reconnectPeople` / `closeContacts` are HOLD —
///     never seeded (no third-party names pushed to the endpoint).
///   • `avoidTopics` is referenced only as a tone instruction, never echoed
///     as a topic to raise.
library;

import '../../features/onboarding/data/intake_response.dart';
import '../../features/onboarding/data/interest_labels.dart';
import '../agents/agent_registry.dart';

class IntakeMemorySeeder {
  IntakeMemorySeeder._();

  /// Readable Cantonese label for each `mainGoal` option id.
  static const Map<String, String> _goalLabels = {
    IntakeOptions.mainGoalCompanionship: '想有人陪下傾偈',
    IntakeOptions.mainGoalEmotionalOutlet: '想搵個地方抒發下心情',
    IntakeOptions.mainGoalReconnect: '想同人重新連繫',
    IntakeOptions.mainGoalLearning: '想學下新嘢',
    IntakeOptions.mainGoalShareMemories: '想分享下人生回憶',
    IntakeOptions.mainGoalCurious: '對世界仲好有好奇心',
  };

  /// Build the seed string for [agentId], or null when there's nothing
  /// worth seeding for that agent.
  ///
  /// [interests] should be the curated `profile.interests` ids (mapped via
  /// [InterestLabels]); [intake] supplies goals / typical day / avoidTopics.
  static String? seedFor({
    required String agentId,
    required IntakeResponse? intake,
    required List<String> interests,
  }) {
    if (intake == null) return null;

    final goals = _goalsLine(intake);
    final interestLine = _interestsLine(interests, intake);
    final dayLine = _typicalDayLine(intake);
    final avoidLine = (intake.avoidTopics?.trim().isNotEmpty ?? false)
        ? '有啲話題用戶唔想提起，系統已記低，唔好主動講。'
        : null;

    final parts = <String>[];
    switch (agentId) {
      case AgentRegistry.siuYanId:
        if (goals != null) parts.add(goals);
        if (dayLine != null) parts.add(dayLine);
        if (interestLine != null) parts.add(interestLine);
        if (avoidLine != null) parts.add(avoidLine);
        break;
      case AgentRegistry.tungTungId:
        if (interestLine != null) parts.add(interestLine);
        if (goals != null) parts.add(goals);
        break;
      case AgentRegistry.ahJanAhBakId:
        // lifeChapters are HOLD (Phase B) — keep the reminiscence seed light
        // so 阿珍／阿伯 doesn't claim to remember threads not yet discussed.
        if (goals != null) parts.add(goals);
        break;
      default:
        return null;
    }

    if (parts.isEmpty) return null;
    // Frame explicitly as onboarding-provided, NOT a past conversation, so
    // the agent references it naturally without fabricating shared history.
    return '（以下係用戶喺一開始填表時提供嘅資料，唔係過往傾偈內容）\n'
        '${parts.join(' ')}';
  }

  static String? _goalsLine(IntakeResponse intake) {
    final labels = <String>[];
    for (final g in intake.mainGoals) {
      final label = _goalLabels[g];
      if (label != null) labels.add(label);
    }
    if (labels.isEmpty) return null;
    return '用戶嚟呢度，主要係${labels.join('、')}。';
  }

  static String? _interestsLine(List<String> interests, IntakeResponse intake) {
    final names = <String>[];
    for (final id in interests.take(6)) {
      names.add(InterestLabels.label(id, false));
    }
    if (names.isEmpty) return null;
    return '佢平時鍾意：${names.join('、')}。';
  }

  static String? _typicalDayLine(IntakeResponse intake) {
    final segs = <String>[];
    void add(String? raw) {
      final t = raw?.trim();
      if (t != null && t.isNotEmpty) segs.add(t);
    }

    add(intake.typicalMorning);
    add(intake.typicalAfternoon);
    add(intake.typicalEvening);
    if (segs.isEmpty) return null;
    // Keep it short — a one-line gist, not a transcript.
    final joined = segs.join('；');
    final gist = joined.length > 80 ? '${joined.substring(0, 80)}…' : joined;
    return '佢嘅日常大致係：$gist。';
  }
}

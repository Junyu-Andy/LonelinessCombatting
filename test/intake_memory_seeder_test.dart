import 'package:app_demo/core/agent_context/intake_memory_seeder.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/features/onboarding/data/intake_response.dart';
import 'package:flutter_test/flutter_test.dart';

/// §1D — verifies the intake → first-conversation memory seed honours the
/// Appendix C field routing AND the §0 hard rules (onMind / importantPeople
/// never leave the device through the seed).
void main() {
  IntakeResponse buildIntake() => IntakeResponse(
        mainGoals: const [
          IntakeOptions.mainGoalCompanionship,
          IntakeOptions.mainGoalShareMemories,
        ],
        typicalMorning: '朝早飲茶睇報紙',
        typicalAfternoon: '落公園散步',
        importantPeople: const [
          PersonEntry(name: '阿明', relationship: '個仔'),
        ],
        onMind: '我覺得好孤獨，冇人理我',
        avoidTopics: '唔好提我先生',
        inputMode: IntakeOptions.inputBoth,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  const interests = ['yum_cha', 'gardening'];

  test('siu_yan seed carries goals + typical day + interests + avoid-tone',
      () {
    final seed = IntakeMemorySeeder.seedFor(
      agentId: AgentRegistry.siuYanId,
      intake: buildIntake(),
      interests: interests,
    )!;
    expect(seed, contains('想有人陪下傾偈'));
    expect(seed, contains('飲茶')); // typical day
    expect(seed, contains('飲茶／一盅兩件')); // interest label
    expect(seed, contains('唔好主動講')); // avoidTopics → tone only
  });

  test('tung_tung seed carries interests + goals, not typical day', () {
    final seed = IntakeMemorySeeder.seedFor(
      agentId: AgentRegistry.tungTungId,
      intake: buildIntake(),
      interests: interests,
    )!;
    expect(seed, contains('種花種菜'));
    expect(seed, isNot(contains('落公園散步'))); // typicalDay is siu_yan-only
  });

  test('ah_jan seed stays light (goals only — lifeChapters HOLD)', () {
    final seed = IntakeMemorySeeder.seedFor(
      agentId: AgentRegistry.ahJanAhBakId,
      intake: buildIntake(),
      interests: interests,
    )!;
    expect(seed, contains('想分享下人生回憶'));
    expect(seed, isNot(contains('飲茶／一盅兩件'))); // no interest dump
  });

  test('HARD RULE: onMind and third-party names NEVER appear in any seed', () {
    for (final agent in [
      AgentRegistry.siuYanId,
      AgentRegistry.tungTungId,
      AgentRegistry.ahJanAhBakId,
    ]) {
      final seed = IntakeMemorySeeder.seedFor(
            agentId: agent,
            intake: buildIntake(),
            interests: interests,
          ) ??
          '';
      expect(seed, isNot(contains('孤獨'))); // onMind content
      expect(seed, isNot(contains('冇人理我'))); // onMind content
      expect(seed, isNot(contains('阿明'))); // importantPeople name
      expect(seed, isNot(contains('先生'))); // avoidTopics literal text
    }
  });

  test('avoid-topics literal text is never echoed, only the tone note', () {
    final seed = IntakeMemorySeeder.seedFor(
      agentId: AgentRegistry.siuYanId,
      intake: buildIntake(),
      interests: interests,
    )!;
    // The instruction is present...
    expect(seed, contains('唔想提起'));
    // ...but the actual sensitive topic text is not.
    expect(seed, isNot(contains('唔好提我先生')));
  });

  test('null intake yields null seed (guest / not-yet-onboarded)', () {
    expect(
      IntakeMemorySeeder.seedFor(
        agentId: AgentRegistry.siuYanId,
        intake: null,
        interests: interests,
      ),
      isNull,
    );
  });
}

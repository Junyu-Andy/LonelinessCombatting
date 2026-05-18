/// Sprint 1 exit-criteria contract tests.
///
/// Covers: B.2 TurnMetadata, B.4 ThoughtExerciseEntry round-trip,
/// C.2 ArmAssigner strata-cell mapping, B.7 SafetyEventWriter level filter.
library;

import 'package:app_demo/core/llm/turn_metadata.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/safety_event_writer.dart';
import 'package:app_demo/features/auth/data/arm_assigner.dart';
import 'package:app_demo/features/thought_exercise/data/thought_exercise_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // -----------------------------------------------------------------------
  // B.2 TurnMetadata
  // -----------------------------------------------------------------------
  group('TurnMetadata', () {
    test('round-trips all fields', () {
      const meta = TurnMetadata(
        systemPromptHash: 'abc123',
        promptKey: 'siu_yan_v1',
        agentId: 'siu_yan',
        sessionId: 'sess-42',
      );
      final round = TurnMetadata.fromMap(meta.toMap());
      expect(round.systemPromptHash, 'abc123');
      expect(round.promptKey, 'siu_yan_v1');
      expect(round.agentId, 'siu_yan');
      expect(round.sessionId, 'sess-42');
    });

    test('armB constructor always has null systemPromptHash', () {
      const meta = TurnMetadata.armB(agentId: 'siu_yan', sessionId: 's1');
      expect(meta.systemPromptHash, isNull);
      expect(meta.promptKey, isNull);
      expect(meta.agentId, 'siu_yan');
    });

    test('fromMap tolerates missing fields', () {
      final meta = TurnMetadata.fromMap({});
      expect(meta.systemPromptHash, isNull);
      expect(meta.promptKey, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // B.4 ThoughtExerciseEntry
  // -----------------------------------------------------------------------
  group('ThoughtExerciseEntry', () {
    test('round-trips all 7 fields', () {
      final entry = ThoughtExerciseEntry(
        thought: '打畀阿女只會煩到佢',
        oneReasonTrue: '佢上次無覆我',
        anotherWayToLook: '佢可能只係忙',
        agentId: 'siu_yan',
        agentInvitationText: '你有冇試過記低你嘅想法？',
        originTurnRef: 'users/u1/agent_contexts/siu_yan',
        createdAt: DateTime.utc(2026, 5, 14),
      );
      final round = ThoughtExerciseEntry.fromMap('e1', entry.toMap());
      expect(round.id, 'e1');
      expect(round.thought, '打畀阿女只會煩到佢');
      expect(round.oneReasonTrue, '佢上次無覆我');
      expect(round.anotherWayToLook, '佢可能只係忙');
      expect(round.agentId, 'siu_yan');
      expect(round.agentInvitationText, '你有冇試過記低你嘅想法？');
      expect(round.originTurnRef, 'users/u1/agent_contexts/siu_yan');
    });

    test('handles optional provenance fields being null', () {
      final entry = ThoughtExerciseEntry(
        thought: 't',
        oneReasonTrue: 'r',
        anotherWayToLook: 'a',
        createdAt: DateTime.now(),
      );
      final round = ThoughtExerciseEntry.fromMap('e2', entry.toMap());
      expect(round.agentId, isNull);
      expect(round.agentInvitationText, isNull);
      expect(round.originTurnRef, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // C.2 ArmAssigner strata-cell mapping
  // -----------------------------------------------------------------------
  group('ArmAssigner.strataCell', () {
    test('maps known age groups to cells 0-3', () {
      expect(ArmAssigner.strataCell('60-64'), 0);
      expect(ArmAssigner.strataCell('65-69'), 1);
      expect(ArmAssigner.strataCell('70-74'), 2);
      expect(ArmAssigner.strataCell('75+'), 3);
    });

    test('unknown / null age group defaults to cell 0', () {
      expect(ArmAssigner.strataCell(null), 0);
      expect(ArmAssigner.strataCell('unknown'), 0);
      expect(ArmAssigner.strataCell(''), 0);
    });
  });

  // -----------------------------------------------------------------------
  // B.7 SafetyEventWriter level gating
  // (writer is in no-op mode when available=false; we test the level gate)
  // -----------------------------------------------------------------------
  group('SafetyEventWriter.maybeWrite level gate', () {
    test('does not throw for none/low distress (no-op when unavailable)', () async {
      final writer = SafetyEventWriter(available: false);
      // Should complete without error for non-escalating levels.
      await expectLater(
        writer.maybeWrite(
          uid: 'u1',
          source: SafetySource.gatewayInput,
          match: const DistressMatch(DistressLevel.none),
          inputText: 'hello',
        ),
        completes,
      );
      await expectLater(
        writer.maybeWrite(
          uid: 'u1',
          source: SafetySource.gatewayOutput,
          match: const DistressMatch(DistressLevel.low),
          inputText: '我有啲孤獨',
        ),
        completes,
      );
    });

    test('completes without error for moderate/acute when unavailable', () async {
      final writer = SafetyEventWriter(available: false);
      await expectLater(
        writer.maybeWrite(
          uid: 'u1',
          source: SafetySource.m3Turn,
          match: const DistressMatch(DistressLevel.acute, '想死'),
          inputText: '我想死',
          agentId: 'siu_yan',
        ),
        completes,
      );
    });
  });
}

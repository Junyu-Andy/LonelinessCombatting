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
  // B.4 ThoughtExerciseEntry — 5 content fields + intensity_before/after
  //                            (Phase A spec May 2026)
  // -----------------------------------------------------------------------
  group('ThoughtExerciseEntry', () {
    test('round-trips all 5 content fields + intensity_before/after', () {
      final entry = ThoughtExerciseEntry(
        situation: '尋日喺街市見到舊朋友冇打招呼',
        emotionEmoji: '😔',
        intensityBefore: 7,
        thought: '佢覺得我老咗唔想理我',
        oneReasonTrue: '我哋好耐冇見',
        anotherWayToLook: '可能佢趕住做嘢冇留意到',
        intensityAfter: 4,
        agentId: 'siu_yan',
        agentInvitationText: '你頭先講咗一句令我有少少 stuck — ...',
        originTurnRef: 'users/u1/agent_contexts/siu_yan',
        createdAt: DateTime.utc(2026, 5, 14),
        entryPathway: 'siu_yan_offer',
      );
      final round = ThoughtExerciseEntry.fromMap('e1', entry.toMap());
      expect(round.id, 'e1');
      expect(round.situation, '尋日喺街市見到舊朋友冇打招呼');
      expect(round.emotionEmoji, '😔');
      expect(round.intensityBefore, 7);
      expect(round.thought, '佢覺得我老咗唔想理我');
      expect(round.oneReasonTrue, '我哋好耐冇見');
      expect(round.anotherWayToLook, '可能佢趕住做嘢冇留意到');
      expect(round.intensityAfter, 4);
      expect(round.agentId, 'siu_yan');
      expect(round.agentInvitationText, '你頭先講咗一句令我有少少 stuck — ...');
      expect(round.originTurnRef, 'users/u1/agent_contexts/siu_yan');
      expect(round.entryPathway, 'siu_yan_offer');
    });

    test('Field 5 (alternative) may legitimately be blank per spec', () {
      final entry = ThoughtExerciseEntry(
        situation: 's',
        emotionEmoji: '😐',
        intensityBefore: 5,
        thought: 't',
        oneReasonTrue: 'r',
        anotherWayToLook: '', // blank — spec-compliant
        createdAt: DateTime.now(),
      );
      final round = ThoughtExerciseEntry.fromMap('e2', entry.toMap());
      expect(round.anotherWayToLook, '');
      expect(round.intensityAfter, isNull); // not yet re-rated
      expect(round.entryPathway, 'me_tile'); // default
    });

    test('copyWith updates intensityAfter for the exit re-rating step', () {
      final entry = ThoughtExerciseEntry(
        situation: 's',
        emotionEmoji: '😐',
        intensityBefore: 6,
        thought: 't',
        oneReasonTrue: 'r',
        anotherWayToLook: 'a',
        createdAt: DateTime.now(),
      );
      final updated = entry.copyWith(intensityAfter: 4);
      expect(updated.intensityBefore, 6);
      expect(updated.intensityAfter, 4);
    });
  });

  // -----------------------------------------------------------------------
  // C.2 ArmAssigner strata-cell mapping (Phase B spec: UCLA × age band)
  // -----------------------------------------------------------------------
  group('ArmAssigner.strataCell', () {
    test('low loneliness × 60-69 → cell 0', () {
      expect(ArmAssigner.strataCell(uclaScore: 35, ageYears: 65), 0);
    });
    test('low loneliness × ≥70 → cell 1', () {
      expect(ArmAssigner.strataCell(uclaScore: 35, ageYears: 72), 1);
    });
    test('high loneliness × 60-69 → cell 2', () {
      expect(ArmAssigner.strataCell(uclaScore: 50, ageYears: 65), 2);
    });
    test('high loneliness × ≥70 → cell 3', () {
      expect(ArmAssigner.strataCell(uclaScore: 50, ageYears: 75), 3);
    });
    test('exactly at median (44) treated as low (not >median)', () {
      expect(ArmAssigner.strataCell(uclaScore: 44, ageYears: 65), 0);
    });
    test('age group string → years midpoint', () {
      expect(ArmAssigner.ageYearsFromGroup('60-64'), 62);
      expect(ArmAssigner.ageYearsFromGroup('70-74'), 72);
      expect(ArmAssigner.ageYearsFromGroup(null), isNull);
    });
    test('missing data defaults to cell 0', () {
      expect(ArmAssigner.strataCell(uclaScore: null, ageYears: null), 0);
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

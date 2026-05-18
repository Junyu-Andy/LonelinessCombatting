/// Sprint 4 (spec-alignment fixes) — contract tests.
///
/// Covers the corrections after the May-2026 spec review:
///   - B.4 ThoughtExerciseEntry: 5 content fields + intensity_before/after
///   - B.1 LLM 5 flags: corrected names (specific_content_engagement,
///     cross_session_memory, honest_unfamiliarity, mixed_content_routing,
///     generative_summary)
///   - C.2 strata: UCLA × age band
///   - Tung Tung rule-based 16-item pool
///   - Phase B probes (unblinding / dependency / distinguishability)
library;

import 'package:app_demo/features/auth/data/arm_assigner.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_rule_pool.dart';
import 'package:app_demo/features/llm_features/data/llm_turn_features.dart';
import 'package:app_demo/features/phase_b_probes/data/phase_b_probes.dart';
import 'package:app_demo/features/thought_exercise/data/thought_exercise_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------- B.4 Thought Exercise — 5 fields + intensity_before/after ----
  group('ThoughtExerciseEntry spec compliance', () {
    test('5 content fields are required (situation, emotion+intensity, '
        'thought, reason, alternative)', () {
      final e = ThoughtExerciseEntry(
        situation: 's',
        emotionEmoji: '😐',
        intensityBefore: 5,
        thought: 't',
        oneReasonTrue: 'r',
        anotherWayToLook: 'a',
        createdAt: DateTime.now(),
      );
      final m = e.toMap();
      expect(m['situation'], isNotNull);
      expect(m['emotionEmoji'], isNotNull);
      expect(m['intensityBefore'], 5);
      expect(m['thought'], isNotNull);
      expect(m['oneReasonTrue'], isNotNull);
      expect(m['anotherWayToLook'], isNotNull);
    });

    test('intensityBefore + intensityAfter both expressed as int 1–10',
        () {
      final e = ThoughtExerciseEntry(
        situation: 's', emotionEmoji: '😐',
        intensityBefore: 1, thought: 't',
        oneReasonTrue: 'r', anotherWayToLook: 'a',
        intensityAfter: 10,
        createdAt: DateTime.now(),
      );
      expect(e.intensityBefore, 1);
      expect(e.intensityAfter, 10);
    });

    test('entryPathway distinguishes siu_yan_offer vs me_tile', () {
      final fromAgent = ThoughtExerciseEntry(
        situation: 's', emotionEmoji: '😐',
        intensityBefore: 5, thought: 't',
        oneReasonTrue: 'r', anotherWayToLook: 'a',
        createdAt: DateTime.now(),
        agentId: 'siu_yan',
        entryPathway: 'siu_yan_offer',
      );
      expect(fromAgent.entryPathway, 'siu_yan_offer');

      final fromTab = ThoughtExerciseEntry(
        situation: 's', emotionEmoji: '😐',
        intensityBefore: 5, thought: 't',
        oneReasonTrue: 'r', anotherWayToLook: 'a',
        createdAt: DateTime.now(),
      );
      expect(fromTab.entryPathway, 'me_tile'); // default
    });
  });

  // ---------- B.1 LLM 5 flags — spec-compliant names ---------------------
  group('LlmTurnFeatures flag names match Phase A spec', () {
    test('all five spec flag names are accepted and round-trip', () {
      final f = LlmTurnFeatures.fromCloudFunctionPayload(
        agentId: 'siu_yan',
        moduleId: 'm3',
        raw: const {
          'specific_content_engagement': true,
          'cross_session_memory': true,
          'honest_unfamiliarity': false,
          'mixed_content_routing': false,
          'generative_summary': true,
          '_version': 2,
        },
      );
      expect(f.detectorVersion, 2);
      expect(f.flags.keys.toSet(), {
        'specific_content_engagement',
        'cross_session_memory',
        'honest_unfamiliarity',
        'mixed_content_routing',
        'generative_summary',
      });
    });
  });

  // ---------- C.2 strata = UCLA × age band -------------------------------
  group('ArmAssigner strata: UCLA × age band (Phase B §4.4)', () {
    test('4-cell layout', () {
      expect(ArmAssigner.strataCell(uclaScore: 30, ageYears: 60), 0);
      expect(ArmAssigner.strataCell(uclaScore: 30, ageYears: 70), 1);
      expect(ArmAssigner.strataCell(uclaScore: 60, ageYears: 60), 2);
      expect(ArmAssigner.strataCell(uclaScore: 60, ageYears: 70), 3);
    });
    test('median split at 44 — exactly 44 is "low"', () {
      expect(ArmAssigner.strataCell(uclaScore: 44, ageYears: 65), 0);
      expect(ArmAssigner.strataCell(uclaScore: 45, ageYears: 65), 2);
    });
  });

  // ---------- B.4 Tung Tung rule-based pool ------------------------------
  group('TungTungRulePool 16-item static pool', () {
    test('exactly 16 items', () {
      expect(TungTungRulePool.items.length, 16);
    });
    test('all items have both zh and en text, non-empty', () {
      for (final item in TungTungRulePool.items) {
        expect(item.zh.isNotEmpty, true);
        expect(item.en.isNotEmpty, true);
      }
    });
    test('rotation is deterministic by turn index', () {
      final first = TungTungRulePool.openerFor(0);
      final eighth = TungTungRulePool.openerFor(8);
      final sixteenth = TungTungRulePool.openerFor(16);
      expect(first.zh, equals(TungTungRulePool.openerFor(0).zh));
      expect(sixteenth.zh, equals(first.zh)); // wraps at 16
      expect(eighth.zh, isNot(equals(first.zh)));
    });
  });

  // ---------- Phase B distinguishability probe — entropy -----------------
  group('DistinguishabilityProbeResponse.entropy', () {
    test('uniform ratings → maximum entropy', () {
      final r = DistinguishabilityProbeResponse(
        agentRatings: const {
          'siu_yan': 5, 'ah_jan_ah_bak': 5, 'tung_tung': 5,
        },
        answeredAt: DateTime.now(),
        weekNumber: 2,
      );
      // log2(3) ≈ 1.585
      expect(r.entropy, closeTo(1.585, 0.01));
    });
    test('all weight on one agent → zero entropy', () {
      final r = DistinguishabilityProbeResponse(
        agentRatings: const {
          'siu_yan': 7, 'ah_jan_ah_bak': 0, 'tung_tung': 0,
        },
        answeredAt: DateTime.now(),
        weekNumber: 4,
      );
      expect(r.entropy, 0.0);
    });
    test('entropy persisted in toMap', () {
      final r = DistinguishabilityProbeResponse(
        agentRatings: const {
          'siu_yan': 4, 'ah_jan_ah_bak': 2, 'tung_tung': 1,
        },
        answeredAt: DateTime.now(),
        weekNumber: 2,
      );
      final m = r.toMap();
      expect(m['entropy'], greaterThan(0));
      expect(m['entropy'], lessThan(1.585));
    });
  });
}

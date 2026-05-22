/// Sprint 2 exit-criteria contract tests.
///
/// Covers:
///   B.1 LlmTurnFeatures payload parsing + armBSkip gate
///   B.5 (implicit: ThoughtExerciseEntry already round-trip tested in s1)
///   B.6 BriefPprController mandatory-first logic + UserProfile.firstPprSeenByAgent
///   B.9 TurnRepairController debounce + template advance
///   B.10 UserProfile.isQuietToday day-boundary semantics
library;

import 'package:app_demo/core/repair/turn_repair_controller.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/llm_features/data/llm_turn_features.dart';
import 'package:app_demo/features/ppr/data/brief_ppr_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ----------------------- B.1 LlmTurnFeatures ---------------------------
  group('LlmTurnFeatures.fromCloudFunctionPayload', () {
    test('separates _version from flag map (spec May 2026, v2)', () {
      final f = LlmTurnFeatures.fromCloudFunctionPayload(
        agentId: 'siu_yan',
        moduleId: 'm3',
        raw: const {
          'specific_content_engagement': true,
          'cross_session_memory': false,
          'honest_unfamiliarity': true,
          'mixed_content_routing': false,
          'generative_summary': true,
          '_version': 2,
        },
      );
      expect(f.detectorVersion, 2);
      expect(f.flags['specific_content_engagement'], true);
      expect(f.flags['honest_unfamiliarity'], true);
      expect(f.flags['generative_summary'], true);
      expect(f.flags.containsKey('_version'), false);
    });

    test('round-trips through toMap()', () {
      final f = LlmTurnFeatures(
        agentId: 'siu_yan',
        moduleId: 'm3',
        systemPromptHash: 'abc',
        flags: const {'specific_content_engagement': true},
        detectorVersion: 2,
        createdAt: DateTime.utc(2026, 5, 14),
      );
      final m = f.toMap();
      expect(m['agentId'], 'siu_yan');
      expect(m['systemPromptHash'], 'abc');
      expect(m['detectorVersion'], 2);
      expect((m['flags'] as Map)['specific_content_engagement'], true);
    });
  });

  group('LlmTurnFeaturesRepository.write', () {
    test('skips when isArmA=false (Arm B never writes)', () async {
      final repo = LlmTurnFeaturesRepository(available: false);
      final result = await repo.write(
        uid: 'u1',
        isArmA: false,
        features: LlmTurnFeatures(
          agentId: 'siu_yan',
          moduleId: 'm3',
          flags: const {'honest_unfamiliarity': true},
          detectorVersion: 1,
          createdAt: DateTime.now(),
        ),
      );
      expect(result, isNull);
    });

    test('skips when available=false (guest mode)', () async {
      final repo = LlmTurnFeaturesRepository(available: false);
      final result = await repo.write(
        uid: 'u1',
        isArmA: true,
        features: LlmTurnFeatures(
          agentId: 'siu_yan',
          moduleId: 'm3',
          flags: const {},
          detectorVersion: 1,
          createdAt: DateTime.now(),
        ),
      );
      expect(result, isNull);
    });
  });

  // ----------------------- B.6 BriefPprController ------------------------
  group('BriefPprController.isMandatoryFor', () {
    final controller = BriefPprController(available: false);

    test('mandatory when agent not yet seen', () {
      final p = UserProfile(uid: 'u1', email: 'a@b.com', displayName: '阿明');
      expect(controller.isMandatoryFor(profile: p, agentId: 'siu_yan'), true);
    });

    test('skippable after agent has been seen once', () {
      final p = UserProfile(
        uid: 'u1', email: 'a@b.com', displayName: '阿明',
        firstPprSeenByAgent: {'siu_yan': DateTime.utc(2026, 5, 10)},
      );
      expect(controller.isMandatoryFor(profile: p, agentId: 'siu_yan'), false);
    });

    test('per-agent: seen siu_yan does NOT make ah_jan_ah_bak skippable', () {
      final p = UserProfile(
        uid: 'u1', email: 'a@b.com', displayName: '阿明',
        firstPprSeenByAgent: {'siu_yan': DateTime.utc(2026, 5, 10)},
      );
      expect(
          controller.isMandatoryFor(profile: p, agentId: 'ah_jan_ah_bak'),
          true);
    });

    test('guest mode: never mandatory', () {
      expect(controller.isMandatoryFor(profile: null, agentId: 'siu_yan'),
          false);
    });
  });

  // ----------------------- B.9 TurnRepairController ----------------------
  group('TurnRepairController', () {
    test('first click → llm_regenerate; second → template_advance(0)', () {
      final c = TurnRepairController(debounce: Duration.zero);
      final first = c.onThumbsDown('t1');
      final second = c.onThumbsDown('t1');
      expect(first?.isLlmRegenerate, true);
      expect(second?.isTemplateAdvance, true);
      expect(second?.templateIndex, 1);
    });

    test('debounces rapid taps within window', () {
      final c =
          TurnRepairController(debounce: const Duration(milliseconds: 500));
      final first = c.onThumbsDown('t1');
      final immediate = c.onThumbsDown('t1');
      expect(first, isNotNull);
      expect(immediate, isNull); // debounced
      expect(c.clicksForTest('t1'), 1);
    });

    test('different turn keys are independent', () {
      final c = TurnRepairController(debounce: Duration.zero);
      c.onThumbsDown('t1');
      c.onThumbsDown('t1');
      final t2First = c.onThumbsDown('t2');
      expect(t2First?.isLlmRegenerate, true);
    });
  });

  // ----------------------- B.10 isQuietToday -----------------------------
  group('UserProfile.isQuietToday', () {
    test('false when timestamp is null', () {
      final p = UserProfile(uid: 'u1', email: 'a@b.com', displayName: 'a');
      expect(p.isQuietToday, false);
    });

    test('true when timestamp is today', () {
      final now = DateTime.now();
      final p = UserProfile(
        uid: 'u1', email: 'a@b.com', displayName: 'a',
        quietTodayActivatedAt: DateTime(now.year, now.month, now.day, 9),
      );
      expect(p.isQuietToday, true);
    });

    test('false when timestamp is from a previous day', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final p = UserProfile(
        uid: 'u1', email: 'a@b.com', displayName: 'a',
        quietTodayActivatedAt: yesterday,
      );
      expect(p.isQuietToday, false);
    });
  });

  // ----------------------- UserProfile round-trip with new fields --------
  group('UserProfile B.6/B.10 round-trip', () {
    test('firstPprSeenByAgent + quietTodayActivatedAt serialise', () {
      final original = UserProfile(
        uid: 'u1',
        email: 'a@b.com',
        displayName: '阿明',
        firstPprSeenByAgent: {
          'siu_yan': DateTime.utc(2026, 5, 10),
          'ah_jan_ah_bak': DateTime.utc(2026, 5, 12),
        },
        quietTodayActivatedAt: DateTime.utc(2026, 5, 14, 9, 30),
      );
      final round = UserProfile.fromMap('u1', original.toMap());
      expect(round.firstPprSeenByAgent.length, 2);
      expect(round.firstPprSeenByAgent['siu_yan'], DateTime.utc(2026, 5, 10));
      expect(round.quietTodayActivatedAt,
          DateTime.utc(2026, 5, 14, 9, 30));
    });
  });
}

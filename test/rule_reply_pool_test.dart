// Decision 0023 — Arm B template-reply pool format and pick rules.
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_picker.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_service.dart';
import 'package:app_demo/features/rule_replies/rule_reply_safety.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pool format', () {
    test('ids are unique; 41 entries', () {
      final ids = RuleReplyPool.entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 41);
    });

    test('each mood band has 4 entries per agent; G-1 for none', () {
      for (final agent in ['siu_yan', 'ah_jan_ah_bak']) {
        for (var mood = 1; mood <= 5; mood++) {
          final pool = RuleReplyPool.subPool(
            agent: agent,
            band: RuleReplyPool.bandFor(mood),
          );
          expect(pool.length, 4, reason: '$agent mood $mood');
          expect(pool.every((e) => e.agent == agent), isTrue);
        }
        expect(
          RuleReplyPool.subPool(agent: agent, band: 'none').map((e) => e.id),
          ['G-1'],
        );
      }
    });

    test('grief → Z5, whatever the agent asks for', () {
      expect(
        RuleReplyPool.subPool(agent: 'ah_jan_ah_bak', band: 'grief')
            .map((e) => e.id),
        ['Z5-1', 'Z5-2', 'Z5-3', 'Z5-4'],
      );
    });

    test('pending characters keep the pool off by default', () {
      expect(RuleReplyPool.hasPlaceholderText, isFalse);
      expect(RuleReplyPool.hasPendingConfirmation, isTrue);
      expect(RuleReplyPool.hasPlaceholders, isTrue);
      if (!FeatureFlags.ruleTemplateRepliesAllowPlaceholder) {
        expect(RuleReplyPool.enabled, isFalse);
      }
    });

    test('mood rank → band (5 = 好開心 … 1 = 好唔開心), none when not picked',
        () {
      expect([1, 2, 3, 4, 5, null].map(RuleReplyPool.bandFor).toList(), [
        'very_unhappy',
        'not_good',
        'so_so',
        'good',
        'very_happy',
        'none',
      ]);
      String group(int mood) => RuleReplyPool.subPool(
            agent: 'siu_yan',
            band: RuleReplyPool.bandFor(mood),
          ).first.id.substring(0, 2);
      expect([5, 4, 3, 2, 1].map(group).toList(),
          ['X1', 'X2', 'X3', 'X4', 'X5']);
    });
  });

  group('picker', () {
    final pool = RuleReplyPool.subPool(
      agent: 'siu_yan',
      band: 'very_unhappy',
    ); // 4 entries

    test('first unused entry, in pool order', () {
      expect(RuleReplyPicker.pick(pool, const [])!.id, pool[0].id);
      expect(RuleReplyPicker.pick(pool, [pool[0].id])!.id, pool[1].id);
    });

    test('no repeat within the last N; LRU when all were used', () {
      var recent = <String>[];
      final seen = <String>[];
      for (var i = 0; i < 9; i++) {
        final e = RuleReplyPicker.pick(pool, recent)!;
        seen.add(e.id);
        recent = RuleReplyPicker.remember(recent, e.id);
      }
      for (var i = 1; i < seen.length; i++) {
        final window = seen.sublist(
          i - RuleReplyPool.recentWindow < 0
              ? 0
              : i - RuleReplyPool.recentWindow,
          i,
        );
        if (window.length < pool.length) {
          expect(window.contains(seen[i]), isFalse, reason: 'step $i');
        }
      }
      // Four-entry sub-pool with N = 3: the one not in the last 3.
      expect(
        RuleReplyPicker.pick(pool, [pool[3].id, pool[0].id, pool[1].id])!.id,
        pool[2].id,
      );
      // One-entry sub-pool (G-1): always that entry.
      final g = RuleReplyPool.subPool(agent: 'ah_jan_ah_bak', band: 'none');
      expect(RuleReplyPicker.pick(g, [g[0].id])!.id, 'G-1');
    });

    test('remember keeps the last N ids', () {
      expect(RuleReplyPicker.remember(['a', 'b', 'c'], 'd'), ['b', 'c', 'd']);
    });
  });

  test('service rotates through the sub-pool per agent', () async {
    final store = InMemoryRuleReplyHistoryStore();
    final s = RuleReplyService(store: store);
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      final e = await s.next(
        uid: null,
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        theme: 'check_in',
        mood: 1,
      );
      ids.add(e!.id);
    }
    expect(ids, ['X5-1', 'X5-2', 'X5-3', 'X5-4']);
  });

  test('service: grief ignores the mood and uses Z5', () async {
    final s = RuleReplyService(store: InMemoryRuleReplyHistoryStore());
    final e = await s.next(
      uid: null,
      agentId: 'ah_jan_ah_bak',
      moduleId: 'm3_reminiscence_w1',
      theme: 'w1',
      mood: 5,
      grief: true,
    );
    expect(e!.id, 'Z5-1');
  });

  test('safety gate: moderate / acute block the reply, low does not', () {
    const d = DistressDetector();
    expect(allowsTemplateReply(d.analyze('今日去咗飲茶')), isTrue);
    expect(allowsTemplateReply(d.analyze('我真係想死')), isFalse);
    expect(allowsTemplateReply(d.analyze('冇人理我')), isFalse);
    expect(
      allowsTemplateReply(const DistressMatch(DistressLevel.low, 'x')),
      isTrue,
    );
    expect(
      allowsTemplateReply(
        const DistressMatch(DistressLevel.moderateReview, 'x'),
      ),
      isFalse,
    );
  });

  test('T33 route: grief → Z5 on reminiscence only; crisis never', () {
    const d = DistressDetector();
    RuleReplyRoute r(String t, {required bool remi}) =>
        ruleReplyRoute(d.analyze(t), griefTemplates: remi);
    expect(r('今日去咗飲茶', remi: true), RuleReplyRoute.byMood);
    expect(r('老伴走咗之後好難過', remi: true), RuleReplyRoute.grief);
    expect(r('老伴走咗之後好難過', remi: false), RuleReplyRoute.none);
    expect(r('冇人理我', remi: true), RuleReplyRoute.none);
    expect(r('我真係想死', remi: true), RuleReplyRoute.none);
  });
}

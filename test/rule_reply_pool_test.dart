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
    test('ids are unique', () {
      final ids = RuleReplyPool.entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every sub-pool the pages can ask for is non-empty', () {
      for (final band in ['low', 'mid', 'high', 'none']) {
        expect(
          RuleReplyPool.subPool(
            agent: 'siu_yan',
            theme: 'check_in',
            band: band,
          ),
          isNotEmpty,
          reason: 'siu_yan check_in $band',
        );
        for (var w = 1; w <= 4; w++) {
          expect(
            RuleReplyPool.subPool(
              agent: 'ah_jan_ah_bak',
              theme: RuleReplyPool.themeForWeek(w),
              band: band,
            ),
            isNotEmpty,
            reason: 'ah_jan w$w $band',
          );
        }
      }
    });

    test('pool still holds placeholder text, so it is off by default', () {
      expect(RuleReplyPool.hasPlaceholders, isTrue);
      for (final e in RuleReplyPool.entries) {
        expect(
          e.zh.startsWith(RuleReplyPool.placeholderMarker),
          isTrue,
          reason: e.id,
        );
        expect(e.en.startsWith('[PLACEHOLDER]'), isTrue, reason: e.id);
      }
      if (!FeatureFlags.ruleTemplateRepliesAllowPlaceholder) {
        expect(RuleReplyPool.enabled, isFalse);
      }
    });

    test('mood bands: 1–2 low, 3 mid, 4–5 high, none when not picked', () {
      expect([1, 2, 3, 4, 5, null].map(RuleReplyPool.bandFor).toList(), [
        'low',
        'low',
        'mid',
        'high',
        'high',
        'none',
      ]);
    });

    test('check-in has no "none" sub-pool and falls back to mid', () {
      final none = RuleReplyPool.subPool(
        agent: 'siu_yan',
        theme: 'check_in',
        band: 'none',
      );
      expect(none.every((e) => e.band == 'mid'), isTrue);
    });
  });

  group('picker', () {
    final pool = RuleReplyPool.subPool(
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'low',
    ); // 3 entries

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
      // Two-entry sub-pool with N = 3: alternates, oldest first.
      final two = RuleReplyPool.subPool(
        agent: 'ah_jan_ah_bak',
        theme: 'w1',
        band: 'mid',
      );
      expect(two.length, 2);
      expect(RuleReplyPicker.pick(two, [two[0].id, two[1].id])!.id, two[0].id);
      expect(RuleReplyPicker.pick(two, [two[1].id, two[0].id])!.id, two[1].id);
    });

    test('remember keeps the last N ids', () {
      expect(RuleReplyPicker.remember(['a', 'b', 'c'], 'd'), ['b', 'c', 'd']);
    });
  });

  test('service rotates through the sub-pool per agent', () async {
    final store = InMemoryRuleReplyHistoryStore();
    final s = RuleReplyService(store: store);
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      final e = await s.next(
        uid: null,
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        theme: 'check_in',
        mood: 1,
      );
      ids.add(e!.id);
    }
    expect(ids.toSet().length, 3);
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
}

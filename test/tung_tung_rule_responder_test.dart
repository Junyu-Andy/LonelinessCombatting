import 'package:app_demo/features/curious_companion/data/tung_tung_rule_pool.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_rule_responder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TungTungRuleResponder (Arm B)', () {
    test('matches a topic by keyword', () {
      final r = TungTungRuleResponder.reply('我今日去咗飲茶', userTurnIndex: 0);
      expect(r.id, startsWith('food_'));
    });

    test('health outranks food so 食藥 never gets a food template', () {
      final r = TungTungRuleResponder.reply('我啱啱食咗藥', userTurnIndex: 0);
      expect(r.id, startsWith('health_'));
    });

    test('falls back to a generic template', () {
      final r = TungTungRuleResponder.reply('嗯', userTurnIndex: 0);
      expect(r.id, startsWith('generic_'));
    });

    test('matches English keywords case-insensitively', () {
      final r = TungTungRuleResponder.reply('I love Dim Sum', userTurnIndex: 0);
      expect(r.id, startsWith('food_'));
    });

    test('is deterministic for the same text and turn', () {
      final a = TungTungRuleResponder.reply('今日好熱', userTurnIndex: 4);
      final b = TungTungRuleResponder.reply('今日好熱', userTurnIndex: 4);
      expect(a.id, b.id);
      expect(a.zh, b.zh);
    });

    test('varies the template across turns within a topic', () {
      final ids = {
        for (var i = 0; i < 3; i++)
          TungTungRuleResponder.reply('聽歌', userTurnIndex: i).id,
      };
      expect(ids.length, greaterThan(1));
    });

    test('appends a pool opener every third user turn only', () {
      for (var i = 0; i < 9; i++) {
        final r = TungTungRuleResponder.reply('嗯', userTurnIndex: i);
        final expectOpener =
            (i + 1) % TungTungRuleResponder.openerEvery == 0;
        expect(r.openerId != null, expectOpener, reason: 'turn $i');
        if (expectOpener) {
          final ids = TungTungRulePool.items.map((o) => o.id);
          expect(ids, contains(r.openerId));
        }
      }
    });

    test('never echoes the user\'s own words (no specific-content engagement)',
        () {
      const input = '我個孫仔阿明今日嚟探我食點心';
      for (var i = 0; i < 6; i++) {
        final r = TungTungRuleResponder.reply(input, userTurnIndex: i);
        expect(r.zh.contains('阿明'), isFalse);
        expect(r.zh.contains('孫仔'), isFalse);
      }
    });

    test('templates avoid attachment phrasing banned in the agent prompts',
        () {
      const banned = ['我掛住你', '我會諗起你', '我會喺度等你', '下次見'];
      for (final text in [
        '食', '歌', '戲', '行街', '天氣', '麻雀', '貓', '過年', '以前', '藥', '嗯',
      ]) {
        for (var i = 0; i < 6; i++) {
          final r = TungTungRuleResponder.reply(text, userTurnIndex: i);
          for (final b in banned) {
            expect(r.zh.contains(b), isFalse, reason: '${r.id}: $b');
          }
          expect(r.zh.trim(), isNotEmpty);
          expect(r.en.trim(), isNotEmpty);
        }
      }
    });
  });
}

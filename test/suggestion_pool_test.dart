import 'package:app_demo/features/social_suggestions/data/suggestion_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SuggestionPool rotation', () {
    test('rotates deterministically by seed', () {
      const pool = SuggestionPool();
      final a = pool.rotate(seed: 0);
      final b = pool.rotate(seed: 0);
      expect(a.map((s) => s.id), b.map((s) => s.id));
    });

    test('different seeds produce different first pick across the pool', () {
      const pool = SuggestionPool();
      final ids = <String>{};
      for (var i = 0; i < SuggestionPool.all.length; i++) {
        ids.add(pool.rotate(seed: i, count: 1).first.id);
      }
      // Every offset should land on a distinct first item.
      expect(ids.length, SuggestionPool.all.length);
    });

    test('returns the requested count, wrapping around if necessary', () {
      const pool = SuggestionPool();
      final picks = pool.rotate(seed: 0, count: 3);
      expect(picks.length, 3);
    });

    test('seeds covering all four types exist', () {
      // Sanity check the pool is balanced across spec-required types.
      final types = SuggestionPool.all.map((s) => s.type).toSet();
      expect(types, containsAll(SuggestionType.values));
    });
  });
}

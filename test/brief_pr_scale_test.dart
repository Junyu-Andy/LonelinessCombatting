import 'package:app_demo/features/brief_pr/data/brief_pr_response.dart';
import 'package:flutter_test/flutter_test.dart';

/// C1 — locks the Brief PR 1–7 scale change: schemaVersion bumped, raw
/// integer values stored (S4 not reverse-scored), skip distinguishable.
void main() {
  test('completed response stamps schemaVersion 2 and stores raw 1–7', () {
    final r = BriefPrResponse(
      agentId: 'siu_yan',
      agentDisplayName: '小欣',
      understanding: 7,
      validation: 6,
      caring: 5,
      insensitivity: 2, // raw, NOT reverse-scored at write time
      isAnchorPrompt: false,
      status: 'completed',
      promptedAt: DateTime(2026, 6, 7),
      respondedAt: DateTime(2026, 6, 7),
      arm: 'A',
    );
    final m = r.toFirestore();
    expect(m['schemaVersion'], 2);
    expect(BriefPrResponse.currentSchemaVersion, 2);
    expect(m['understanding'], 7);
    expect(m['insensitivity'], 2); // stored raw — analysis applies 8 - x
    expect(m['status'], 'completed');
  });

  test('skipped response keeps null values + schemaVersion, status skipped', () {
    final r = BriefPrResponse(
      agentId: 'tung_tung',
      agentDisplayName: '通通',
      isAnchorPrompt: false,
      status: 'skipped',
      promptedAt: DateTime(2026, 6, 7),
      respondedAt: DateTime(2026, 6, 7),
      arm: 'A',
    );
    final m = r.toFirestore();
    expect(m['schemaVersion'], 2);
    expect(m['understanding'], isNull);
    expect(m['validation'], isNull);
    expect(m['caring'], isNull);
    expect(m['insensitivity'], isNull);
    expect(m['status'], 'skipped'); // distinguishable from missing
  });
}

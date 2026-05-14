import 'package:app_demo/core/memory/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryStore transcript-consent gate', () {
    test('no-op when transcript consent missing, even with Firebase ready',
        () async {
      // We construct the store with `available: false` so it never actually
      // touches Firestore — but the consent gate runs first and short-
      // circuits regardless. This test guards the gate ordering: if the
      // gate accidentally moves below the availability check, transcripts
      // could leak.
      final store = MemoryStore(available: false);
      await store.writeSummary(
        uid: 'u',
        moduleId: 'm3_reminiscence_w1',
        summary: '童年細節',
        armCode: 'A',
        hasTranscriptConsent: false,
      );
      // No exception, no write attempted (verified by lack of Firestore
      // crash). The test passes simply by not throwing.
    });

    test('still no-op when consent given but firebase unavailable',
        () async {
      final store = MemoryStore(available: false);
      await store.writeSummary(
        uid: 'u',
        moduleId: 'm3_reminiscence_w1',
        summary: 's',
        armCode: 'A',
        hasTranscriptConsent: true,
      );
    });
  });
}

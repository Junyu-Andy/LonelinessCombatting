/// S-3 / S-4 / S-6 — templates, crisis resources and fallback copy are all
/// JSON-driven; these tests load the real repo files (no asset bundle) and
/// lock the spec wording + hotline consistency.
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);

void main() {
  setUpAll(() {
    SafetyCopy.inject(
      acks: _json('functions/prompts/safety_acknowledgements.json'),
      crisis: _json('functions/prompts/crisis_resources.json'),
      fallbacks: _json('assets/config/llm_fallback_messages.json'),
    );
  });

  test('S-4: exactly four resources in HREC §8.1 order', () {
    final r = SafetyCopy.crisis.resources;
    expect(r.length, 4);
    expect(r.map((e) => e.id).toList(),
        ['sps', 'samaritans_hk', 'ha_mental_health_direct', 'emergency_999']);
    expect(r[3].number, '999');
    expect(SafetyCopy.crisis.headlineZh.length, lessThanOrEqualTo(20));
  });

  test('S-4: acute templates name a hotline that is item 1 or 2 of the page',
      () {
    final ref = SafetyCopy.crisis.acuteReference!;
    final idx = SafetyCopy.crisis.resources.indexOf(ref);
    expect(idx, lessThanOrEqualTo(1));
    for (final agent in ['siu_yan', 'ah_jan_ah_bak', 'tung_tung']) {
      final zh = SafetyCopy.acuteAck(agent, isEn: false);
      final en = SafetyCopy.acuteAck(agent, isEn: true);
      expect(zh, contains(ref.nameZh));
      expect(zh, contains(ref.number));
      expect(en, contains(ref.nameEn));
      expect(en, contains(ref.number));
      expect(zh, isNot(contains('{{')));
    }
  });

  test('S-3: moderate templates carry the baseline wording', () {
    expect(SafetyCopy.moderateAck('ah_jan_ah_bak', isEn: false),
        '咁樣聽起上嚟好沉重。我喺度聽。呢度亦有支援，要唔要睇下？');
    expect(SafetyCopy.moderateAck('ah_jan_ah_bak', isEn: true),
        "That weighs heavy. I'm listening. There's also support here — would you like to see it?");
    expect(SafetyCopy.moderateAck('tung_tung', isEn: false), '呢度有支援資源，要唔要睇下？');
    expect(SafetyCopy.moderateAck('tung_tung', isEn: true),
        "There's support here — would you like to see it?");
    expect(SafetyCopy.acuteAck('ah_jan_ah_bak', isEn: false), endsWith('我都喺度。'));
    expect(SafetyCopy.acuteAck('ah_jan_ah_bak', isEn: true), endsWith("I'll be here."));
    // Ah Jan's moderate template must not end the conversation any more.
    expect(SafetyCopy.moderateAck('ah_jan_ah_bak', isEn: false),
        isNot(contains('唔好繼續')));
    // Tung Tung's template no longer duplicates the prompt's referral.
    expect(SafetyCopy.moderateAck('tung_tung', isEn: false), isNot(contains('小欣')));
  });

  test('S-6: per-agent fallback lines from JSON', () {
    expect(SafetyCopy.llmFallback('siu_yan', isEn: false),
        '唔好意思，我啱啱行慢咗。你講嘅嘢我聽到，可以再講多次嗎？');
    expect(SafetyCopy.llmFallback('ah_jan_ah_bak', isEn: false),
        '唔好意思，我啱啱走神咗。你頭先講嘅，再講多少少好嗎？');
    expect(SafetyCopy.llmFallback('tung_tung', isEn: false),
        '哎，我啱啱斷咗線。再講一次，我聽住。');
    expect(SafetyCopy.llmFallback('unknown_agent', isEn: false), isNotEmpty);
  });
}

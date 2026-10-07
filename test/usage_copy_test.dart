import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/agent_profile/data/agent_profile_content.dart';
import 'package:app_demo/features/agent_profile/data/agent_profile_usage_copy.dart';
import 'package:flutter_test/flutter_test.dart';

/// T20 — usage-frequency copy from `app_config/usage_copy`.  Without a
/// signed-off value every site must show exactly today's text.
void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  group('UsageCopy.fromMap', () {
    test('keeps only known, non-empty, non-placeholder strings', () {
      final copy = UsageCopy.fromMap({
        'siu_yan_tile_subtitle_zh': '新字',
        'siu_yan_tile_subtitle_en': '【占位】建議每日用',
        'siu_yan_first_intro_zh': '   ',
        'siu_yan_first_intro_en': 42,
        'unknown_key_zh': '唔應該用',
      });
      expect(copy.text(UsageCopy.siuYanTileSubtitle,
          isEn: false, fallback: 'x'), '新字');
      expect(copy.text(UsageCopy.siuYanTileSubtitle,
          isEn: true, fallback: 'x'), 'x');
      expect(copy.text(UsageCopy.siuYanFirstIntro,
          isEn: false, fallback: 'x'), 'x');
      expect(copy.text(UsageCopy.siuYanFirstIntro,
          isEn: true, fallback: 'x'), 'x');
      expect(copy.text('unknown_key', isEn: false, fallback: 'x'), 'x');
    });

    test('an empty document falls back everywhere', () {
      final copy = UsageCopy.fromMap(const {});
      for (final key in UsageCopy.keys) {
        expect(copy.text(key, isEn: false, fallback: 'orig'), 'orig');
        expect(copy.text(key, isEn: true, fallback: 'orig'), 'orig');
      }
    });
  });

  group('default copy is unchanged', () {
    test('Siu Yan tile subtitle and first intro', () {
      final siuYan = AgentRegistry.byId(AgentRegistry.siuYanId);
      expect(siuYan.tileSubtitleZh, '日日陪你傾偈，聽你今日點');
      expect(siuYan.tileSubtitleEn, 'Daily companion — hears how you are');
      final intro = AgentRegistry.introTextFor('siu_yan_v1')!;
      expect(intro.zh, startsWith('你好啊，我係小欣，一個 AI 機械人。我會喺日日陪你傾下偈，'));
    });

    test('profile intros are returned as written', () {
      for (final entry in profileIntros.entries) {
        final agentId = entry.key.startsWith('ah_jan_ah_bak')
            ? AgentRegistry.ahJanAhBakId
            : entry.key;
        final out = withUsageCopy(agentId, entry.value);
        expect(out.opening, entry.value.opening);
        expect(out.capabilities, entry.value.capabilities);
        expect(out.limitations, entry.value.limitations);
        expect(out.closing, entry.value.closing);
      }
      expect(profileIntros['siu_yan']!.capabilities,
          contains(siuYanMoodCapabilityLine));
      expect(profileIntros['ah_jan_ah_bak_feminine']!.capabilities,
          contains(ahJanAhBakWeeklyCapabilityLine));
    });
  });

  group('signed-off copy replaces only its own site', () {
    setUp(() {
      UsageCopy.current = UsageCopy.fromMap({
        'siu_yan_tile_subtitle_zh': 'T-ZH',
        'siu_yan_first_intro_zh': 'I-ZH',
        'siu_yan_profile_opening_zh': 'O-ZH',
        'siu_yan_profile_mood_capability_zh': 'M-ZH',
        'ah_jan_ah_bak_profile_weekly_capability_zh': 'W-ZH',
      });
    });

    test('registry', () {
      expect(AgentRegistry.byId(AgentRegistry.siuYanId).tileSubtitleZh, 'T-ZH');
      // English not configured → today's English.
      expect(AgentRegistry.byId(AgentRegistry.siuYanId).tileSubtitleEn,
          'Daily companion — hears how you are');
      expect(AgentRegistry.byId(AgentRegistry.tungTungId).tileSubtitleZh,
          '同你傾下你鍾意嘅嘢');
      expect(AgentRegistry.introTextFor('siu_yan_v1')!.zh, 'I-ZH');
      expect(AgentRegistry.introTextFor('tung_tung_v1')!.zh,
          startsWith('你好，我係通通'));
    });

    test('profiles', () {
      final siuYan =
          withUsageCopy(AgentRegistry.siuYanId, profileIntros['siu_yan']!);
      expect(siuYan.opening, 'O-ZH');
      expect(siuYan.capabilities.first, 'M-ZH');
      expect(siuYan.capabilities.length,
          profileIntros['siu_yan']!.capabilities.length);
      final ahJan = withUsageCopy(
          AgentRegistry.ahJanAhBakId, profileIntros['ah_jan_ah_bak_masculine']!);
      expect(ahJan.capabilities.first, 'W-ZH');
      expect(ahJan.opening, profileIntros['ah_jan_ah_bak_masculine']!.opening);
    });
  });
}

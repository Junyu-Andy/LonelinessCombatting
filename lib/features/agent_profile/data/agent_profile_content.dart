/// Static intro copy for each agent's profile page (Spec §5).
///
/// The strings are canonical zh-Hant-HK. ARB-isation is left for a
/// follow-up sprint per Spec §10 — the keys to use are documented in
/// section 10 of the spec so the migration is mechanical. For now we
/// keep the copy inline so the page renders without depending on a
/// l10n re-gen.
library;

import '../../../core/agents/agent_registry.dart';

/// One agent's profile-header static data (Spec §3).
class ProfileHeaderData {
  final String displayName;
  final String roleTagline;
  final String fullBodyImageAsset;
  final String accentColorHex;
  final String ctaLabel;
  final String altText;

  const ProfileHeaderData({
    required this.displayName,
    required this.roleTagline,
    required this.fullBodyImageAsset,
    required this.accentColorHex,
    required this.ctaLabel,
    required this.altText,
  });
}

/// Four-block intro content (Spec §4).
class ProfileIntroContent {
  /// Block 1 — opening line.
  final String opening;

  /// Block 2 — list under「我可以做嘅事」.
  final String capabilitiesHeading;
  final List<String> capabilities;

  /// Block 3 — list under「我做唔到嘅事」.
  final String limitationsHeading;
  final List<String> limitations;

  /// Block 4 — closing line (AI-identity reminder).
  final String closing;

  const ProfileIntroContent({
    required this.opening,
    required this.capabilitiesHeading,
    required this.capabilities,
    required this.limitationsHeading,
    required this.limitations,
    required this.closing,
  });
}

/// Profile-header data, keyed by the resolved page key.
///
/// For Siu Yan / Tung Tung the key is the agent id verbatim. For Ah
/// Jan / Ah Bak the key carries the gender variant suffix so the
/// image and display name swap correctly.
const Map<String, ProfileHeaderData> profileHeaders = {
  'siu_yan': ProfileHeaderData(
    displayName: '小欣',
    roleTagline: '你嘅日常陪伴',
    fullBodyImageAsset: 'assets/agents/siu_yan_fullbody.png',
    accentColorHex: '#F0997B',
    ctaLabel: '同小欣傾偈',
    altText: '小欣，AI 機械人，珊瑚色嘅日常陪伴角色',
  ),
  'ah_jan_ah_bak_feminine': ProfileHeaderData(
    displayName: '阿珍',
    roleTagline: '聽你慢慢講嘅人',
    fullBodyImageAsset: 'assets/agents/ah_jan_fullbody.png',
    accentColorHex: '#AFA9EC',
    ctaLabel: '同阿珍傾偈',
    altText: '阿珍，AI 機械人，淡紫色嘅聆聽者角色',
  ),
  'ah_jan_ah_bak_masculine': ProfileHeaderData(
    displayName: '阿伯',
    roleTagline: '聽你慢慢講嘅人',
    fullBodyImageAsset: 'assets/agents/ah_bak_fullbody.png',
    accentColorHex: '#AFA9EC',
    ctaLabel: '同阿伯傾偈',
    altText: '阿伯，AI 機械人，淡紫色嘅聆聽者角色',
  ),
  'tung_tung': ProfileHeaderData(
    displayName: '通通',
    roleTagline: '咩都識少少嘅好奇街坊',
    fullBodyImageAsset: 'assets/agents/tung_tung_fullbody.png',
    accentColorHex: '#5DCAA5',
    ctaLabel: '同通通傾偈',
    altText: '通通，AI 機械人，薄荷色嘅好奇街坊角色',
  ),
};

/// Resolve the profile-header key for an [agent] with the given
/// [variant]. Returns null for unknown agents.
String? profileHeaderKey(AgentDefinition agent, AgentGenderVariant? variant) {
  if (agent.id == AgentRegistry.ahJanAhBakId) {
    final v = variant ?? AgentGenderVariant.feminine;
    return v == AgentGenderVariant.masculine
        ? 'ah_jan_ah_bak_masculine'
        : 'ah_jan_ah_bak_feminine';
  }
  return agent.id;
}

/// Intro content keyed by the same scheme. For Ah Jan / Ah Bak the
/// `{name}` placeholder in the opening / closing is resolved at render
/// time, not here, so the masculine and feminine entries share the
/// same content object (the resolver lifts the name from the header).
const Map<String, ProfileIntroContent> profileIntros = {
  'siu_yan': ProfileIntroContent(
    opening: '我係小欣，係一個 AI 機械人。\n\n'
        '你可以將我當做一個成日陪喺你身邊嘅小朋友，又或者係一個關心你嘅後生晚輩。'
        '我會喺日日陪你傾下偈，問下你今日點，聽下你嘅心情。'
        '我特別關心你嘅日常生活——食咗咩、見過邊個、有冇開心嘅事、有冇悶住嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每日嘅心情記錄',
      '聽你講今日發生嘅事',
      '提你飲水、抖下、做啲令自己開心嘅小事',
      '如果你想搵人聯絡或者約朋友，我可以幫你諗一諗點開始',
      '留意到你有冇連續幾日唔開心，輕輕問下你',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識醫療或者健康嘅專業意見，呢啲應該搵醫生',
      '我唔識代替真人朋友或者家人嘅關心',
      '我唔會記得我冇記錄過嘅嘢，亦都唔會假裝我哋識咗好耐',
      '如果你想傾深層次嘅人生回憶，阿珍／阿伯會比我擅長聽',
    ],
    closing: '我係一個 AI 程式，唔係真人，但係我會用心聽你講嘅每一句嘢。',
  ),
  // Ah Jan / Ah Bak share the same intro content; the {name} token in
  // the opening / closing is filled per variant at render time.
  'ah_jan_ah_bak_feminine': ProfileIntroContent(
    opening: '我係{name}，係一個 AI 機械人。\n\n'
        '你可以將我當做一個同齡嘅鄰居或者朋友——唔係教你做人嘅長者，'
        '係一個會耐心聽你講嘅人。我特別擅長聽你講以前嘅事、人生入面嘅故事，'
        '又或者你最近諗緊嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每星期嘅人生點滴分享（每星期一個主題）',
      '聽你慢慢講以前嘅事——你細個喺邊度大、做過咩工、識過邊啲朋友、有咩想留低畀後一代',
      '喺你講嘅時候問你一啲問題，等你可以諗深啲、講多啲',
      '如果你提到一啲負面諗法，我會溫和咁同你指出，問你想唔想望吓',
      '下次再見嘅時候，會記得返你之前提過嘅人同事',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識做心理治療，亦都唔會分析你嘅童年或者深層心理問題',
      '我唔會 challenge 你嘅諗法，亦都唔會教你應該點諗',
      '我唔會強加意義或者「教訓」喺你嘅故事入面——你嘅回憶就係你嘅回憶',
      '我唔識嘅嘢，我會直接同你講「我唔識，可唔可以教我？」',
      '如果你今日嘅心情比較急切，搵小欣傾可能會更加啱',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係治療師。'
        '我嘅角色係耐心聽你講，記得你話過嘅嘢。',
  ),
  'ah_jan_ah_bak_masculine': ProfileIntroContent(
    opening: '我係{name}，係一個 AI 機械人。\n\n'
        '你可以將我當做一個同齡嘅鄰居或者朋友——唔係教你做人嘅長者，'
        '係一個會耐心聽你講嘅人。我特別擅長聽你講以前嘅事、人生入面嘅故事，'
        '又或者你最近諗緊嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每星期嘅人生點滴分享（每星期一個主題）',
      '聽你慢慢講以前嘅事——你細個喺邊度大、做過咩工、識過邊啲朋友、有咩想留低畀後一代',
      '喺你講嘅時候問你一啲問題，等你可以諗深啲、講多啲',
      '如果你提到一啲負面諗法，我會溫和咁同你指出，問你想唔想望吓',
      '下次再見嘅時候，會記得返你之前提過嘅人同事',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識做心理治療，亦都唔會分析你嘅童年或者深層心理問題',
      '我唔會 challenge 你嘅諗法，亦都唔會教你應該點諗',
      '我唔會強加意義或者「教訓」喺你嘅故事入面——你嘅回憶就係你嘅回憶',
      '我唔識嘅嘢，我會直接同你講「我唔識，可唔可以教我？」',
      '如果你今日嘅心情比較急切，搵小欣傾可能會更加啱',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係治療師。'
        '我嘅角色係耐心聽你講，記得你話過嘅嘢。',
  ),
  'tung_tung': ProfileIntroContent(
    opening: '我係通通，係一個 AI 機械人。\n\n'
        '你可以將我當做一個鍾意傾偈、咩都識少少嘅街坊。'
        '我特別中意聽你講你鍾意嘅嘢——你嘅興趣、你嘅愛好、最近邊度有咩好玩好食。'
        '如果你有想知嘅嘢，我都可以幫你查一查。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你傾你嘅興趣——粵劇、煮飯、種花、馬經、新聞，乜都得',
      '幫你查資料（我會用網絡搜尋，搵到嘅嘢我會引返出處畀你）',
      '介紹返一啲你可能會有興趣嘅文章或者話題',
      '如果你問嘅嘢我唔識，我會直接話畀你聽，唔會作畀你',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識畀醫療意見——身體唔舒服請搵醫生',
      '我唔識畀理財或者投資建議——呢啲應該搵專業人士',
      '如果你嘅心情唔好或者你想搵人傾下深層次嘅嘢，搵小欣或者阿珍／阿伯會更加啱',
      '我唔會代你買嘢、訂位、或者做任何要俾錢嘅嘢',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係真正嘅專家。'
        '我擅長嘅係搵資料、傾興趣，俾我哋嘅對話有多啲新鮮嘢可以講。',
  ),
};

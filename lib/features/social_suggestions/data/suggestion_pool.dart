/// Spec §M6: "rotating list of generic suggestions drawn from a fixed
/// pool of ~40 items grouped by effort level (low/medium/high) and type
/// (family/friend/community/solo-reflective)."
///
/// Sprint 3 ships an HK-flavoured seed pool (16 items). The full ~40
/// will be co-designed in Phase A — this list is meant to be edited.
/// Avoid Western-centric activities; lean local (yum cha, parks,
/// community centres, MTR-walkable distances).
enum SuggestionEffort { low, medium, high }

enum SuggestionType { family, friend, community, soloReflective }

class SocialSuggestion {
  final String id;
  final String zh;
  final String en;
  final SuggestionEffort effort;
  final SuggestionType type;
  const SocialSuggestion({
    required this.id,
    required this.zh,
    required this.en,
    required this.effort,
    required this.type,
  });
}

class SuggestionPool {
  const SuggestionPool();

  static const all = <SocialSuggestion>[
    // Family — low effort
    SocialSuggestion(
      id: 'family_text_morning',
      zh: '傳個「早晨」短訊畀屋企人。',
      en: 'Send a "good morning" text to a family member.',
      effort: SuggestionEffort.low,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_voice_note',
      zh: '錄個 30 秒語音畀仔女或孫，講今日見到咩。',
      en: 'Record a 30-second voice note for a child or grandchild '
          'about something you saw today.',
      effort: SuggestionEffort.low,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_share_photo',
      zh: '揀一張舊相分享畀屋企人，講個小故事。',
      en: 'Pick an old photo, share it with family with a short note.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_yum_cha',
      zh: '約屋企人去飲茶，唔使一定週末。',
      en: 'Invite family to yum cha — doesn\'t have to be the weekend.',
      effort: SuggestionEffort.high,
      type: SuggestionType.family,
    ),

    // Friend — low to high
    SocialSuggestion(
      id: 'friend_check_in',
      zh: '打畀好耐冇傾偈嘅朋友，問句最近點。',
      en: 'Call a friend you haven\'t spoken to in a while, just to say hi.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_morning_walk',
      zh: '約朋友早上喺公園散步 20 分鐘。',
      en: 'Walk in the park with a friend for 20 minutes in the morning.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_share_recipe',
      zh: '同朋友 WhatsApp 分享一個你鍾意嘅煮食方法。',
      en: 'WhatsApp a friend a recipe you enjoy making.',
      effort: SuggestionEffort.low,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_birthday_call',
      zh: '聽日有冇朋友生日？提早一日 send 個祝福。',
      en: 'Anyone\'s birthday tomorrow? Send a message a day early.',
      effort: SuggestionEffort.low,
      type: SuggestionType.friend,
    ),

    // Community — outings + groups
    SocialSuggestion(
      id: 'community_centre_visit',
      zh: '去屋企附近嘅長者中心睇下今個禮拜有咩活動。',
      en: 'Drop by the local community centre and see this week\'s events.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_morning_park',
      zh: '朝早去公園做下太極或者散步，留意吓有冇熟面孔。',
      en: 'Morning tai chi or stroll in the park — keep an eye out for '
          'familiar faces.',
      effort: SuggestionEffort.low,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_library',
      zh: '去公共圖書館坐一坐，揀一本書翻吓。',
      en: 'Spend an hour at the public library with one book.',
      effort: SuggestionEffort.low,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_volunteer_short',
      zh: '報名一個 1-2 小時嘅義工活動，唔使長期承諾。',
      en: 'Sign up for a 1–2 hour volunteer slot — no long commitment.',
      effort: SuggestionEffort.high,
      type: SuggestionType.community,
    ),

    // Solo-reflective
    SocialSuggestion(
      id: 'solo_letter',
      zh: '寫一封信畀以前嘅自己，唔需要寄。',
      en: 'Write a letter to your past self — you don\'t have to send it.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_three_things',
      zh: '寫低今日三件令你覺得平靜嘅事。',
      en: 'Write down three things today that felt calm.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_music',
      zh: '聽一首你後生時鍾意嘅歌，記低諗起嘅人或地方。',
      en: 'Play a song you loved when you were younger. Note who or where '
          'it brings to mind.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_window_watch',
      zh: '坐喺窗邊 10 分鐘，留意外面有咩動靜。',
      en: 'Sit by the window for 10 minutes and watch what passes.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
  ];

  /// Pick the next [count] suggestions deterministically from a rotation
  /// seed (e.g. day-of-year) so Arm B users see a stable but rotating
  /// set without us tracking shown-history.
  List<SocialSuggestion> rotate({required int seed, int count = 2}) {
    final list = [...all];
    final offset = seed.abs() % list.length;
    return List.generate(count, (i) => list[(offset + i) % list.length]);
  }
}

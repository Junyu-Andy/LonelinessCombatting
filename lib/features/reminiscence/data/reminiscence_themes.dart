/// Spec §M3: provisional 6-week reminiscence sequence. HK cultural
/// adaptation will land in a separate document (Module 3 thematic
/// curriculum). For the basic build, we keep the seven prompts the spec
/// lists, with light Cantonese examples baked into the opening line so
/// the participant immediately knows what kind of memory we mean.
class ReminiscenceTheme {
  final int weekIndex; // 1..6
  final String titleZh;
  final String titleEn;
  final String openingZh;
  final String openingEn;

  const ReminiscenceTheme({
    required this.weekIndex,
    required this.titleZh,
    required this.titleEn,
    required this.openingZh,
    required this.openingEn,
  });

  static const all = <ReminiscenceTheme>[
    ReminiscenceTheme(
      weekIndex: 1,
      titleZh: '童年同屋企',
      titleEn: 'Childhood & home',
      openingZh:
          '今個禮拜，不如傾下你細個住嘅地方。你最記得邊條街、邊個鋪頭、或者邊個鄰居？',
      openingEn:
          'This week, let\'s talk about where you grew up. What street, '
              'shop, or neighbour do you remember first?',
    ),
    ReminiscenceTheme(
      weekIndex: 2,
      titleZh: '後生時期同工作',
      titleEn: 'Young adulthood & work',
      openingZh: '今個禮拜想聽下你後生嗰陣嘅故事。你嘅第一份工係咩？嗰陣係點開始嘅？',
      openingEn:
          'This week I\'d love to hear about your younger years. What was '
              'your first job? How did it begin?',
    ),
    ReminiscenceTheme(
      weekIndex: 3,
      titleZh: '一生人嘅朋友',
      titleEn: 'Friendships across a lifetime',
      openingZh:
          '今個禮拜，諗下對你嚟講重要嘅朋友。有冇一個朋友，你會覺得無論幾耐冇見，見返都好似冇變？',
      openingEn:
          'This week, think about a friend who mattered to you. Is there '
              'someone you feel never really changed, no matter how long '
              'you went without seeing them?',
    ),
    ReminiscenceTheme(
      weekIndex: 4,
      titleZh: '人生嘅轉捩點',
      titleEn: 'Turning points',
      openingZh: '今個禮拜，講下一個對你嚟講最重要嘅決定。係幾時做嘅？事後諗返你會點睇？',
      openingEn:
          'This week, share a decision that mattered most to you. When did '
              'you make it? Looking back now, how do you see it?',
    ),
    ReminiscenceTheme(
      weekIndex: 5,
      titleZh: '驕傲同成就',
      titleEn: 'Pride & accomplishment',
      openingZh: '今個禮拜，分享一件令你覺得驕傲嘅事。可以好細件，唔使大事。',
      openingEn:
          'This week, share something you feel proud of. It can be small '
              '— it doesn\'t have to be a big achievement.',
    ),
    ReminiscenceTheme(
      weekIndex: 6,
      titleZh: '想留畀下一代嘅說話',
      titleEn: 'What I would tell the next generation',
      openingZh:
          '今個禮拜係最後一堂。如果你可以同年輕一代講一句說話，你想佢哋知道啲咩？',
      openingEn:
          'This is the final week. If you could leave one thing for the '
              'next generation to know, what would it be?',
    ),
  ];

  static ReminiscenceTheme byIndex(int weekIndex) {
    return all.firstWhere(
      (t) => t.weekIndex == weekIndex,
      orElse: () => all.first,
    );
  }
}

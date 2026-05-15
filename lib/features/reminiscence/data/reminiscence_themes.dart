/// Spec §M3: 4-week reminiscence curriculum (P2 plan, scaled down from
/// the prior 6-week prototype for the pilot cohort). Themes track the
/// dissertation's four protected windows: place of origin, working life,
/// friendships, and legacy. The HK cultural co-design will land
/// thematic refinements in a separate document; the four prompts here
/// keep the structure for the basic build.
class ReminiscenceTheme {
  final int weekIndex; // 1..4
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

  /// Total weeks in the curriculum. Referenced by the My Story tab and
  /// any reader that wants to display "Week N of {totalWeeks}".
  static const totalWeeks = 4;

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

/// 1020d (回憶 v2) — the one shared script for both arms: openers, the 32
/// questions, the rule arm's fixed lines, the closing line, button labels,
/// the rule arm's chapter short titles and the three chapter ratings.
///
/// Both arms read this file; the questions, their order, the openers and
/// the closing line are never written by the LLM.  The only difference
/// between the arms is what comes after an answer (Hybrid: one LLM
/// follow-up + one short LLM reply; rule arm: one fixed line).
///
/// Human table: docs/spec/copy/reminiscence-v2.md.  `test/reminiscence_v2_
/// copy_test.dart` checks the two word for word.  **Every elder-visible
/// line here is a draft (草稿)**; Junyu settles them from the PR
/// screenshots, then the table changes first and this file follows.
library;

class ReminiscenceV2Week {
  const ReminiscenceV2Week({
    required this.weekIndex,
    required this.themeZh,
    required this.questions,
    required this.shortTitles,
  });

  final int weekIndex;

  /// 本週主題 (the same four titles as `ReminiscenceTheme.titleZh`).
  final String themeZh;

  /// Q1 … Q8, verbatim from 1020d section 4 (Junyu confirmed 10/19).
  final List<String> questions;

  /// Rule arm chapter: one short title per question (drafts).
  final List<String> shortTitles;

  String question(int index) => questions[index - 1];
  String shortTitle(int index) => shortTitles[index - 1];
}

class ReminiscenceV2RatingItem {
  const ReminiscenceV2RatingItem(this.key, this.question, this.low, this.high);

  /// Field name in `reminiscence_chapter_ratings`.
  final String key;
  final String question;

  /// Words under 1 and under 7.
  final String low;
  final String high;
}

class ReminiscenceV2Copy {
  ReminiscenceV2Copy._();

  /// Written on every week doc (`configVersion`) so analysts can tell
  /// which wording an elder saw.
  static const version = 'reminiscence_v2.draft-20261020';

  static const questionsPerWeek = 8;

  /// The question after which the rule arm says [q7Line].
  static const hardshipQuestion = 7;

  // ---------------------------------------------------------------------
  // 1020o (4a) — the scene picture, the first bubble of each week (before
  // the opener; Junyu 10/20 第 91 条).  Both arms; no reply expected.
  // ---------------------------------------------------------------------

  /// The line under the week's picture, by week index.
  static const sceneLines = <int, String>{
    1: '睇吓呢幅圖，有冇令你諗起細個嘅日子？',
    2: '睇吓呢幅圖，有冇令你諗起後生嗰陣做嘢嘅日子？',
    3: '睇吓呢幅圖，有冇令你諗起一個老朋友？',
    4: '睇吓呢幅圖。今個禮拜，想聽下你想留畀後生一代嘅說話。',
  };

  /// The week's landscape picture (1024 × 768, 4:3).
  static String sceneAsset(int weekIndex) =>
      'assets/reminiscence/scene_$weekIndex.jpg';

  // ---------------------------------------------------------------------
  // Openers (section 3) — three bubbles.
  // ---------------------------------------------------------------------

  /// Week 1.  `{name}` = 阿珍 or 阿伯 (the elder's pairing).
  static const week1Opener = <String>[
    '你好，我係{name}。接落嚟幾個禮拜，我想陪你慢慢講返你人生入面唔同嘅日子，每個禮拜講一段。今個禮拜我哋講細個同屋企。我會問你幾條問題，想講幾多就講幾多，唔想講可以跳過，中途離開都會暫存。',
    '每個禮拜講完，我會幫你整理成一篇小文章，最後合埋就係你嘅人生小篇章。',
    '如果冇問題，我哋今日就由你細個住嘅地方講起。',
  ];

  /// Weeks 2–4.  `{theme}` = 本週主題, `{n}` = the week number.
  static const laterOpener = <String>[
    '歡迎返嚟。今個禮拜我哋講{theme}，一樣係幾條問題，慢慢嚟。',
    '講完我會幫你整理成第{n}章。',
    '如果冇問題，我哋就開始。',
  ];

  static List<String> openerFor(int weekIndex, {required String name}) {
    if (weekIndex <= 1) {
      return [for (final l in week1Opener) l.replaceAll('{name}', name)];
    }
    final w = week(weekIndex);
    return [
      for (final l in laterOpener)
        l.replaceAll('{theme}', w.themeZh).replaceAll('{n}', '$weekIndex'),
    ];
  }

  // ---------------------------------------------------------------------
  // The 32 questions (section 4, verbatim) and the rule arm's short titles.
  // ---------------------------------------------------------------------

  static const weeks = <ReminiscenceV2Week>[
    ReminiscenceV2Week(
      weekIndex: 1,
      themeZh: '童年同屋企',
      questions: [
        '講下你細個住嘅地方，係點樣嘅？',
        '喺嗰度，有冇一日發生嘅事，你到而家都記得好清楚？',
        '講開屋企，細個嗰陣屋企有邊啲人？你同邊個最親？',
        '有冇一件同佢有關嘅事，你一諗起就好似喺眼前？',
        '細個平時一日係點過嘅？玩啲咩、有冇返學、使唔使幫手做嘢？',
        '有冇一次玩得特別開心，或者特別難忘嘅經歷？',
        '講完細個嘅事，你覺得嗰陣最難捱係咩？你係點樣過嚟？',
        '而家返轉頭睇，細個嘅日子對今日嘅你有咩影響？',
      ],
      shortTitles: [
        '細個住嘅地方',
        '最記得嘅一日',
        '屋企人',
        '一諗起就喺眼前嘅事',
        '細個嘅一日',
        '最難忘嘅經歷',
        '最難捱嘅時候',
        '細個對我嘅影響',
      ],
    ),
    ReminiscenceV2Week(
      weekIndex: 2,
      themeZh: '後生時期同工作',
      questions: [
        '後生嗰陣，你主要做緊啲咩？返工、打理屋企或者其他都算。',
        '講一日你做緊呢樣嘢嘅情景：幾點開始？做緊咩？身邊有邊個？',
        '嗰陣身邊有冇一個人，對你影響特別大？可以係同事、老闆、師傅或者屋企人。',
        '有冇一件同佢一齊經歷嘅事，你到而家都記得？',
        '後生嗰陣，生活有冇啲大轉變？例如搬屋、拍拖、結婚、去第二個地方。',
        '講下嗰次轉變入面嘅其中一日，當時係點樣嘅？',
        '講完後生嗰段日子，你覺得最難嘅係咩？你係點樣捱過去？',
        '嗰段日子教識咗你咩，到而家仲用得著？',
      ],
      shortTitles: [
        '後生做緊嘅嘢',
        '一日嘅情景',
        '影響我好大嘅人',
        '一齊經歷嘅事',
        '生活嘅大轉變',
        '轉變入面嘅一日',
        '最難嘅時候',
        '嗰段日子教識我嘅嘢',
      ],
    ),
    ReminiscenceV2Week(
      weekIndex: 3,
      themeZh: '一生人嘅朋友',
      questions: [
        '講下一個對你好重要嘅朋友，你哋係點識嘅？',
        '有冇一次同佢一齊嘅經歷，你到而家都記得好清楚？喺邊度？做緊咩？',
        '除咗佢，你有冇一班成日一齊嘅人？可以係同學、同事、街坊或者其他圈子。',
        '講一次同呢班人一齊最開心嘅情景。',
        '有冇一個好耐冇見、或者已經唔喺度嘅朋友，你間中會諗起？',
        '諗起佢，你最記得佢嘅係咩？',
        '講完朋友嘅事，你同朋友之間有冇試過唔開心、疏遠咗或者分開？嗰陣你點樣面對？',
        '朋友喺你一生入面，係點樣嘅存在？',
      ],
      shortTitles: [
        '一個重要嘅朋友',
        '同佢一齊嘅經歷',
        '成日一齊嘅一班人',
        '最開心嘅情景',
        '間中會諗起嘅朋友',
        '最記得佢嘅地方',
        '唔開心同分開',
        '朋友喺我一生',
      ],
    ),
    ReminiscenceV2Week(
      weekIndex: 4,
      themeZh: '想留畀下一代嘅說話',
      questions: [
        '活到今日，你覺得做人最緊要係咩？',
        '有冇一件親身經歷，令你明白呢個道理？',
        '你屋企有冇一個故事，你好想年輕人知道？',
        '講下呢個故事入面，你最記得嘅一幕。',
        '如果可以同而家嘅年輕人講一句說話，你會講咩？',
        '點解係呢句？有冇一件事令你咁諗？',
        '講完咁多，有冇一條你行過嘅路，你唔想年輕人再行？',
        '回望呢四個禮拜講過嘅嘢，你覺得自己呢一生係點樣嘅？',
      ],
      shortTitles: [
        '做人最緊要',
        '令我明白嘅經歷',
        '屋企嘅故事',
        '最記得嘅一幕',
        '想同年輕人講嘅說話',
        '點解係呢句',
        '唔想年輕人再行嘅路',
        '我呢一生',
      ],
    ),
  ];

  static ReminiscenceV2Week week(int weekIndex) => weeks.firstWhere(
        (w) => w.weekIndex == weekIndex,
        orElse: () => weeks.first,
      );

  // ---------------------------------------------------------------------
  // Fixed lines (section 5) and the closing line (section 2 (6)).
  // ---------------------------------------------------------------------

  /// Rule arm, after an answer to Q1–Q6 (rotated, not one of the last 2).
  static const generalLines = <String>[
    '多謝你話我知，我哋講下一樣。',
    '收到，我記低咗。我哋講下一樣。',
    '聽落好有畫面。我哋講下一樣。',
  ];

  /// Rule arm, after an answer to Q7.
  static const q7Line = '嗰陣真係唔容易，多謝你肯講。我哋講最後一樣。';

  /// Both arms, after 唔想講 (no LLM call).
  static const skipLine = '冇問題，我哋講下一樣。';

  /// Both arms, after Q8.
  static const closingLine =
      '今個禮拜嘅問題問完喇，多謝你。撳『完成今個禮拜』，我幫你整理成一篇小文章。';

  /// Rule arm reply to each 再講多啲 message; also the Hybrid fallback
  /// there.  Developer draft (1020d 8 (1) says "固定一句" without the
  /// words) — 【待 Junyu 确认】.
  static const extraLine = '收到，我記低咗。想再講可以繼續寫。';

  // ---------------------------------------------------------------------
  // Buttons and other short texts.
  // ---------------------------------------------------------------------

  static const skipLabel = '唔想講';
  static const finishWeekLabel = '完成今個禮拜';
  static const moreLabel = '再講多啲';
  static const regenerateLabel = '重新整理';
  static const editLabel = '改一改';
  static const saveLabel = '儲存';
  static const savedLabel = '已儲存';
  static const leaveLabel = '離開（會暫存）';
  static const chaptersPageTitle = '我嘅人生小篇章';
  static const inputHint = '記得幾多寫幾多。';
  static const generating = '整理緊…你可以先離開，整理好會話你知。';
  static const failed = '今次整理唔到。撳「重新整理」再試一次。';
  static const emptyChapter = '（今個禮拜冇寫低內容。）';
  static const extraSectionTitle = '再講多啲';
  static const chaptersEmpty = '完成咗一個禮拜，小篇章就會喺度。';

  /// 「第 N 章：{主題}」.
  static String chapterTitle(int weekIndex) =>
      '第 $weekIndex 章：${week(weekIndex).themeZh}';

  /// 「第 N 章整理好喇」 (the page, the landing card).
  static String chapterReady(int weekIndex) => '第 $weekIndex 章整理好喇';

  // ---------------------------------------------------------------------
  // 1020o — the 自己 page entry and the 人生點滴 landing page (both arms;
  // no switch).  Final (Junyu, 10/20).
  // ---------------------------------------------------------------------

  /// Line under 「我嘅人生小篇章」 on the 自己 page.
  static const chaptersEntrySubtitle = '每個禮拜講完，整理好嘅小文章都喺度。';

  /// The companion's speech bubble at the top of the landing page.
  /// `{name}` = 阿珍 / 阿伯 by the elder's pairing.  May be replaced as a
  /// whole by `app_config/usage_copy.reminiscence_landing_intro_zh`.
  static const landingIntro =
      '我係{name}。我哋一共講四個題目，一個禮拜講一個，每次大約十五至二十五分鐘。冇標準答案，記得幾多講幾多。';

  /// Tester view in English only.
  static const landingIntroEn =
      'I\'m {name}. We\'ll talk about four topics, one a week, about 15 to 25 '
      'minutes each time. There\'s no right answer — share as much as you '
      'remember.';

  /// One small line per theme on the landing cards, by week index (the
  /// theme's id), not by display order.
  static const themeLines = <int, String>{
    1: '細個住嘅地方、屋企嘅人',
    2: '後生嗰陣做過嘅嘢，返工或者打理屋企都算',
    3: '一路以嚟陪住你嘅朋友',
    4: '做人嘅道理，想話畀後生一代知嘅嘢',
  };

  static const themeLinesEn = <int, String>{
    1: 'Where you lived as a child, your family',
    2: 'What you did when you were young — work or running a home',
    3: 'The friends who have been with you along the way',
    4: 'Life lessons you would like the next generation to know',
  };

  // ---------------------------------------------------------------------
  // Chapter rating (section 7) — one at a time, 1–7, words at both ends.
  // ---------------------------------------------------------------------

  static const ratingItems = <ReminiscenceV2RatingItem>[
    ReminiscenceV2RatingItem(
        'accuracy', '呢篇寫得啱唔啱你講過嘅嘢？', '完全唔啱', '完全啱'),
    ReminiscenceV2RatingItem(
        'satisfaction', '睇完呢篇，你覺得幾滿意？', '好唔滿意', '好滿意'),
    ReminiscenceV2RatingItem(
        'share', '你會唔會想畀屋企人或者朋友睇？', '一定唔會', '一定會'),
  ];

  static const ratingStem = '想問你三條問題（1 至 7）';
  static const ratingNext = '下一題';
  static const ratingDone = '完成';
  static const ratingSkip = '唔評住';
}

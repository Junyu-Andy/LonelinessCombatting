/// T17 (SPEC:C22) — ADA item structure, Phase A questionnaire v1.3
/// Appendix C.  **All wording here is placeholder** until the research
/// team publishes `docs/spec/instruments/ada.md`; [itemsVersion] is stored
/// with every answer so placeholder-era data can be told apart.
///
/// Raw values stored (`users/{uid}/ada_responses/{timepoint}`):
///   usage.{agentId}              0–3 (完全冇 … 三次或以上) or "skipped"
///   traits.{traitId}.{agentId}   1–5 (完全唔似 … 好似) or "skipped"
///   scenarios.{scenarioId}       siu_yan | ah_jan_ah_bak | tung_tung |
///                                any, or "skipped"            (full only)
///   freeText                     text, or null when skipped
library;

const String adaItemsVersion = 'ada-placeholder-20261007';
const String day7OpenItemsVersion = 'day7-open-placeholder-20261007';

/// Collections under users/{uid} (firestore.rules; tool/delete_participant.js).
const String kAdaCollection = 'ada_responses';
const String kDay7OpenCollection = 'day7_open_responses';
const String kDay7OpenDocId = 'day7';

/// Value stored for an item the participant skipped.
const String kSkipped = 'skipped';

class AdaAgents {
  static const siuYan = 'siu_yan';
  static const ahJanAhBak = 'ah_jan_ah_bak';
  static const tungTung = 'tung_tung';
  static const all = [siuYan, ahJanAhBak, tungTung];
}

/// Part A — 4 bands, stored 0–3.
class AdaUsage {
  static const labelsZh = ['完全冇', '少過一次', '一至兩次', '三次或以上'];
  static const labelsEn = ['Not at all', 'Less than once', 'Once or twice',
      'Three times or more'];

  /// Prefix is the configured recall window.
  static String questionZh(String recallWindow) =>
      '$recallWindow，你大約同每個夥伴傾過幾多次？';
  static String questionEn(String recallWindow) =>
      '$recallWindow, about how often did you talk with each companion?';
}

/// Part B — 4 traits × 3 agents, 1–5.
class AdaTraits {
  static const warm = 'warm';
  static const sameAge = 'same_age';
  static const curious = 'curious';
  static const nonJudgmental = 'non_judgmental';
  static const all = [warm, sameAge, curious, nonJudgmental];

  static const labelsZh = {
    warm: '溫暖、關心人',
    sameAge: '似自己同年紀',
    curious: '好奇、鍾意問嘢',
    nonJudgmental: '聽我講而唔評判我',
  };
  static const labelsEn = {
    warm: 'Warm and caring',
    sameAge: 'Like someone my own age',
    curious: 'Curious, likes asking questions',
    nonJudgmental: 'Listens to me without judging',
  };

  static const scaleZh = ['完全唔似', '少少', '有啲', '幾似', '好似'];
  static const scaleEn = ['Not at all', 'A little', 'Somewhat', 'Quite',
      'Very much'];

  static const promptZh = '呢句說話有幾似每個夥伴？';
  static const promptEn = 'How well does this describe each companion?';
}

/// Part C — 5 scenarios, single choice (full form only).
class AdaScenarios {
  static const dayRecap = 'day_recap';
  static const memories = 'memories';
  static const learnNew = 'learn_new';
  static const feelingDown = 'feeling_down';
  static const smallTalk = 'small_talk';
  static const all = [dayRecap, memories, learnNew, feelingDown, smallTalk];

  /// Option stored when the participant picks 「邊個都得」.
  static const any = 'any';
  static const options = [...AdaAgents.all, any];

  static const labelsZh = {
    dayRecap: '講今日點過',
    memories: '講舊時回憶',
    learnNew: '學新嘢',
    feelingDown: '心情唔好',
    smallTalk: '日常閒聊',
  };
  static const labelsEn = {
    dayRecap: 'Talking about how my day went',
    memories: 'Talking about old memories',
    learnNew: 'Learning something new',
    feelingDown: 'When I feel down',
    smallTalk: 'Everyday chat',
  };

  static const anyZh = '邊個都得';
  static const anyEn = 'Any of them';
  static const promptZh = '想做呢樣嘢嘅時候，你會搵邊個夥伴？';
  static const promptEn = 'For this, which companion would you go to?';
}

/// Part D — one long free answer.
class AdaFreeText {
  static const questionZh = '你覺得三個夥伴有咩唔同？你會同邊個傾得多啲？點解？';
  static const questionEn = 'How are the three companions different? Who '
      'would you talk with more, and why?';
  static const hintZh = '想講幾多都得。';
  static const hintEn = 'Write as much as you like.';
}

/// Day-7 open questions (placeholder text; research team to supply).
class Day7OpenQuestions {
  static const ids = ['q1', 'q2', 'q3'];
  static const questionsZh = {
    'q1': '【占位】第 7 日開放題一',
    'q2': '【占位】第 7 日開放題二',
    'q3': '【占位】第 7 日開放題三',
  };
  static const questionsEn = {
    'q1': '[Placeholder] Day-7 open question 1',
    'q2': '[Placeholder] Day-7 open question 2',
    'q3': '[Placeholder] Day-7 open question 3',
  };
}

/// T17b (SPEC:C22, decision 0030) — ADA items, copied verbatim from
/// `docs/spec/instruments/ada.md` §3 (v1.0, research team 2026-10-07).
/// Do not reword the Cantonese: a change needs a new spec version and a
/// new [adaItemsVersion].  English is a working translation only (the
/// App's EN locale); it is not part of the instrument.
///
/// Forms (§2): short = B + D (visit 1); full = A + B + C + D (day 7).
///
/// Raw values stored (`users/{uid}/ada_responses/{timepoint}`, §4–5):
///   usage.{agentId}              0–3 (完全冇 / 一次 / 兩至三次 / 四次或以上)
///                                or "skipped"                 (full only)
///   traits.{traitId}.{agentId}   1–5 (完全唔似 … 好似) or "skipped"
///   scenarios.{scenarioId}       siu_yan | ah_jan_ah_bak | tung_tung |
///                                any, or "skipped"            (full only)
///   freeText                     text, or null when skipped
/// No totals are computed; B is reported per companion (§4.4).
library;

/// v1.0 wording.  Placeholder-era answers carry
/// `ada-placeholder-20261007` and are left as they are.
const String adaItemsVersion = 'ada-v1.0-20261007';
const String day7OpenItemsVersion = 'day7-open-placeholder-20261007';

/// Collections under users/{uid} (firestore.rules; tool/delete_participant.js).
const String kAdaCollection = 'ada_responses';
const String kDay7OpenCollection = 'day7_open_responses';
const String kDay7OpenDocId = 'day7';

/// Value stored for an item the participant skipped.
const String kSkipped = 'skipped';

/// ada.md §5 completion channel.
class AdaChannel {
  static const app = 'app';
  static const phoneByStaff = 'phone_by_staff';
}

class AdaAgents {
  static const siuYan = 'siu_yan';
  static const ahJanAhBak = 'ah_jan_ah_bak';
  static const tungTung = 'tung_tung';
  static const all = [siuYan, ahJanAhBak, tungTung];
}

/// Part A — usage over the past 7 days, 4 options, stored 0–3.
class AdaUsage {
  static const questionZh = '過去 7 日，你大約同每位陪伴者傾過幾多次？';
  static const questionEn =
      'In the past 7 days, about how many times did you talk with each '
      'companion?';
  static const labelsZh = ['完全冇', '一次', '兩至三次', '四次或以上'];
  static const labelsEn = ['Not at all', 'Once', '2–3 times',
      '4 times or more'];
}

/// Part B — 4 sentences × 3 companions, 1–5.  Ids are kept from T17 so
/// the field names do not change; [codes] gives the spec numbering.
class AdaTraits {
  static const warm = 'warm';
  static const sameAge = 'same_age';
  static const curious = 'curious';
  static const nonJudgmental = 'non_judgmental';
  static const all = [warm, sameAge, curious, nonJudgmental];

  static const codes = {
    warm: 'B1', sameAge: 'B2', curious: 'B3', nonJudgmental: 'B4',
  };

  static const labelsZh = {
    warm: '溫暖、關心人',
    sameAge: '似自己同年紀嘅人',
    curious: '好奇，鍾意問我嘢',
    nonJudgmental: '聽我講而唔評判我',
  };
  static const labelsEn = {
    warm: 'Warm and caring',
    sameAge: 'Like someone my own age',
    curious: 'Curious, likes asking me things',
    nonJudgmental: 'Listens to me without judging',
  };

  static const scaleZh = ['完全唔似', '少少似', '有啲似', '幾似', '好似'];
  static const scaleEn = ['Not at all', 'A little', 'Somewhat', 'Quite',
      'Very'];

  static const promptZh = '下面每一句，有幾似每位陪伴者？';
  static const promptEn = 'How much is each sentence like each companion?';
}

/// Part C — 5 situations, single choice (full form only).
class AdaScenarios {
  static const dayRecap = 'day_recap';
  static const memories = 'memories';
  static const learnNew = 'learn_new';
  static const feelingDown = 'feeling_down';
  static const smallTalk = 'small_talk';
  static const all = [dayRecap, memories, learnNew, feelingDown, smallTalk];

  static const codes = {
    dayRecap: 'C1', memories: 'C2', learnNew: 'C3', feelingDown: 'C4',
    smallTalk: 'C5',
  };

  /// Option stored when the participant picks 「邊個都得」.
  static const any = 'any';
  static const options = [...AdaAgents.all, any];

  static const labelsZh = {
    dayRecap: '講下今日點過',
    memories: '講下舊時嘅回憶、人生經歷',
    learnNew: '學啲新嘢',
    feelingDown: '心情唔好嘅時候',
    smallTalk: '日常閒聊',
  };
  static const labelsEn = {
    dayRecap: 'Talk about how my day went',
    memories: 'Talk about old memories and my life',
    learnNew: 'Learn something new',
    feelingDown: 'When I am in a bad mood',
    smallTalk: 'Everyday chat',
  };

  static const anyZh = '邊個都得';
  static const anyEn = 'Any of them';
  static const promptZh = '如果你想做下面呢啲嘢，你會首先搵邊位陪伴者？';
  static const promptEn =
      'If you wanted to do the following, which companion would you go to '
      'first?';
}

/// Part D — one long free answer.
class AdaFreeText {
  static const questionZh =
      '用你自己嘅說話，話我哋知三位陪伴者有咩唔同？有冇邊位你會想同佢傾多啲？點解？';
  static const questionEn =
      'In your own words, tell us how the three companions are different. '
      'Is there one you would like to talk with more? Why?';
  // Draft helper line under the question (not part of the instrument).
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

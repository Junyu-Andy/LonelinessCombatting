/// 1020 E / 1020b §4 5.1, 5.2 — the mood row on page 1 (M1–M8) and 小欣's
/// openers when the elder comes in from M7 / M8 (O1–O5, C1, C2), behind
/// `app_config/feature_flags.moodRowV2Enabled`.
///
/// Drafts (1020b common rule 4, Junyu signs them off in the PR
/// screenshots), copied verbatim from `docs/spec/copy/home-v2.md`;
/// test/final_copy_test.dart compares every line.  Edit the spec first.
///
/// Both arms see the same row.  The openers are the rule arm's; the
/// Hybrid arm's LLM says the same thing in its own words (prompt
/// `siu_yan.v4`, block `[開場·心情]`) and falls back to these lines when
/// the model fails.
library;

import '../../context/presentation/pages/check_in_shared.dart';

class MoodRowCopy {
  MoodRowCopy._();

  /// Logged with every row event so the wording can be traced.
  static const String version = '1020b-5.1-5.2-20261019-draft';

  /// M1 — today, nothing answered yet.
  static const String m1 = '你而家心情點？';

  /// M2 — the small button beside M1.
  static const String m2 = '遲啲先答';

  /// M3 — shown briefly after a face is picked.
  static const String m3 = '記低咗';

  /// M4 — after M2, for the rest of the day (tap to answer).
  static const String m4 = '今日心情：未答（撳一下答）';

  /// M5 — answered: `今日心情：{表情} {幾好}（{09:12}）`.
  static const String m5Template = '今日心情：{表情} {幾好}（{09:12}）';

  static String m5(int mood, DateTime at) {
    final face = faceFor(mood);
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return m5Template
        .replaceFirst('{表情}', face.emoji())
        .replaceFirst('{幾好}', face.label(false))
        .replaceFirst('{09:12}', '$hh:$mm');
  }

  /// M6 — the small button under M5; opens the five faces again.
  static const String m6 = '而家有冇變？';

  /// M7 — under the row after the first answer of the day.
  static const String m7 = '想同小欣講詳細啲？';

  /// M8 — a later answer that differs from the one before; replaces M7.
  static const String m8 = '心情好似唔同咗，想同小欣講下發生咩事？';

  /// 1..5 → the face (5 = 好好 … 1 = 好差, as the home pad).
  static MoodFace faceFor(int mood) =>
      MoodFace.values[mood.clamp(1, 5) - 1];

  // ---------------------------------------------------------------------
  // 5.2 — 小欣's opener from M7 / M8 (rule arm; Hybrid falls back to it)
  // ---------------------------------------------------------------------

  /// O1–O5 by the mood just picked (M7): 5 = 好開心 … 1 = 好唔開心.
  static const Map<String, String> openers = {
    'O1': '見你而家心情咁好，我都開心！有咩好事，講俾我聽下？',
    'O2': '心情幾好，好呀。今日有咩想同我傾？',
    'O3': '一般般都唔緊要。有咩想講，慢慢講。',
    'O4': '聽到你心情唔係幾好。想講下發生咩事嗎？我喺度聽。',
    'O5': '你而家好唔開心，辛苦你喇。想講就講，唔想講陪下你都得。',
    'C1': '心情好咗喎！發生咗咩好事呀？',
    'C2': '心情好似差咗啲，發生咗咩事？想講就慢慢講。',
  };

  /// The openers after which the rule arm answers from SN1–SN4 (5.2b).
  static const Set<String> lowOpeners = {'O4', 'O5', 'C2'};

  /// How 5.2 names each mood (O1 好開心 … O5 好唔開心), for the Hybrid
  /// opener's context block — the same five words as check-in Q1.
  static const Map<int, String> moodWords = {
    5: '好開心',
    4: '幾好',
    3: '一般般',
    2: '唔係幾好',
    1: '好唔開心',
  };
}

/// How 小欣's chat was opened from the mood row: M7 (the mood just
/// picked) or M8 (the mood changed from [previousMood] to [mood]).
class MoodChatEntry {
  const MoodChatEntry({required this.mood, this.previousMood});

  /// Today's latest pick, 1..5.
  final int mood;

  /// M8 only: the pick before it.
  final int? previousMood;

  bool get changed => previousMood != null && previousMood != mood;

  /// `M7` or `M8` (what the elder tapped).
  String get promptId => changed ? 'M8' : 'M7';

  /// `up` / `down` for M8, null for M7.
  String? get direction =>
      !changed ? null : (mood > previousMood! ? 'up' : 'down');

  /// The 5.2 opener: O1–O5 by mood for M7; C1 (better) / C2 (worse) for M8.
  String get openerId {
    if (changed) return mood > previousMood! ? 'C1' : 'C2';
    return 'O${6 - mood.clamp(1, 5)}';
  }

  String get openerText => MoodRowCopy.openers[openerId]!;

  /// O4, O5, C2: the rule arm then answers from SN1–SN4.
  bool get lowOpener => MoodRowCopy.lowOpeners.contains(openerId);

  /// The Hybrid opener's context block (prompt `siu_yan.v4`, section
  /// 「從首頁心情入嚟（開場）」).  Only the moods, never the elder's words.
  String get contextBlock {
    final now = MoodRowCopy.moodWords[mood.clamp(1, 5)]!;
    if (!changed) {
      return '[開場·心情]\n'
          '入口：M7（${MoodRowCopy.m7}）\n'
          '用戶而家揀嘅心情：$now（$mood/5）';
    }
    final before = MoodRowCopy.moodWords[previousMood!.clamp(1, 5)]!;
    return '[開場·心情]\n'
        '入口：M8（${MoodRowCopy.m8}）\n'
        '用戶而家揀嘅心情：$now（$mood/5）\n'
        '之前揀嘅心情：$before（$previousMood/5）\n'
        '變化：${direction == 'up' ? '好咗' : '差咗'}';
  }
}

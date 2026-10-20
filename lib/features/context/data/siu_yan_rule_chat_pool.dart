/// 1020 F (4) / 1020b §4 5.2b — the rule arm's Siu Yan free-chat replies
/// (`checkInChatV2Enabled`).  Each elder message gets one line, rotated so
/// none repeats within the last [RuleReplyPool.recentWindow] replies;
/// never the LLM.  SN1–SN4 when the elder's mood is low (see [isLow]),
/// otherwise SY1–SY6.  A safety hit gets no line (the safety flow runs).
///
/// Drafts, verbatim from `docs/spec/copy/check-in-chat.md`
/// (test/final_copy_test.dart).  The recent list is stored like the other
/// templates (`users/{uid}/rule_reply_history/{historyKey}`).
library;

import '../../rule_replies/data/rule_reply_picker.dart';
import '../../rule_replies/data/rule_reply_pool.dart';

class SiuYanRuleChatPool {
  SiuYanRuleChatPool._();

  static const String version = '1020b-5.2b-20261019-draft';

  /// Doc id under `rule_reply_history` (separate from the X templates'
  /// `siu_yan`, so the check-in reply rotation is not disturbed).
  static const String historyKey = 'siu_yan_chat';

  static const String bandGeneral = 'chat_general';
  static const String bandLow = 'chat_low';

  static const List<RuleReplyEntry> general = [
    (id: 'SY1', agent: 'siu_yan', band: bandGeneral, zh: '多謝你同我講，我喺度聽緊。'),
    (id: 'SY2', agent: 'siu_yan', band: bandGeneral, zh: '明白。你慢慢講，唔使急。'),
    (
      id: 'SY3',
      agent: 'siu_yan',
      band: bandGeneral,
      zh: '聽落你都有唔少嘢諗。想講多啲都得。',
    ),
    (id: 'SY4', agent: 'siu_yan', band: bandGeneral, zh: '好呀，再講多少少俾我聽？'),
    (
      id: 'SY5',
      agent: 'siu_yan',
      band: bandGeneral,
      zh: '你講嘅我都聽到。今日記得飲多啲水，休息下。',
    ),
    (id: 'SY6', agent: 'siu_yan', band: bandGeneral, zh: '收到。得閒隨時嚟搵我傾。'),
  ];

  static const List<RuleReplyEntry> low = [
    (
      id: 'SN1',
      agent: 'siu_yan',
      band: bandLow,
      zh: '聽落你而家唔係咁好受，我喺度陪你。',
    ),
    (
      id: 'SN2',
      agent: 'siu_yan',
      band: bandLow,
      zh: '多謝你肯講出嚟，唔使一個人頂住。',
    ),
    (id: 'SN3', agent: 'siu_yan', band: bandLow, zh: '慢慢嚟，想停一停都得。'),
    (
      id: 'SN4',
      agent: 'siu_yan',
      band: bandLow,
      zh: '除咗同我講，如果有信得過嘅人，都可以搵佢哋傾下。',
    ),
  ];

  /// Low mood (5.2b): today's latest `daily_mood` is 唔係幾好 or 好唔開心
  /// (2 or 1 on the 1..5 scale), or the chat was opened from a low-mood
  /// opener (O4, O5, C2 — batch 3 passes [lowMoodEntry]).
  static bool isLow({int? latestMoodToday, bool lowMoodEntry = false}) =>
      lowMoodEntry || (latestMoodToday != null && latestMoodToday <= 2);

  /// How many recent ids are kept (`rule_reply_history/siu_yan_chat`):
  /// one less than the larger group, so each group goes round in full.
  static const int historyKeep = 5;

  /// The next line: the first entry of the group not among its last
  /// (group size − 1) uses in [recent] (oldest first) — i.e. the group in
  /// turn, SY1 … SY6, SY1 …, never a repeat within the last few; when all
  /// were used, the least recently used one ([RuleReplyPicker]).
  static RuleReplyEntry pick({
    required bool low,
    required List<String> recent,
  }) {
    final group = low ? SiuYanRuleChatPool.low : general;
    return RuleReplyPicker.pick(group, recent, window: group.length - 1)!;
  }

  /// [recent] with [id] added, trimmed to [historyKeep].
  static List<String> remember(List<String> recent, String id) =>
      RuleReplyPicker.remember(recent, id, keep: historyKeep);
}

/// 1020 F / 1020b §4 (5.2b, 5.3) — the fixed elder-facing words of the
/// Siu Yan chat window behind `checkInChatV2Enabled`: the check-in
/// questions Q0–Q6 with their buttons, the rule arm's fixed replies XG,
/// R4a, R4b and the opener SY0.
///
/// Drafts (1020b common rule 4, Junyu signs them off in the PR
/// screenshots), copied verbatim from `docs/spec/copy/check-in-chat.md`;
/// test/final_copy_test.dart compares every line.  Edit the spec first.
///
/// The questions, the buttons and their order are the same in both arms
/// and are never written by the LLM.  Only Siu Yan's two check-in replies
/// differ: rule arm = these templates and the 5.4 X1–X5
/// ([RuleReplyPool.checkInChatEntries]); Hybrid = the LLM.
library;

/// One answer button.  [code] is what `check_in_responses` stores, [label]
/// what the elder sees.
class CheckInOption {
  const CheckInOption(this.code, this.label, {this.score});

  final String code;
  final String label;

  /// Q1 only: 5 好開心 … 1 好唔開心; null for 唔想答.
  final int? score;
}

class CheckInChatCopy {
  CheckInChatCopy._();

  /// Logged with every check-in record so the wording can be traced.
  static const String version = '1020b-s4-20261019-draft';

  static const String q0Morning = '早晨！想問下你尋日嘅情況，幾條就得。';

  /// Q0: 「早晨」 before noon, 「你好」 from 12:00 (phone time).
  static String q0(DateTime now) =>
      now.hour < 12 ? q0Morning : q0Morning.replaceFirst('早晨', '你好');

  static const String q1 = '尋日成日整體過得點？';

  /// Q1 code `prefer_not` (唔想答) has no band: reply 1 is XG.
  static const String q1PreferNot = 'prefer_not';
  /// 1020e 二.12: the five faces read 好唔開心／唔係幾好／一般般／幾好／好開心
  /// (low to high, as on the home mood row); scores stay 1–5.
  static const List<CheckInOption> q1Options = [
    CheckInOption('very_unhappy', '好唔開心', score: 1),
    CheckInOption('not_good', '唔係幾好', score: 2),
    CheckInOption('so_so', '一般般', score: 3),
    CheckInOption('good', '幾好', score: 4),
    CheckInOption('very_happy', '好開心', score: 5),
    CheckInOption(q1PreferNot, '唔想答'),
  ];

  static const String q2 = '尋日有冇同人傾過偈？';
  static const List<CheckInOption> q2Options = [
    CheckInOption('none', '冇'),
    CheckInOption('a_little', '少少'),
    CheckInOption('quite_a_bit', '幾多'),
    CheckInOption('a_lot', '好多'),
  ];

  static const String q3 = '尋日有冇咩特別事？';
  static const List<CheckInOption> q3Options = [
    CheckInOption('none', '冇'),
    CheckInOption('small', '一啲小事'),
    CheckInOption('big', '一件大事'),
  ];

  /// Q3 answers that open Q3b.
  static const Set<String> q3OpensQ3b = {'small', 'big'};

  static const String q3b = '想講下係咩事嗎？打字講都得，唔講都得。';

  /// The skip button under the Q3b / Q4 input box.
  static const String skipLabel = '唔講住';

  static const String xg = '多謝你話俾我知尋日嘅情況。';

  static const String q4 = '今日有咩打算？想講就講，唔講都得。';
  static const String r4a = '好呀，今日就照你嘅打算慢慢嚟。';
  static const String r4b = '冇問題，今日慢慢諗都得。';

  static const String q5 = '想訂個小計劃嗎？';
  static const List<CheckInOption> q5Options = [
    CheckInOption('yes', '好呀'),
    CheckInOption('no', '唔使喇'),
  ];

  static const String q6 = '多謝你同我傾，聽朝再問候你。';

  /// Opener when today's check-in is already done (rule arm; the Hybrid
  /// arm's LLM opener falls back to it).
  static const String sy0 = '今日 check-in 做咗喇，想再講啲咩都得。';

  /// Input box hint (1020e 二.5, #134): typing only, no voice wording.
  static const String inputHint = '寫低你想講嘅嘢。';
  static const String inputHintEn = 'Type what you want to say.';
}

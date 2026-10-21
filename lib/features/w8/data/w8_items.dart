/// T35 — the W8 questionnaire (handover 1021-W8; decision 0036): every
/// word the elder sees, and the items of the five parts and the optional
/// AIMHS.  Copied word for word from the handover's section 三 (checked
/// against the W0 / W4 paper booklets by the research side on 10/21) —
/// do not reword, do not "fix" punctuation.  The same words are in
/// docs/spec/copy/w8-questionnaire.md and docs/spec/instruments/
/// (ucla3.md, lsns6.md, ci.md, aimhs.md; DJG-ES in djg_es.md);
/// test/w8_questionnaire_test.dart compares them word for word.
///
/// Both arms get exactly these words; no model is ever asked.  Nothing
/// here mentions or reveals the arm (AIMHS speaks of AI chat assistants
/// in general, as on the W0 / W4 paper forms).
///
/// The W8 does NOT contain the Phase B "guess the version" or
/// "dependence" probes (lib/features/phase_b_probes/): they are not in
/// the approved questionnaire package nor in the handover.
library;

import '../../../core/survey/direction_cue.dart';
import '../../assessment/data/djg_w2.dart';

/// The parts in their fixed order (handover 二 (1)), then the optional
/// AIMHS (二 (3)).
enum W8Part { djg, ucla3, pgic, ci, lsns6, aimhs }

/// One question.  [lead] is a line shown just above it (DJG-ES q4,
/// LSNS-6 q1 and q4; handover 二 (4)).
class W8Item {
  final String id;
  final String text;
  final String? lead;
  const W8Item(this.id, this.text, {this.lead});
}

/// One answer: the stored raw value (DJG-ES a string, the rest a number)
/// and the label on the button.
class W8Option {
  final Object value;
  final String label;
  const W8Option(this.value, this.label);
}

/// Everything a part page needs.
class W8PartSpec {
  final W8Part part;

  /// `users/{uid}/<collection>/W8`.
  final String collection;

  /// Page title (the part name; AIMHS: its own name).
  final String title;

  /// Shown above the first question (null: none).
  final String? instruction;

  /// Shown under every question (PGIC's 「提示」).
  final String? hint;
  final List<W8Item> items;
  final List<W8Option> options;
  final String itemsVersion;

  const W8PartSpec({
    required this.part,
    required this.collection,
    required this.title,
    required this.instruction,
    this.hint,
    required this.items,
    required this.options,
    required this.itemsVersion,
  });
}

/// The words around the questions (handover 三).
class W8Texts {
  W8Texts._();

  /// 標題 — the home card and the page title.
  static const title = '最後一份問卷';

  /// 開頭 — at the top of the flow before anything is done.
  static const intro =
      '今次一共有 5 部分，大約 8 分鐘，可以隨時停，下次由停低嗰度繼續。';

  /// 部分名, in order.
  static const partNames = <String>[
    '最近嘅感受',
    '孤單嘅感覺',
    '同開始用嗰時比較',
    '會唔會繼續用',
    '身邊嘅親人同朋友',
  ];

  /// 完成 — after the five parts, with the two buttons.
  static const done = '全部做完喇，多謝你！仲有一份可以選擇唔填嘅短問卷。';
  static const fill = '填呢份';
  static const decline = '唔填喇';

  /// The push (days 56, 58 and 60; sent by the server,
  /// functions/w8_questionnaire.js PUSH_BODY).
  static const push = '最後一份問卷開咗，請喺一個禮拜內入嚟答埋佢。多謝你！';

  /// The LSNS-6 lead lines (handover 二 (4); the App's spoken version,
  /// decisions-log 10/21 item 127 (4)).
  static const lsnsQ1Lead = '先講親人，即係同你有血緣、婚姻或者收養關係嘅人。';
  static const lsnsQ4Lead = '跟住講朋友，包括住喺你附近嘅朋友。';

  /// The optional questionnaire's name.
  static const aimhsTitle = '對傾偈助手嘅睇法';
}

class W8Items {
  W8Items._();

  /// The bundle id: every W8 record is `users/{uid}/<collection>/W8`.
  static const bundleId = 'W8';

  /// A skipped question is stored as this (DJG-ES's convention).
  static const skipped = 'skipped';

  /// Part 1 — DJG-ES 6: the same items and answers as W1–W3
  /// ([DjgW2Items], the approved package §3); the q4 line is
  /// [DirectionCues.djgQ4], shown always in W8.
  static final djg = W8PartSpec(
    part: W8Part.djg,
    collection: 'djg_responses',
    title: W8Texts.partNames[0],
    instruction: '每句揀一個最啱你最近情況嘅答案。',
    items: [
      for (final it in DjgW2Items.items)
        W8Item(it.id, it.text,
            lead: it.id == 'q4' ? DirectionCues.djgQ4 : null),
    ],
    options: [
      for (final o in DjgW2Items.options) W8Option(o.$1, o.$2),
    ],
    itemsVersion: DjgW2Items.version,
  );

  /// Part 2 — UCLA-3: 很少 1, 有時 2, 經常 3.
  static const ucla3 = W8PartSpec(
    part: W8Part.ucla3,
    collection: 'ucla3_responses',
    title: '孤單嘅感覺',
    instruction: '以下三條問題，請揀很少、有時、定係經常。',
    items: [
    W8Item('q1', '你多常感到缺乏陪伴？'),
    W8Item('q2', '你多常感到被冷落、被排除在外？'),
    W8Item('q3', '你多常感到與他人疏離、孤立？'),
    ],
    options: [
    W8Option(1, '很少'),
    W8Option(2, '有時'),
    W8Option(3, '經常'),
    ],
    itemsVersion: 'ucla3_w8_v1',
  );

  /// Part 3 — PGIC, one question, the raw value 1 (好咗好多) … 7 (差咗好多)
  /// as the W1–W7 PGIC page; stored in the existing PGIC format
  /// (users/{uid}/pgic/W8, `value`).
  static const pgic = W8PartSpec(
    part: W8Part.pgic,
    collection: 'pgic',
    title: '同開始用嗰時比較',
    instruction: null,
    hint: '請揀最貼近你感受嘅一個。',
    items: [
      W8Item('q1', '同你開始用呢個 app 之前比較，你嘅孤獨感而家點？'),
    ],
    options: [
    W8Option(1, '好咗好多'),
    W8Option(2, '好咗'),
    W8Option(3, '好咗少少'),
    W8Option(4, '冇變'),
    W8Option(5, '差咗少少'),
    W8Option(6, '差咗'),
    W8Option(7, '差咗好多'),
    ],
    itemsVersion: 'pgic_w8_v1',
  );

  /// Part 4 — continuance intention CI1–CI3, 1–5.
  static const ci = W8PartSpec(
    part: W8Part.ci,
    collection: 'ci_responses',
    title: '會唔會繼續用',
    instruction: '每句揀你有幾同意。',
    items: [
    W8Item('q1', '如果研究結束之後呢個 app 繼續開放，我會繼續用。'),
    W8Item('q2', '喺接落嚟嘅日子，我打算繼續用呢類陪伴功能。'),
    W8Item('q3', '將來如果有需要，我會再開呢個 app 嚟用。'),
    ],
    options: [
    W8Option(1, '1 非常不同意'),
    W8Option(2, '2 不同意'),
    W8Option(3, '3 一半半'),
    W8Option(4, '4 同意'),
    W8Option(5, '5 非常同意'),
    ],
    itemsVersion: 'ci_w8_v1',
  );

  /// Part 5 — LSNS-6: 沒有 0 … 九個或以上 5; q1–q3 family, q4–q6 friends.
  static const lsns6 = W8PartSpec(
    part: W8Part.lsns6,
    collection: 'lsns6_responses',
    title: '身邊嘅親人同朋友',
    instruction:
        '以下六條問題問你身邊有幾多親戚同朋友，每條揀一個數目。',
    items: [
    W8Item('q1', '你有幾多個親人，係你每個月起碼見一次面、或者傾一次電話／訊息嘅？',
        lead: W8Texts.lsnsQ1Lead),
    W8Item('q2', '你有幾多個親人，係你可以放心同佢講私人嘢嘅？'),
    W8Item('q3', '你有幾多個親人，係你覺得好親近、有事可以搵佢幫手嘅？'),
    W8Item('q4', '你有幾多個朋友，係你每個月起碼見一次面、或者傾一次電話／訊息嘅？',
        lead: W8Texts.lsnsQ4Lead),
    W8Item('q5', '你有幾多個朋友，係你可以放心同佢講私人嘢嘅？'),
    W8Item('q6', '你有幾多個朋友，係你覺得好親近、有事可以搵佢幫手嘅？'),
    ],
    options: [
    W8Option(0, '沒有'),
    W8Option(1, '一個'),
    W8Option(2, '兩個'),
    W8Option(3, '三至四個'),
    W8Option(4, '五至八個'),
    W8Option(5, '九個或以上'),
    ],
    itemsVersion: 'lsns6_w8_v1',
  );

  /// Optional — AIMHS 5, 1–5; item 1 is reversed only at analysis (the
  /// raw value is stored).  The whole questionnaire may be left out.
  static const aimhs = W8PartSpec(
    part: W8Part.aimhs,
    collection: 'aimhs_responses',
    title: W8Texts.aimhsTitle,
    instruction:
        '以下五句話係講 AI 傾偈助手，即係可以同人傾偈嘅電腦程式。每句請揀你有幾同意。',
    items: [
    W8Item('q1', '喺「明白同體諒人嘅感受」呢方面，AI 傾偈助手做唔到好似真人輔導員咁。'),
    W8Item('q2', '喺解決問題嘅能力上面，AI 傾偈助手可以叻過真人輔導員。'),
    W8Item('q3', 'AI 傾偈助手可以減少地域上嘅限制，令更多人得到情緒支援。'),
    W8Item('q4', 'AI 傾偈助手可以全日二十四小時都用到，令更多人得到情緒支援。'),
    W8Item('q5', 'AI 傾偈助手收費較低，可以減少經濟負擔，令更多人得到情緒支援。'),
    ],
    options: [
    W8Option(1, '1 非常不同意'),
    W8Option(2, '2 不同意'),
    W8Option(3, '3 一半半'),
    W8Option(4, '4 同意'),
    W8Option(5, '5 非常同意'),
    ],
    itemsVersion: 'aimhs_w8_v1',
  );

  /// The five required parts, in order.
  static final parts = <W8PartSpec>[djg, ucla3, pgic, ci, lsns6];

  static W8PartSpec specOf(W8Part p) => switch (p) {
        W8Part.djg => djg,
        W8Part.ucla3 => ucla3,
        W8Part.pgic => pgic,
        W8Part.ci => ci,
        W8Part.lsns6 => lsns6,
        W8Part.aimhs => aimhs,
      };
}

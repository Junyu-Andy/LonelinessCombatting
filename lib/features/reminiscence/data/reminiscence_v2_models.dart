/// 1020d (回憶 v2) — the week's conversation, its state, the chapter doc and
/// the pure helpers both arms share (rule-arm chapter layout, the chapter
/// request payload, the edit ratio, fixed-line rotation).
///
/// Week doc: `users/{uid}/reminiscence_v2/week_{N}` ([ReminiscenceWeekState]).
/// Chapter doc: `users/{uid}/reminiscence_chapters/week_{N}`
/// ([ReminiscenceChapterDoc]) — the contract with the server's chapter
/// Cloud Function: the App writes the request (and, in the rule arm, the
/// finished chapter); only the server writes `finalText`, `rounds`,
/// `flags`, `generatedAt` and, for Hybrid, `version`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'reminiscence_v2_copy.dart';

/// `messages[].kind` (contract with the server agent).
enum ReminiscenceMessageKind {
  opener('opener'),
  question('question'),
  answer('answer'),
  followup('followup'),
  followupAnswer('followup_answer'),
  reply('reply'),
  fixedLine('fixed_line'),
  skip('skip'),
  closing('closing'),
  extra('extra'),
  extraReply('extra_reply');

  const ReminiscenceMessageKind(this.code);
  final String code;

  static ReminiscenceMessageKind? parse(String? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }

  /// Written by the elder (role `user`).
  bool get fromUser =>
      this == answer || this == followupAnswer || this == skip || this == extra;
}

/// One message of the week.
class ReminiscenceMessage {
  const ReminiscenceMessage({
    required this.id,
    required this.kind,
    required this.text,
    required this.at,
    this.questionIndex,
    this.copyId,
    this.safety,
  });

  final String id;
  final ReminiscenceMessageKind kind;
  final String text;
  final DateTime at;

  /// 1–8; null for the opener, the closing line and 再講多啲.
  final int? questionIndex;

  /// Which fixed line / source (e.g. `G1`, `Q7`, `SKIP`, `Z5-2`, `EXTRA`,
  /// `llm`, `llm_fallback`, `opener_1`, `Q3`).  For analysis only.
  final String? copyId;

  /// Elder messages only: the safety tier (`moderate_interrupt` / `acute`)
  /// when this message stopped the questions.  Such a message is left out
  /// of the chapter and is never sent to the LLM again.
  final String? safety;

  bool get fromUser => kind.fromUser;
  String get role => fromUser ? 'user' : 'assistant';
  bool get flagged => safety != null;

  /// [isoTime]: the device cache (JSON); otherwise a DateTime, which
  /// Firestore stores as a Timestamp.
  Map<String, dynamic> toMap({bool isoTime = false}) => {
        'id': id,
        'role': role,
        'kind': kind.code,
        'questionIndex': questionIndex,
        'text': text,
        'at': isoTime ? at.toIso8601String() : at,
        if (copyId != null) 'copyId': copyId,
        if (safety != null) 'safety': safety,
      };

  static ReminiscenceMessage? fromMap(Map<String, dynamic> m) {
    final kind = ReminiscenceMessageKind.parse(m['kind'] as String?);
    if (kind == null) return null;
    return ReminiscenceMessage(
      id: (m['id'] as String?) ?? '',
      kind: kind,
      text: (m['text'] as String?) ?? '',
      at: parseTime(m['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      questionIndex: (m['questionIndex'] as num?)?.toInt(),
      copyId: m['copyId'] as String?,
      safety: m['safety'] as String?,
    );
  }

  ReminiscenceMessage copyWith({String? safety}) => ReminiscenceMessage(
        id: id,
        kind: kind,
        text: text,
        at: at,
        questionIndex: questionIndex,
        copyId: copyId,
        safety: safety ?? this.safety,
      );
}

DateTime? parseTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// `status` of the week doc.
class ReminiscenceWeekStatus {
  ReminiscenceWeekStatus._();
  static const inProgress = 'in_progress';
  static const questionsDone = 'questions_done';
  static const chapterRequested = 'chapter_requested';
  static const chapterReady = 'chapter_ready';
}

/// `users/{uid}/reminiscence_v2/week_{N}`.
class ReminiscenceWeekState {
  ReminiscenceWeekState({
    required this.weekIndex,
    required this.arm,
    this.configVersion = ReminiscenceV2Copy.version,
    this.status = ReminiscenceWeekStatus.inProgress,
    this.currentQuestion = 1,
    Map<int, int>? followupsAsked,
    List<ReminiscenceMessage>? messages,
    this.ratedRequestId,
    this.chapterRequestedAtMessage,
    this.createdAt,
    this.exists = false,
  })  : followupsAsked = followupsAsked ?? <int, int>{},
        messages = messages ?? <ReminiscenceMessage>[];

  final int weekIndex;

  /// 'A' (Hybrid) or 'B' (rule arm), like the M3 week doc.
  final String arm;
  String configVersion;
  String status;

  /// 1–8: the question being asked; 9 = all eight done.
  int currentQuestion;

  /// Follow-ups the LLM asked per question (Hybrid; the rule arm keeps 0).
  final Map<int, int> followupsAsked;
  final List<ReminiscenceMessage> messages;

  /// The chapter request (`requestId`) the elder has rated: the rating
  /// shows once per chapter version, i.e. per request.
  String? ratedRequestId;

  /// How many messages the last chapter request covered: more messages
  /// since (再講多啲) offer 「重新整理」.
  int? chapterRequestedAtMessage;
  DateTime? createdAt;

  /// Whether the doc was found in the store (the first save adds
  /// `createdAt`).
  bool exists;

  int get followupsForCurrent => followupsAsked[currentQuestion] ?? 0;

  bool get questionsFinished => currentQuestion > ReminiscenceV2Copy.questionsPerWeek;

  Map<String, dynamic> toMap({required bool includeMessages}) => {
        'weekIndex': weekIndex,
        'arm': arm,
        'configVersion': configVersion,
        'status': status,
        'currentQuestion': currentQuestion,
        'followupsAsked': {
          for (final e in followupsAsked.entries) '${e.key}': e.value,
        },
        // Consent off: the server copy has no words (kept on the device).
        'messages': includeMessages
            ? [for (final m in messages) m.toMap()]
            : const <Map<String, dynamic>>[],
        'transcriptRetained': includeMessages,
        if (ratedRequestId != null) 'ratedRequestId': ratedRequestId,
        if (chapterRequestedAtMessage != null)
          'chapterRequestedAtMessage': chapterRequestedAtMessage,
      };

  static ReminiscenceWeekState fromMap(
    Map<String, dynamic> m, {
    required int weekIndex,
    required String arm,
  }) {
    final raw = (m['followupsAsked'] as Map?) ?? const {};
    return ReminiscenceWeekState(
      weekIndex: (m['weekIndex'] as num?)?.toInt() ?? weekIndex,
      arm: (m['arm'] as String?) ?? arm,
      configVersion:
          (m['configVersion'] as String?) ?? ReminiscenceV2Copy.version,
      status: (m['status'] as String?) ?? ReminiscenceWeekStatus.inProgress,
      currentQuestion: (m['currentQuestion'] as num?)?.toInt() ?? 1,
      followupsAsked: {
        for (final e in raw.entries)
          if (int.tryParse('${e.key}') != null && e.value is num)
            int.parse('${e.key}'): (e.value as num).toInt(),
      },
      messages: [
        for (final x in ((m['messages'] as List?) ?? const []))
          if (x is Map)
            ?ReminiscenceMessage.fromMap(Map<String, dynamic>.from(x)),
      ],
      ratedRequestId: m['ratedRequestId'] as String?,
      chapterRequestedAtMessage:
          (m['chapterRequestedAtMessage'] as num?)?.toInt(),
      createdAt: parseTime(m['createdAt']),
      exists: true,
    );
  }
}

/// `status` of the chapter doc.
class ReminiscenceChapterStatus {
  ReminiscenceChapterStatus._();
  static const requested = 'requested';
  static const generating = 'generating';
  static const ready = 'ready';
  static const failed = 'failed';
}

/// `users/{uid}/reminiscence_chapters/week_{N}` as the App reads it.
class ReminiscenceChapterDoc {
  const ReminiscenceChapterDoc({
    required this.weekIndex,
    required this.source,
    required this.status,
    this.requestId,
    this.finalText,
    this.ruleText,
    this.version,
    this.editedText,
    this.editRatio,
    this.savedAt,
    this.requestedAt,
  });

  final int weekIndex;

  /// 'hybrid' | 'rule'.
  final String source;
  final String status;
  final String? requestId;

  /// Server (Hybrid).
  final String? finalText;

  /// App (rule arm).
  final String? ruleText;
  final int? version;
  final String? editedText;
  final double? editRatio;
  final DateTime? savedAt;
  final DateTime? requestedAt;

  bool get isReady => status == ReminiscenceChapterStatus.ready;
  bool get isFailed => status == ReminiscenceChapterStatus.failed;
  bool get isRule => source == 'rule';

  /// The text the ratings are about (never the elder's edit).
  String get originalText => (isRule ? ruleText : finalText) ?? '';

  /// What the elder sees: their own edit once saved, else the original.
  String get displayText {
    final e = editedText;
    return e != null && e.trim().isNotEmpty ? e : originalText;
  }

  static ReminiscenceChapterDoc fromMap(Map<String, dynamic> m,
          {required int weekIndex}) =>
      ReminiscenceChapterDoc(
        weekIndex: (m['weekIndex'] as num?)?.toInt() ?? weekIndex,
        source: (m['source'] as String?) ?? 'hybrid',
        status: (m['status'] as String?) ?? ReminiscenceChapterStatus.requested,
        requestId: m['requestId'] as String?,
        finalText: m['finalText'] as String?,
        ruleText: m['ruleText'] as String?,
        version: (m['version'] as num?)?.toInt(),
        editedText: m['editedText'] as String?,
        editRatio: (m['editRatio'] as num?)?.toDouble(),
        savedAt: parseTime(m['savedAt']),
        requestedAt: parseTime(m['requestedAt']),
      );
}

/// Pure helpers shared by both arms (unit-tested).
class ReminiscenceV2Logic {
  ReminiscenceV2Logic._();

  /// Rule arm line after an answer: the first general line not used in the
  /// last two general lines of this week (G1 → G2 → G3 → G1 …).  Returns
  /// (copyId, text).
  static (String, String) nextGeneralLine(List<ReminiscenceMessage> messages) {
    final used = [
      for (final m in messages)
        if (m.kind == ReminiscenceMessageKind.fixedLine &&
            (m.copyId ?? '').startsWith('G'))
          m.copyId!,
    ];
    final recent = used.length <= 2 ? used : used.sublist(used.length - 2);
    for (var i = 0; i < ReminiscenceV2Copy.generalLines.length; i++) {
      final id = 'G${i + 1}';
      if (!recent.contains(id)) return (id, ReminiscenceV2Copy.generalLines[i]);
    }
    return ('G1', ReminiscenceV2Copy.generalLines.first);
  }

  /// Rule arm line after a `moderate_review` answer (grief / past
  /// hardship) to Q1–Q6: rule-templates.md rule 3 — the Z5 group, rotated
  /// the same way.  [z5] is (id, text) in order.
  static (String, String) nextGriefLine(
      List<ReminiscenceMessage> messages, List<(String, String)> z5) {
    final used = [
      for (final m in messages)
        if ((m.copyId ?? '').startsWith('Z5')) m.copyId!,
    ];
    final recent = used.length <= 2 ? used : used.sublist(used.length - 2);
    for (final e in z5) {
      if (!recent.contains(e.$1)) return e;
    }
    return z5.first;
  }

  /// The main answer to question [q] (null when skipped or flagged).
  static ReminiscenceMessage? answerTo(
          List<ReminiscenceMessage> messages, int q) =>
      _first(messages, ReminiscenceMessageKind.answer, q);

  static ReminiscenceMessage? _first(
      List<ReminiscenceMessage> messages, ReminiscenceMessageKind kind, int q) {
    for (final m in messages) {
      if (m.kind == kind && m.questionIndex == q) return m;
    }
    return null;
  }

  /// Whether 唔想講 was pressed on the question itself (not a follow-up).
  static bool questionSkipped(List<ReminiscenceMessage> messages, int q) {
    for (final m in messages) {
      if (m.questionIndex != q) continue;
      if (m.kind == ReminiscenceMessageKind.answer) return false;
      if (m.kind == ReminiscenceMessageKind.skip) return true;
    }
    return false;
  }

  /// Answers the elder gave in this list (skips and flagged ones not
  /// counted).
  static int answeredCount(List<ReminiscenceMessage> messages) => messages
      .where((m) => m.kind == ReminiscenceMessageKind.answer && !m.flagged)
      .length;

  /// The chapter request's `input` (contract): the whole week, so the
  /// server never reads `reminiscence_v2`.  Flagged messages (a safety
  /// stop) are left out: `answer` null; such a follow-up answer null.
  static Map<String, dynamic> chapterInput(
      int weekIndex, List<ReminiscenceMessage> messages) {
    final week = ReminiscenceV2Copy.week(weekIndex);
    final items = <Map<String, dynamic>>[];
    for (var q = 1; q <= ReminiscenceV2Copy.questionsPerWeek; q++) {
      final answer = answerTo(messages, q);
      final followups = <Map<String, dynamic>>[];
      String? reply;
      ReminiscenceMessage? pendingFollowup;
      for (final m in messages) {
        if (m.questionIndex != q) continue;
        switch (m.kind) {
          case ReminiscenceMessageKind.followup:
            if (pendingFollowup != null) {
              followups.add({'q': pendingFollowup.text, 'a': null});
            }
            pendingFollowup = m;
          case ReminiscenceMessageKind.followupAnswer:
          case ReminiscenceMessageKind.skip:
            if (pendingFollowup != null) {
              final ok = m.kind == ReminiscenceMessageKind.followupAnswer &&
                  !m.flagged;
              followups.add({'q': pendingFollowup.text, 'a': ok ? m.text : null});
              pendingFollowup = null;
            }
          case ReminiscenceMessageKind.reply:
            reply = m.text;
          default:
            break;
        }
      }
      if (pendingFollowup != null) {
        followups.add({'q': pendingFollowup.text, 'a': null});
      }
      items.add({
        'questionIndex': q,
        'question': week.question(q),
        'answer': answer == null || answer.flagged ? null : answer.text,
        'skipped': questionSkipped(messages, q),
        'followups': followups,
        'reply': reply,
      });
    }
    final extras = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.kind != ReminiscenceMessageKind.extra || m.flagged) continue;
      String? reply;
      if (i + 1 < messages.length &&
          messages[i + 1].kind == ReminiscenceMessageKind.extraReply) {
        reply = messages[i + 1].text;
      }
      extras.add({'text': m.text, 'reply': reply});
    }
    return {'themeZh': week.themeZh, 'items': items, 'extras': extras};
  }

  /// Rule arm chapter body (the title 「第 N 章：{主題}」 is drawn above
  /// it): for each answered question its short title, then the elder's
  /// own words verbatim; 唔想講 questions are left out.  再講多啲 messages
  /// follow under 「再講多啲」.
  static String ruleChapterText(
      int weekIndex, List<ReminiscenceMessage> messages) {
    final week = ReminiscenceV2Copy.week(weekIndex);
    final parts = <String>[];
    for (var q = 1; q <= ReminiscenceV2Copy.questionsPerWeek; q++) {
      final a = answerTo(messages, q);
      if (a == null || a.flagged || a.text.trim().isEmpty) continue;
      parts.add('${week.shortTitle(q)}\n${a.text}');
    }
    final extras = [
      for (final m in messages)
        if (m.kind == ReminiscenceMessageKind.extra &&
            !m.flagged &&
            m.text.trim().isNotEmpty)
          m.text,
    ];
    if (extras.isNotEmpty) {
      parts.add('${ReminiscenceV2Copy.extraSectionTitle}\n${extras.join('\n')}');
    }
    return parts.join('\n\n');
  }

  /// The elder's own words, for the rule arm's 80-character-summary slot
  /// (M3 week doc, as the old rule-arm page stored the raw note).
  static String answersJoined(List<ReminiscenceMessage> messages) => [
        for (final m in messages)
          if ((m.kind == ReminiscenceMessageKind.answer ||
                  m.kind == ReminiscenceMessageKind.followupAnswer ||
                  m.kind == ReminiscenceMessageKind.extra) &&
              !m.flagged)
            m.text,
      ].join('\n');

  /// Edit ratio = character-level Levenshtein distance between the
  /// original and the edited text (insert / delete / substitute one
  /// character = 1; characters are Unicode code points, so one Chinese
  /// character counts once) ÷ the original's length.  0 = unchanged;
  /// 1 = as many single-character edits as the original has characters
  /// (it can go above 1 when a lot is added).  Empty original: 0 when
  /// the edit is empty too, else 1.
  static double editRatio(String original, String edited) {
    final a = original.runes.toList();
    final b = edited.runes.toList();
    if (a.isEmpty) return b.isEmpty ? 0 : 1;
    return levenshtein(a, b) / a.length;
  }

  static int levenshtein(List<int> a, List<int> b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }
}

// 1020l (1020j 一 (4)) — the research transcript: every chat turn writes
// the elder's message and the reply shown to
// users/{uid}/chat_transcripts/{turnId} while the switch
// `researchTranscriptEnabled` is on (ChatSessionRecorder.logTurn).
//   - the row has exactly the fields firestore.rules allows, no arm field;
//   - texts are clipped to the rules' limits;
//   - the switch is off unless literally true;
//   - every TurnRecord built anywhere in lib/ passes `userText:`, so no
//     chat page (either arm) silently drops the elder's words.
// The rules themselves: test/rules/chat_transcripts_rules.test.js.
// Decision 0069: rows are schema 2 now (`role`, `userInput`; the
// reply as shown) — test/research_transcript_v2_test.dart has the rest.
import 'dart:io';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 20, 18, 0);

TurnRecord _turn({
  String? userText = '今日去咗飲茶。',
  String reply = '聽落幾開心喎。',
  LlmStatus status = LlmStatus.ok,
  bool shortCircuited = false,
}) =>
    TurnRecord(
      agentId: 'siu_yan',
      moduleId: 'siu_yan_chat',
      userSent: _t0,
      replyShown: _t0.add(const Duration(seconds: 3)),
      modality: InputModality.text,
      charCount: userText?.length ?? 0,
      userText: userText,
      detector: const DistressMatch(DistressLevel.none),
      shortCircuited: shortCircuited,
      ackShown: false,
      response: LlmResponse(
        text: reply,
        inputFlag: const DistressMatch(DistressLevel.none),
        outputFlag: const DistressMatch(DistressLevel.none),
        shortCircuited: shortCircuited,
        metadata: const TurnMetadata(systemPromptHash: 'h'),
        status: status,
      ),
    );

/// The key list of `transcriptKeys()` in firestore.rules.
List<String> _rulesKeys() {
  final rules = File('firestore.rules').readAsStringSync();
  final m = RegExp(r'function transcriptKeys\(\) \{\s*return \[([^\]]*)\]')
      .firstMatch(rules);
  expect(m, isNotNull, reason: 'transcriptKeys() in firestore.rules');
  return RegExp(r"'([a-zA-Z]+)'")
      .allMatches(m!.group(1)!)
      .map((x) => x.group(1)!)
      .toList();
}

void main() {
  test('row: exactly the fields the rules allow, no arm, the words kept', () {
    final m = _turn().transcriptMap(sessionId: 's1', turnId: 't1');
    expect(m.keys.toSet(), _rulesKeys().toSet());
    expect(m.keys, isNot(contains('arm')));
    expect(m['role'], 'elder');
    expect(m['userInput'], 'text');
    expect(m['sessionId'], 's1');
    expect(m['turnId'], 't1');
    expect(m['agentId'], 'siu_yan');
    expect(m['moduleId'], 'siu_yan_chat');
    expect(m['userText'], '今日去咗飲茶。');
    expect(m['replyText'], '聽落幾開心喎。');
    expect(m['replyStatus'], 'ok');
    expect(m['userSentAt'], Timestamp.fromDate(_t0));
    expect(m['replyShownAt'],
        Timestamp.fromDate(_t0.add(const Duration(seconds: 3))));
    expect(m['receivedAt'], isA<FieldValue>());
    expect(m['schemaVersion'], 2);
  });

  test('rule template, crisis short-circuit, no free text', () {
    final rule = _turn(reply: '多謝你講俾我聽。', status: LlmStatus.ruleBased)
        .transcriptMap(sessionId: 's', turnId: 't');
    expect(rule['replyStatus'], LlmStatus.ruleBased.code);
    expect(rule['replyText'], '多謝你講俾我聽。');
    final crisis = _turn(
            reply: '', status: LlmStatus.shortCircuited, shortCircuited: true)
        .transcriptMap(sessionId: 's', turnId: 't');
    expect(crisis['replyText'], '');
    expect(crisis['userText'], '今日去咗飲茶。');
    final buttons =
        _turn(userText: null).transcriptMap(sessionId: 's', turnId: 't');
    expect(buttons.containsKey('userText'), isTrue);
    expect(buttons['userText'], isNull);
    expect(buttons['userInput'], isNull);
  });

  test('texts clipped to the rules limits (5000 / 10000)', () {
    final m = _turn(userText: 'a' * 6000, reply: 'b' * 12000)
        .transcriptMap(sessionId: 's', turnId: 't');
    expect((m['userText'] as String).length, TurnRecord.maxUserChars);
    expect((m['replyText'] as String).length, TurnRecord.maxReplyChars);
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('d.userText.size() <= ${TurnRecord.maxUserChars}'));
    expect(rules, contains('d.replyText.size() <= ${TurnRecord.maxReplyChars}'));
  });

  test('switch: off by default, on only for literal true', () {
    expect(const RemoteFeatureFlags().researchTranscriptEnabled, isFalse);
    expect(
        RemoteFeatureFlags.fromMap(const {'researchTranscriptEnabled': 'true'})
            .researchTranscriptEnabled,
        isFalse);
    expect(
        RemoteFeatureFlags.fromMap(const {'researchTranscriptEnabled': true})
            .researchTranscriptEnabled,
        isTrue);
  });

  test('every TurnRecord in lib/ passes userText (all chat pages, both arms)',
      () {
    final missing = <String>[];
    var count = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\bTurnRecord\(').allMatches(src)) {
        final before = src.substring(0, m.start);
        // Skip the declaration and the constructor itself.
        if (before.endsWith('class ') || before.endsWith('const ')) continue;
        // The argument list: up to the matching parenthesis.
        var depth = 0;
        var end = m.end - 1;
        for (var i = m.end - 1; i < src.length; i++) {
          final c = src[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
        count++;
        final args = src.substring(m.end, end);
        if (!args.contains('userText:')) {
          final line = '\n'.allMatches(before).length + 1;
          missing.add('${f.path}:$line');
        }
      }
    }
    expect(count, greaterThanOrEqualTo(15));
    expect(missing, isEmpty);
  });
}

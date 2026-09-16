/// Phase A baseline — L-1 / L-3 / M-1 / M-6 logging-layer contract tests
/// (pure parts: TurnRecord shape, referral + TE scanners, feedback reasons,
/// session summary pointer, PhaseAConfig merge).
import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/llm/turn_metadata.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/response_feedback/data/response_feedback.dart';
import 'package:app_demo/features/thought_exercise/presentation/naming_thought_card.dart';
import 'package:flutter_test/flutter_test.dart';

LlmResponse _resp({
  String text = '聽到。',
  LlmStatus status = LlmStatus.ok,
  Map<String, dynamic> flags = const {
    'specific_content_engagement': true,
    'cross_session_memory': false,
    'honest_unfamiliarity': false,
    'mixed_content_routing': true,
    'generative_summary': false,
    '_version': 2,
  },
}) =>
    LlmResponse(
      text: text,
      inputFlag: const DistressMatch(DistressLevel.none),
      outputFlag: const DistressMatch(DistressLevel.none),
      shortCircuited: false,
      metadata: const TurnMetadata(systemPromptHash: 'abc', promptKey: 'siu_yan_v1'),
      llmFlags: flags,
      status: status,
      error: status == LlmStatus.fallback ? 'timeout' : null,
      model: status == LlmStatus.ok ? 'deepseek-chat' : null,
      latencyMs: 1234,
      temperature: 0.7,
      promptVersion: 'siu_yan_v1@2026-06',
    );

void main() {
  group('TurnRecord → turns/{turnId} document (L-1)', () {
    test('carries every spec field with the right shape', () {
      const det = DistressDetector();
      final match = det.analyze('冇人理我，我係個負擔');
      final rec = TurnRecord(
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        userSent: DateTime(2026, 9, 11, 10, 0, 0),
        replyShown: DateTime(2026, 9, 11, 10, 0, 4),
        modality: InputModality.voice,
        voiceDurationMs: 5200,
        charCount: 10,
        detector: match,
        shortCircuited: false,
        ackShown: true,
        response: _resp(text: '聽到你咁講。呢啲嘢小欣比我擅長，要唔要過去搵佢？'),
      );
      final m = rec.toMap(participantId: 'u1', sessionId: 's1');
      expect(m['participantId'], 'u1');
      expect(m['sessionId'], 's1');
      expect((m['input'] as Map)['modality'], 'voice');
      expect((m['input'] as Map)['voiceDurationMs'], 5200);
      expect((m['input'] as Map)['charCount'], 10);
      final d = m['detector'] as Map;
      expect(d['tier'], 'moderate_interrupt');
      expect(d['matchedTerm'], '冇人理我');
      expect(d['category'], 'distress');
      expect(d['lexiconVersion'], 'v5-2026-09');
      expect(d['ackShown'], true);
      final llm = m['llm'] as Map;
      expect(llm['status'], 'ok');
      expect(llm['model'], 'deepseek-chat');
      expect(llm['promptVersion'], 'siu_yan_v1@2026-06');
      expect(llm['temperature'], 0.7);
      expect(llm['systemPromptHash'], 'abc');
      final flags = m['flags'] as Map;
      expect(flags.keys.toList(), ['F1', 'F2', 'F3', 'F4', 'F5']);
      expect(flags['F1'], true);
      expect(flags['F4'], true);
      expect(flags['F2'], false);
      // Referral detected from the reply text (regex) — target Siu Yan.
      expect((m['referral'] as Map)['offered'], true);
      expect((m['referral'] as Map)['target'], 'siu_yan');
      expect((m['te'] as Map)['offered'], false);
      expect((m['feedback'] as Map)['thumb'], isNull);
    });

    test('fallback turn: flags all null, status fallback, error kept', () {
      final rec = TurnRecord(
        agentId: 'tung_tung',
        moduleId: 'tung_tung_chat',
        userSent: DateTime(2026, 9, 11),
        replyShown: DateTime(2026, 9, 11),
        modality: InputModality.text,
        charCount: 3,
        detector: const DistressMatch(DistressLevel.none),
        shortCircuited: false,
        ackShown: false,
        response: _resp(text: '', status: LlmStatus.fallback),
        tungTungMode: 'B',
      );
      final m = rec.toMap(participantId: 'u', sessionId: 's');
      expect((m['llm'] as Map)['status'], 'fallback');
      expect((m['llm'] as Map)['error'], 'timeout');
      expect((m['flags'] as Map).values.every((v) => v == null), true);
      expect((m['tungtung'] as Map)['mode'], 'B');
      expect((m['tungtung'] as Map)['searchInvoked'], false);
      expect(rec.isFallback, true);
    });

    test('TE offer text from the card is logged verbatim (L-3)', () {
      final offer = NamingThoughtCard.invitationText('打畀阿女只會煩到佢', isEn: false);
      expect(offer, startsWith('你頭先講咗一句令我有少少 stuck — 「打畀阿女只會煩到佢」'));
      final rec = TurnRecord(
        agentId: 'siu_yan',
        moduleId: 'm2_check_in',
        userSent: DateTime(2026, 9, 11),
        replyShown: DateTime(2026, 9, 11),
        modality: InputModality.text,
        charCount: 9,
        detector: const DistressMatch(DistressLevel.none),
        shortCircuited: false,
        ackShown: false,
        response: _resp(),
        teOfferText: offer,
      );
      final m = rec.toMap(participantId: 'u', sessionId: 's');
      expect((m['te'] as Map)['offered'], true);
      expect((m['te'] as Map)['offerText'], offer);
    });
  });

  group('Scanners', () {
    test('TeOfferScanner extracts the whole locked sentence from a reply', () {
      const reply = '聽到你話打畀阿女只會煩到佢。你頭先講咗一句令我有少少 stuck — '
          '『打畀阿女只會煩到佢』。要唔要做個小練習慢慢望一望呢個諗法？要唔要都得。\n下次再傾。';
      expect(
        TeOfferScanner.scan(reply),
        '你頭先講咗一句令我有少少 stuck — 『打畀阿女只會煩到佢』。要唔要做個小練習慢慢望一望呢個諗法？要唔要都得。',
      );
      expect(TeOfferScanner.scan('普通回覆。'), isNull);
    });

    test('ReferralScanner maps phrasing to a target agent', () {
      expect(ReferralScanner.scan('呢類嘢小欣比我擅長 — 要唔要過去搵佢？'), 'siu_yan');
      expect(ReferralScanner.scan('呢類回憶嘅嘢，阿珍／阿伯比我細心，要唔要同阿伯傾下？'),
          'ah_jan_ah_bak');
      expect(ReferralScanner.scan('呢類資料嘅嘢通通好叻 — 要唔要過去搵通通？'), 'tung_tung');
      expect(ReferralScanner.scan('Maybe talk to Tung Tung about that?'), 'tung_tung');
      expect(ReferralScanner.scan('今日天氣幾好。'), isNull);
    });
  });

  group('Session helpers', () {
    test('sessionSummaryHasTEPointer is a plain string match', () {
      expect(ChatSessionRecorder.hasTePointer(
          '呢個禮拜你講起阿嫲。如果你想之後望一望嗰個諗法，可以喺「做啲嘢」入面搵「望一望心入面」。'),
          true);
      expect(ChatSessionRecorder.hasTePointer('呢個禮拜你講起阿嫲嘅煲仔飯。'), false);
    });

    test('M-6 thumbs-down reasons: exactly four, single-select ids', () {
      expect(ResponseFeedbackReasons.all, [
        'not_understand',
        'wrong_topic',
        'not_helpful',
        'other',
      ]);
      expect(ResponseFeedbackReasons.labels.values.toList(),
          ['唔明白我', '講錯話題', '冇幫助', '其他']);
    });
  });

  group('PhaseAConfig', () {
    test('defaults match the spec', () {
      const c = PhaseAConfig();
      expect(c.sessionIdleTimeoutMin, 10);
      expect(c.briefPRMinTurns, 2);
      expect(c.briefPRItemCount, 4);
      expect(c.weeklyPrPushHour, 20);
      expect(c.weeklyPrCloseWeekday, DateTime.tuesday);
      expect(c.w2DayOffset, 14);
      expect(c.w2WindowDays, 3);
      expect(c.week1NudgeDays, [3, 6]);
    });

    test('remote override merges and clamps briefPRItemCount to {3,4}', () {
      final c = PhaseAConfig.fromMap({'briefPRItemCount': 3, 'sessionIdleTimeoutMin': 15});
      expect(c.briefPRItemCount, 3);
      expect(c.sessionIdleTimeoutMin, 15);
      expect(c.briefPRMinTurns, 2);
      expect(PhaseAConfig.fromMap({'briefPRItemCount': 9}).briefPRItemCount, 4);
    });
  });
}

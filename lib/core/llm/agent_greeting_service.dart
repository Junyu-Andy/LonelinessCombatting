/// Pre-generated, personalized agent greeting cache (Sprint 1).
///
/// Goal: when the user opens Ah Jan / Ah Bak or Tung Tung, the very
/// first bot bubble references something specific from the user's
/// profile or prior conversations (rolling summary on the per-agent
/// context doc, week-N reminiscence prompt, an onboarding interest)
/// rather than a generic "你今日點？" boilerplate.
///
/// Storage shape:
///   users/{uid}/agent_greetings/{YYYY-MM-DD}_{agentId}
///     - text:        String
///     - lang:        'zh' | 'en'
///     - generatedAt: server timestamp
///     - agentId:     String
///
/// Lifecycle:
///   1. TodayPage warms the cache fire-and-forget on each entry, one
///      ensureGreeting() per (ah_jan_ah_bak, tung_tung).
///   2. When the user taps into the agent's page, the page calls
///      readCachedGreeting() first.  Cache hit -> use the personalized
///      opener.  Miss (or guest mode / Firebase error) -> the page
///      falls back to the existing hardcoded opener (no regression).
///
/// Siu Yan is handled separately by the mood-aware opener flow.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/auth/data/user_profile.dart';
import '../agent_context/agent_context_service.dart';
import 'llm_gateway.dart';

class AgentGreetingService {
  AgentGreetingService(this._llm, {AgentContextService? agentContext})
      : _agentContext = agentContext;

  final LlmGateway _llm;

  /// Optional — when supplied, the service reads the agent's rolling
  /// summary to compose `lastSessionTopic`.  Without it the prompt
  /// falls back to interest-only personalisation.
  final AgentContextService? _agentContext;

  /// Soft caps so a runaway LLM response doesn't blow out the chat
  /// bubble.  Cantonese characters count as 1; English uses ~2x.
  static const int _zhCharCap = 120;
  static const int _enCharCap = 250;

  /// Reads the cached greeting if one exists for today AND matches the
  /// current locale.  Returns null on miss / locale mismatch /
  /// guest mode / Firebase error.
  Future<String?> readCachedGreeting({
    required String uid,
    required String agentId,
    required bool isEn,
  }) async {
    if (uid.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('agent_greetings')
          .doc(_docId(agentId))
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final text = (data['text'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      final lang = data['lang'] as String?;
      final wanted = isEn ? 'en' : 'zh';
      if (lang != null && lang != wanted) return null;
      return text;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AgentGreetingService] readCachedGreeting error: $e');
      }
      return null;
    }
  }

  /// Generate-and-cache.  Idempotent — if today's greeting already
  /// exists for the requested locale, returns it without calling the
  /// LLM.  Otherwise calls the LLM via the existing gateway and
  /// writes the result.  Returns null on any failure so callers can
  /// fall back to the hardcoded opener.
  Future<String?> ensureGreeting({
    required String uid,
    required String agentId,
    required UserProfile profile,
    required bool isEn,
  }) async {
    if (uid.isEmpty) return null;
    final cached =
        await readCachedGreeting(uid: uid, agentId: agentId, isEn: isEn);
    if (cached != null) return cached;

    String? lastSessionTopic;
    if (_agentContext != null) {
      try {
        final snap = await _agentContext!.read(uid: uid, agentId: agentId);
        final summary = snap.rollingSummary.trim();
        if (summary.isNotEmpty) lastSessionTopic = _trimSummary(summary);
      } catch (_) {
        // best-effort — fall through with null
      }
    }

    final weekIndex = _weekIndexSince(profile.createdAt);
    final systemPrompt = _buildPrompt(
      agentId: agentId,
      profile: profile,
      isEn: isEn,
      lastSessionTopic: lastSessionTopic,
      weekIndex: weekIndex,
    );

    try {
      final response = await _llm.send(
        moduleId: 'greeting_$agentId',
        systemPrompt: systemPrompt,
        agentId: agentId,
        userInput: isEn
            ? "Generate today's greeting."
            : '生成今日嘅開場白。',
        history: const [],
        uid: uid,
        armCode: profile.arm?.code,
      );
      final text = _capText(response.text.trim(), isEn);
      if (text.isEmpty) return null;
      await _writeCache(
        uid: uid,
        agentId: agentId,
        text: text,
        isEn: isEn,
      );
      return text;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AgentGreetingService] ensureGreeting LLM error: $e');
      }
      return null;
    }
  }

  Future<void> _writeCache({
    required String uid,
    required String agentId,
    required String text,
    required bool isEn,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('agent_greetings')
          .doc(_docId(agentId))
          .set({
        'text': text,
        'lang': isEn ? 'en' : 'zh',
        'agentId': agentId,
        'generatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AgentGreetingService] _writeCache error: $e');
      }
    }
  }

  String _docId(String agentId) => '${_todayKey()}_$agentId';

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 1-indexed week since signup, capped at 4 to match the M3
  /// 4-week reminiscence curriculum.  Null createdAt -> week 1.
  int _weekIndexSince(DateTime? createdAt) {
    if (createdAt == null) return 1;
    final days = DateTime.now().difference(createdAt).inDays;
    final w = (days ~/ 7) + 1;
    if (w < 1) return 1;
    if (w > 4) return 4;
    return w;
  }

  String _trimSummary(String s) {
    // Pass the first ~240 chars of the rolling summary — enough for
    // a topic seed, not so much it dominates the prompt.
    if (s.length <= 240) return s;
    return '${s.substring(0, 240)}…';
  }

  String _capText(String s, bool isEn) {
    final cap = isEn ? _enCharCap : _zhCharCap;
    if (s.length <= cap) return s;
    return '${s.substring(0, cap)}…';
  }

  String _buildPrompt({
    required String agentId,
    required UserProfile profile,
    required bool isEn,
    required String? lastSessionTopic,
    required int weekIndex,
  }) {
    final interests = profile.interests.isEmpty
        ? (isEn ? '(none captured)' : '(未有記錄)')
        : profile.interests.take(8).join(isEn ? ', ' : '、');
    final avoid = (profile.avoidTopics ?? '').trim().isEmpty
        ? (isEn ? '(none)' : '冇')
        : profile.avoidTopics!.trim();
    final lastTopic = (lastSessionTopic ?? '').trim().isEmpty
        ? (isEn ? '(no prior session)' : '(冇之前傾過)')
        : lastSessionTopic!.trim();

    if (agentId == 'ah_jan_ah_bak') {
      if (isEn) {
        return '''
You are Ah Jan / Ah Bak, a reflective peer-listener helping a Hong Kong
elder revisit life memories. Here is the user's context:
- Interests: $interests
- Last session topic (if any): $lastTopic
- Current week: $weekIndex (4-week M3 reminiscence cycle)
- Do NOT bring up: $avoid

Write ONE short opener (1-2 sentences, warm conversational English) that:
- Naturally references a specific detail the user mentioned before
  (if lastSessionTopic is available), OR
- Cues a reminiscence prompt appropriate for week $weekIndex
  (week 1 = childhood, week 2 = youth/family formation,
   week 3 = midlife/work, week 4 = present/future)
- AVOID generic openers like "How are you today?"
- Do NOT mention other agents by name
- Keep it under $_enCharCap characters.

Example: "Last time you mentioned your older sister taking you to the
wet market to pick fish — would you like to share more about those days?"
''';
      }
      return '''
你係阿珍／阿伯，一位 reflective peer-listener，幫一位香港長者整理人生回憶。
以下係用戶嘅 context:
- 興趣: $interests
- 上次傾過 (如果有): $lastTopic
- 而家係第 $weekIndex 個禮拜 (4-week M3 reminiscence cycle)
- 唔好提起: $avoid

請寫一句短嘅開場白 (1-2 句, 粵語口語繁體中文)，要：
- 自然提起一個用戶之前講過嘅具體細節 (如果有 lastSessionTopic)
- 或者引一個適合 week $weekIndex 嘅 reminiscence prompt
  (week 1 = 童年, week 2 = 青年/成家, week 3 = 中年/工作, week 4 = 而家/未來)
- 唔好用 "你今日點？" 呢類 generic 嘅嘢
- 唔好提其他 agent 名
- 唔好超過 $_zhCharCap 個字。

例: "上次你話起家姐成日帶你去街市揀魚，今日想再講多啲嗰啲日子嗎？"
''';
    }

    // tung_tung
    if (isEn) {
      return '''
You are Tung Tung, a curious AI companion who loves chatting with Hong
Kong elders about their interests. Here is the user's context:
- Interests: $interests
- Last session topic (if any): $lastTopic
- Do NOT bring up: $avoid

Write ONE short opener (1-2 sentences, light + curious English) that:
- Naturally hooks into one of the user's interests (e.g. "cooking"), OR
- Follows up on the last session topic if available
- AVOID generic openers like "How are you today?"
- Do NOT mention other agents by name
- Keep it under $_enCharCap characters.

Example: "I remember you mentioned you love cooking — have you tried any
new dishes lately?"
''';
    }
    return '''
你係通通，一個好奇心強嘅 AI 機械人，鍾意陪香港長者傾偈傾興趣。
以下係用戶 context:
- 興趣: $interests
- 上次傾過 (如果有): $lastTopic
- 唔好提起: $avoid

請寫一句短嘅開場白 (1-2 句, 粵語口語繁體中文)，要：
- 自然引一個用戶嘅 interest (例如 "煮食") 入手
- 或者 follow up 上次傾過嘅話題
- 唔好用 "你今日點？" 呢類 generic 嘅嘢
- 唔好提其他 agent 名
- 唔好超過 $_zhCharCap 個字。

例: "我記得你話鍾意煮餸 — 你最近有冇試新嘅菜式？"
''';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'chat_models.dart';

/// Strategy interface for "how does the bot reply?".
abstract class ChatBackend {
  Future<String> reply({
    required ChatPersona persona,
    required List<ChatMessage> history,
    required String userMessage,
  });
}

/// Default offline backend so the demo works without an API key.
class ScriptedChatBackend implements ChatBackend {
  static final _rand = Random();

  static const _casualReplies = <String>[
    '聽到你咁講，我都覺得溫暖。今日有冇做過一件令自己微笑嘅小事？',
    '辛苦你喇，慢慢嚟。可以同我講多少少嗎？',
    '係喎，呢啲日子確實唔容易。我喺呢度陪住你。',
    '不如我哋一齊諗一個小到可以即刻做到嘅事？',
    '呢個感覺好真實。你想唞一唞，定係繼續傾？',
  ];

  static const _consultReplies = <String>[
    '多謝你信我，肯講出嚟。可以再講多啲令你最唔舒服嘅部分嗎？',
    '聽落去，呢件事好似已經困擾你一段時間。如果用 1 到 10 形容，今日佢嘅重量係幾多？',
    '呢個反應好正常。我哋可以一齊整理一下：邊一個諗法令你最揮之不去？',
    '如果嗰刻有人陪住你，你最希望佢做啲乜？',
    '我建議你可以將呢段筆記同你信任嘅人或社工分享，呢個唔係你一個人要扛嘅事。',
  ];

  static const _faqReplies = <String>[
    '我喺依度幫你解答 app 相關嘅問題。可以講清楚少少你想了解邊方面？',
    '關於呢個功能，你可以入「設定」→ 相關分類睇吓；如果搵唔到，再詳細講畀我知你想做啲乜。',
    '呢個 demo 版本有啲功能仲未上線，但我可以話畀你知應該點用現有功能去解決。',
    '好問題。如果係私隱相關疑問，可以電郵 zhaojyxs@connect.hku.hk 同我哋直接聯絡。',
    '多謝你嘅反饋，我會將呢個問題交畀團隊跟進。暫時有冇其他想問嘅？',
  ];

  @override
  Future<String> reply({
    required ChatPersona persona,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final pool = switch (persona) {
      ChatPersona.casual => _casualReplies,
      ChatPersona.consult => _consultReplies,
      ChatPersona.faq => _faqReplies,
    };
    return pool[_rand.nextInt(pool.length)];
  }
}

/// DeepSeek-powered backend. Pass the API key at build time via
/// `--dart-define=DEEPSEEK_API_KEY=sk-...`; falls back to
/// [ScriptedChatBackend] when no key is present.
class DeepseekChatBackend implements ChatBackend {
  static const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const _endpoint = 'https://api.deepseek.com/chat/completions';

  final ChatBackend _fallback;
  final http.Client _client;

  DeepseekChatBackend({ChatBackend? fallback, http.Client? client})
      : _fallback = fallback ?? ScriptedChatBackend(),
        _client = client ?? http.Client();

  bool get isConfigured => _apiKey.isNotEmpty;

  @override
  Future<String> reply({
    required ChatPersona persona,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    if (!isConfigured) {
      return _fallback.reply(
        persona: persona,
        history: history,
        userMessage: userMessage,
      );
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': persona.systemPrompt},
      // Include prior turns for context (skip the last — it's the user turn
      // we're replying to, already included as userMessage below).
      for (final m in history.take(history.length - 1))
        {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': 'deepseek-chat',
              'messages': messages,
              'max_tokens': 256,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content =
            data['choices'][0]['message']['content'] as String? ?? '';
        return content.trim().isNotEmpty ? content.trim() : await _fallback.reply(
          persona: persona,
          history: history,
          userMessage: userMessage,
        );
      }
      // Non-200: fall through to fallback.
    } catch (_) {
      // Network error or timeout: fall through to fallback.
    }

    return _fallback.reply(
      persona: persona,
      history: history,
      userMessage: userMessage,
    );
  }
}

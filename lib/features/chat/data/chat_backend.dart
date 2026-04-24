import 'dart:async';
import 'dart:math';

import 'chat_models.dart';

/// Strategy interface for "how does the bot reply?". Lets the UI stay
/// ignorant of whether responses come from a scripted demo or a real
/// remote model.
abstract class ChatBackend {
  /// Returns the assistant's reply for the given user message. Implementations
  /// should treat [history] as read-only context (the latest user turn is
  /// already appended at the end).
  Future<String> reply({
    required ChatPersona persona,
    required List<ChatMessage> history,
    required String userMessage,
  });
}

/// Default offline backend so the demo works without an API key. Picks a
/// gentle response from a small canned set per persona, with a small
/// artificial delay so the typing indicator has something to render.
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

/// Skeleton for the DeepSeek-powered backend.
///
/// **Not wired yet.** To finish:
///
/// 1. Add `http: ^1.2.0` to pubspec.yaml.
/// 2. Set `_apiKey` from `--dart-define=DEEPSEEK_API_KEY=...` instead of
///    hard-coding it. Do not commit a real key.
/// 3. Implement [reply] by POSTing to
///    `https://api.deepseek.com/chat/completions` with the chat history
///    converted to `{role, content}` pairs and `persona.systemPrompt`
///    as the first system message.
/// 4. Surface failures as a friendly bot message instead of throwing so
///    the UI never gets stuck.
///
/// Until then [reply] just defers to [ScriptedChatBackend] so the rest of
/// the app keeps working.
class DeepseekChatBackend implements ChatBackend {
  DeepseekChatBackend({String? apiKey, ChatBackend? fallback})
      : _apiKey = apiKey,
        _fallback = fallback ?? ScriptedChatBackend();

  // ignore: unused_field — placeholder for the real impl.
  final String? _apiKey;
  final ChatBackend _fallback;

  bool get isConfigured => _apiKey != null && _apiKey.isNotEmpty;

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
    // TODO(deepseek): POST to /chat/completions with persona.systemPrompt
    // as the first message and history mapped to {role, content}.
    return _fallback.reply(
      persona: persona,
      history: history,
      userMessage: userMessage,
    );
  }
}

/// Two distinct chat personas. The casual one is a friendly companion for
/// daily small-talk; the consult one is a more measured, professional voice
/// for moments the user wants something closer to advice.
enum ChatPersona { casual, consult }

class ChatMessage {
  final String text;
  final bool fromUser;
  final DateTime sentAt;

  const ChatMessage({
    required this.text,
    required this.fromUser,
    required this.sentAt,
  });
}

extension ChatPersonaSystemPrompt on ChatPersona {
  /// System prompt that the DeepSeek backend should send as the first
  /// message of every conversation. Kept here so the persona definition
  /// lives in one place.
  String get systemPrompt {
    switch (this) {
      case ChatPersona.casual:
        return '''
你係「阿暖」，一個輕鬆友善嘅陪伴助手，主要對象係香港嘅長者用戶。
用簡單嘅繁體中文（或英文，跟住用戶語言）。回答要短、溫柔、貼地，
鼓勵用戶分享日常小事，唔好俾建議式長篇大論。每次回覆控制喺三句之內。
''';
      case ChatPersona.consult:
        return '''
你係「李醫師」，一個富同理心嘅長者心理諮詢助手。
用平易近人嘅繁體中文（或英文，跟住用戶語言），語調比阿暖更穩重。
可以幫用戶整理情緒、提出反思問題，但唔好提供醫療診斷；
如果察覺危機跡象，提醒用戶搵專業人士或屋企人。回答最多五句。
''';
    }
  }
}

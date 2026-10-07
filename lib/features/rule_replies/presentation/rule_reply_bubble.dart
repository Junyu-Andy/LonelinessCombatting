import 'package:flutter/material.dart';

import '../../../shared/widgets/rich_chat_text.dart';

/// Which Hybrid page's agent bubble to match (decision 0023: the Arm B
/// reply looks like the Arm A reply on the same surface).
enum RuleReplyBubbleStyle {
  /// `check_in_arm_a.dart` `_TurnBubble`: surfaceContainerHighest.
  checkIn,

  /// `reminiscence_arm_a_page.dart` `_Bubble`: secondaryContainer.
  reminiscence,
}

/// Agent-side chat bubble for an Arm B template reply.  Geometry and type
/// are copied from the Arm A bubbles (radius 18, 16×12 padding, 78 %
/// width, 17 pt / 1.4) so the two arms read the same.
class RuleReplyBubble extends StatelessWidget {
  final String text;
  final RuleReplyBubbleStyle style;
  const RuleReplyBubble({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (style) {
      RuleReplyBubbleStyle.checkIn => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      RuleReplyBubbleStyle.reminiscence => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('rule_reply_bubble'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: RichChatText(
          text: text,
          style: TextStyle(fontSize: 17, height: 1.4, color: fg),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/safety/safety_copy.dart';
import '../pages/emergency_support_page.dart';

/// 1020m 第三节 (decisions-log 10/20 item 84): the one fixed safety message
/// a chat window shows after an acute trigger.
///
/// Every chat page that can trip acute shows this, both arms alike, where
/// the old per-agent acute template used to be.  The old template named only
/// the one hotline flagged `acuteTemplateReference` in the crisis config,
/// so the chat showed a different number from the crisis page's list; it is
/// gone.
/// This message is never written by the model and is never sent to it.
///
///   • Opening sentence: [openingZh] / [openingEn]（【草稿】, wording for
///     Junyu to confirm).
///   • The numbers: exactly the crisis page's list — [SafetyCopy.crisis],
///     read from the same `functions/prompts/crisis_resources.json` the
///     crisis page reads, same order, names and numbers as they are there.
///     No number is written in this file or in any chat page.
///   • Under it, 「打開緊急求助頁」 opens [EmergencySupportPage] the way the
///     acute flow opens it (root navigator, full screen); the page logs
///     `crisis_page_shown(from: crisis_chat_message)`.
class CrisisChatMessage extends StatelessWidget {
  const CrisisChatMessage({super.key});

  /// 【草稿】 Opening sentence (Junyu to confirm).
  static const String openingZh = '你啱啱講嘅嘢好重要。請即刻打以下電話，有人會聽你講：';

  /// Testers' English line (the study UI is Cantonese).
  static const String openingEn =
      'What you just said matters. Please call one of these numbers now. '
      'Someone will listen:';

  static const String buttonZh = '打開緊急求助頁';
  static const String buttonEn = 'Open the emergency help page';

  /// Logged by the crisis page as `crisis_page_shown.from`.
  static const String from = 'crisis_chat_message';

  static const Key messageKey = Key('crisis_chat_message');
  static const Key openButtonKey = Key('crisis_chat_message_open');

  /// The number line of one crisis resource (its `id` in the config).
  static Key numberKey(String resourceId) =>
      Key('crisis_chat_message_number_$resourceId');

  /// The crisis page, opened as the acute flow opens it.
  static Future<void> openCrisisPage(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const EmergencySupportPage(from: from),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final resources = SafetyCopy.crisis.resources;
    final base = TextStyle(fontSize: 17, height: 1.4, color: cs.onErrorContainer);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: messageKey,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEn ? openingEn : openingZh,
              style: base.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final r in resources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(r.name(isEn), style: base),
                    // A number never breaks across two lines.
                    Text(
                      r.number,
                      key: numberKey(r.id),
                      softWrap: false,
                      style: base.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // The App's filled button (theme: label 20, at least 60 high),
            // in the crisis colour.
            FilledButton.icon(
              key: openButtonKey,
              onPressed: () => openCrisisPage(context),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              icon: const Icon(Icons.phone_in_talk_rounded, size: 26),
              label: Text(isEn ? buttonEn : buttonZh),
            ),
          ],
        ),
      ),
    );
  }
}

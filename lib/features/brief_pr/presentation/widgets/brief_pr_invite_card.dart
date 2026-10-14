/// T25 (C14) — the Brief PR invitation card on the companion list page.
///
/// Copy verbatim from docs/spec/copy/short-texts.md:
///   S10a (right after the session): 頭先同{陪伴者}傾完，想問你四條簡單問題，大概半分鐘。
///   S10b (catch-up on next open):  你{今朝／尋晚／星期X 下晝}同{陪伴者}傾過偈，想問返你嗰次嘅感覺，大概半分鐘。
///   Buttons: 「好呀」／「今次唔評」.
/// The card sits inline above the companion tiles: it never blocks the
/// tiles, the tabs or the back key.  Both buttons are at least 48×48 at
/// every text scale.  Same card, same copy in both arms.
library;

import 'package:flutter/material.dart';

import '../../data/brief_pr_record.dart';
import '../../data/brief_pr_scheduler.dart';

class BriefPrInviteCard extends StatelessWidget {
  const BriefPrInviteCard({
    super.key,
    required this.record,
    required this.channel,
    required this.now,
    required this.onAccept,
    required this.onSkip,
  });

  final BriefPrRecord record;

  /// [BriefPrInviteChannel.listPage] → S10a; [BriefPrInviteChannel.catchUp] → S10b.
  final String channel;
  final DateTime now;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  static const acceptLabel = '好呀';
  static const skipLabel = '今次唔評';

  /// S10a / S10b with the placeholders filled.
  static String text({
    required String channel,
    required String agentName,
    required DateTime sessionEndedAt,
    required DateTime now,
  }) {
    if (channel == BriefPrInviteChannel.catchUp) {
      final when = BriefPrScheduler.timePhrase(sessionEndedAt, now);
      return '你$when同$agentName傾過偈，想問返你嗰次嘅感覺，大概半分鐘。';
    }
    return '頭先同$agentName傾完，想問你四條簡單問題，大概半分鐘。';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = text(
      channel: channel,
      agentName: record.agentDisplayName,
      sessionEndedAt: record.sessionEndedAt,
      now: now,
    );
    return Semantics(
      container: true,
      label: body,
      child: Card(
        key: const Key('brief_pr_invite_card'),
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        elevation: 0,
        color: theme.colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 19,
                  height: 1.45,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('brief_pr_accept'),
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 52),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w600),
                    ),
                    child: const Text(acceptLabel),
                  ),
                  OutlinedButton(
                    key: const Key('brief_pr_skip'),
                    onPressed: onSkip,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, 52),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontSize: 19),
                    ),
                    child: const Text(skipLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Naming-thought invitation card (Phase A Proposal §2.6, §M2 spec May 2026).
///
/// **Only Siu Yan is authorised to surface this card** (during M2 daily
/// check-in, Arm A only).  Ah Jan/Ah Bak MUST briefly acknowledge and
/// return to listening — the unconditional listening quality on which
/// PPR-Understanding depends would be compromised otherwise.
///
/// Wording (10/21, decisions-log 10/21 item 133 (2), PI final handoff;
/// docs/spec/copy/thought-exercise.md TE-invite):
///   你頭先講咗一句：「{thought}」。要唔要做個小練習，慢慢望一望呢個諗法？唔做都得。
/// (was the Phase A text 「你頭先講咗一句令我有少少 stuck — …要唔要都得。」).
/// Siu Yan's own chat reply still follows its prompt file; only this card
/// changed.
///
/// Phase B Proposal §4.7 §point 3 declares this the third sanctioned UI
/// asymmetry between arms: Arm B users access the Thought Exercise only
/// via the 做啲嘢 tab tile (no auto-fill); only the Arm A Siu Yan offer
/// pathway exists.
library;

import 'package:flutter/material.dart';

class NamingThoughtCard extends StatelessWidget {
  /// The cognition the detector matched on — used in the invitation copy
  /// and auto-filled into 一 of the Thought Exercise.
  final String thought;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const NamingThoughtCard({
    super.key,
    required this.thought,
    required this.onAccept,
    required this.onDecline,
  });

  /// L-3 — the exact invitation sentence shown to the participant, with the
  /// thought summary filled in.  Logged verbatim on `turns.te.offerText`
  /// because the Thought Exercise offer is audited at 100 %.
  static String invitationText(String thought, {required bool isEn}) => isEn
      ? 'Just now you said: "${_trim(thought)}". Would you like '
          'to do a small practice and slowly look at this thought? '
          "It's fine not to."
      : '你頭先講咗一句：「${_trim(thought)}」。'
          '要唔要做個小練習，慢慢望一望呢個諗法？唔做都得。';

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Spec-exact invitation copy (TE-invite).
                invitationText(thought, isEn: isEn),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      // 10/21: less side padding so 「好，試下」 stays on one
                      // line at the largest App text (1.30) on a 360 phone.
                      style: FilledButton.styleFrom(padding: _buttonPadding),
                      onPressed: onAccept,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Try it' : '好，試下'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: _buttonPadding),
                      onPressed: onDecline,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Not now' : '唔使住'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _buttonPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 16);

  /// Trim long quoted thoughts to keep the card readable.  The full
  /// thought is auto-filled into 一 of the exercise anyway.
  static String _trim(String t) {
    final clean = t.trim();
    if (clean.length <= 30) return clean;
    return '${clean.substring(0, 28)}…';
  }
}

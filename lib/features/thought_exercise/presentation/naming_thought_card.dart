/// Naming-thought invitation card (Phase A Proposal §2.6, §M2 spec May 2026).
///
/// **Only Siu Yan is authorised to surface this card** (during M2 daily
/// check-in, Arm A only).  Ah Jan/Ah Bak MUST briefly acknowledge and
/// return to listening — the unconditional listening quality on which
/// PPR-Understanding depends would be compromised otherwise.
///
/// Wording matches the Phase A locked text:
///   "你頭先講咗一句令我有少少 stuck — '{thought}'.  要唔要做個小練習慢慢望一望
///   呢個諗法？要唔要都得。"
///
/// Phase B Proposal §4.7 §point 3 declares this the third sanctioned UI
/// asymmetry between arms: Arm B users access the Thought Exercise only
/// via the 做啲嘢 tab tile (no auto-fill); only the Arm A Siu Yan offer
/// pathway exists.
library;

import 'package:flutter/material.dart';

class NamingThoughtCard extends StatelessWidget {
  /// The cognition the detector matched on — used in the invitation copy
  /// and auto-filled into Field 3 of the Thought Exercise.
  final String thought;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const NamingThoughtCard({
    super.key,
    required this.thought,
    required this.onAccept,
    required this.onDecline,
  });

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
                // Phase A spec-exact invitation copy.
                isEn
                    ? 'You just said something that I noticed got stuck '
                        'with me — "${_trim(thought)}". Would you like '
                        "to do a small practice to look at that thought? "
                        "Either way is fine."
                    : "你頭先講咗一句令我有少少 stuck — 「${_trim(thought)}」。"
                        '要唔要做個小練習慢慢望一望呢個諗法？要唔要都得。',
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

  /// Trim long quoted thoughts to keep the card readable.  The full
  /// thought is auto-filled into Field 3 of the exercise anyway.
  static String _trim(String t) {
    final clean = t.trim();
    if (clean.length <= 30) return clean;
    return '${clean.substring(0, 28)}…';
  }
}

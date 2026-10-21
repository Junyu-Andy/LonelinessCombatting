/// 1020k (decisions-log 10/20 items 77–79) — a line above a question that
/// tells the elder the next question(s) turn around.  Maria's test: one
/// reverse item inside a run of same-direction items is easily answered
/// the wrong way round.
///
/// Same size as the questionnaire's body text (the DJG intro line, the
/// Weekly PR items: 18).  [emphasis], if given, is bold in the App's
/// accent colour (`colorScheme.primary`) on a light wash of it — never
/// red.  Both arms identical; shown only while
/// `RemoteFeatureFlags.scaleDirectionCuesEnabled` is on.
library;

import 'package:flutter/material.dart';

/// The three lines, as finalised by Junyu (1020k).  Elder-visible.
class DirectionCues {
  DirectionCues._();

  /// Brief PR question 4 (insensitivity), above the stem.
  static const briefPrQ4 = '最後一題反過嚟問：佢有冇令你唔舒服？';
  static const briefPrQ4Emphasis = '唔舒服';

  /// Weekly PR page 3 (i1–i3), at the top of the page.
  static const weeklyPrReversePage = '呢一頁三句講唔好嘅感覺，同意即係有呢種感覺。';
  static const weeklyPrReversePageEmphasis = '唔好';

  /// In-app DJG-ES question 4 (W1–W3 part 1, W8), above the stem.  Plain.
  static const djgQ4 = '跟住三句講你身邊嘅人。';
}

class DirectionCue extends StatelessWidget {
  const DirectionCue({super.key, required this.text, this.emphasis});

  final String text;

  /// The words inside [text] to bold and highlight; null = a plain line.
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: cs.onSurface,
    );
    final e = emphasis;
    final at = e == null ? -1 : text.indexOf(e);
    if (e == null || at < 0) return Text(text, style: base);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: e,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: cs.primary,
            backgroundColor: cs.primary.withValues(alpha: 0.14),
          ),
        ),
        TextSpan(text: text.substring(at + e.length)),
      ]),
      style: base,
    );
  }
}

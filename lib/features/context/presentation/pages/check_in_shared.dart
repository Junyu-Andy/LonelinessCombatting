import 'package:flutter/material.dart';

import '../../../../shared/widgets/equal_button_grid.dart';

/// Five-face mood picker — kept in lock-step with the home hero pad so
/// the onboarding pick, the hero pick and the post-chat "完成" sheet
/// all speak the same language (1=好差 … 5=好好).
enum MoodFace {
  veryLow,
  low,
  neutral,
  good,
  great;

  /// 1..5 numeric value used everywhere — analytics, [MoodRecorder],
  /// the Siu Yan opener.  No second mapping needed.
  int get rank => index + 1;

  /// Same as [rank] — kept for callers that still ask for
  /// `numericScore`.  Removing the alias would churn analytics call
  /// sites for no behaviour change.
  int get numericScore => rank;

  String emoji() => switch (this) {
        MoodFace.veryLow => '😔',
        MoodFace.low => '🙁',
        MoodFace.neutral => '😐',
        MoodFace.good => '🙂',
        MoodFace.great => '😊',
      };

  String label(bool isEn) => switch (this) {
        // 1020f: one set of words everywhere (selector, chart legend,
        // check-in Q1); scores 1–5 unchanged.
        MoodFace.veryLow => isEn ? 'Very unhappy' : '好唔開心',
        MoodFace.low => isEn ? 'Not great' : '唔係幾好',
        MoodFace.neutral => isEn ? 'So-so' : '一般般',
        MoodFace.good => isEn ? 'Fairly good' : '幾好',
        MoodFace.great => isEn ? 'Very happy' : '好開心',
      };
}

/// 1020l §一 (3) — the five faces are one even grid ([EqualButtonGrid]):
/// every button the same width and height, the face and the word centred
/// both ways, the word on one line whenever the screen allows (five in a
/// row on a tablet, three-and-two or two-two-one on a phone, by the text
/// size).  Was a [Wrap] of fixed 92 px boxes, where a long word wrapped in
/// some boxes and not others.  Font sizes unchanged.  Used by the old
/// check-in pages (switch `checkInChatV2Enabled` off), the rule-arm
/// reminiscence page and the old home mood sheet; same in both arms.
class MoodFacePicker extends StatelessWidget {
  /// Null = nothing selected yet.  B14-aligned: measurement surfaces
  /// must not pre-select a midpoint face, so callers may start empty
  /// and require an active pick.
  final MoodFace? value;
  final ValueChanged<MoodFace> onChanged;
  const MoodFacePicker(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return EqualButtonGrid(
      spacing: 8,
      runSpacing: 10,
      children: MoodFace.values.map((face) {
        final selected = face == value;
        return Semantics(
          button: true,
          selected: selected,
          label: face.label(isEn),
          child: InkWell(
            key: ValueKey('mood_face_${face.name}'),
            onTap: () => onChanged(face),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(face.emoji(), style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 4),
                  Text(face.label(isEn),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

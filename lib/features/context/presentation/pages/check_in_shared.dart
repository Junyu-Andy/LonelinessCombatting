import 'package:flutter/material.dart';

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
        MoodFace.veryLow => isEn ? 'Very bad' : '好差',
        MoodFace.low => isEn ? 'Bad' : '差',
        MoodFace.neutral => isEn ? 'So-so' : '麻麻地',
        MoodFace.good => isEn ? 'Good' : '幾好',
        MoodFace.great => isEn ? 'Great' : '好好',
      };
}

class MoodFacePicker extends StatelessWidget {
  final MoodFace value;
  final ValueChanged<MoodFace> onChanged;
  const MoodFacePicker(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: MoodFace.values.map((face) {
        final selected = face == value;
        return Semantics(
          button: true,
          selected: selected,
          label: face.label(isEn),
          child: InkWell(
            onTap: () => onChanged(face),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(vertical: 10),
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
                children: [
                  Text(face.emoji(), style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 4),
                  Text(face.label(isEn),
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

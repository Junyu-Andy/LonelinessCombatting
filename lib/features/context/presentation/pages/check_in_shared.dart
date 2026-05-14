import 'package:flutter/material.dart';

/// Six-face mood picker (spec §M2 Arm B step 1). Used by the rule-based
/// arm, but the affordance is small enough that it's safe to reuse in
/// Arm A as the optional structured tail.
enum MoodFace {
  veryLow,
  low,
  neutral,
  ok,
  good,
  great;

  /// 1..6 numeric value for analytics. Mapped to the 1..5 mood column
  /// used elsewhere via [numericScore].
  int get rank => index + 1;

  /// Compress 6-face → 1..5 so it slots into the existing analytics
  /// schema without breaking the dashboard.
  int get numericScore {
    switch (this) {
      case MoodFace.veryLow:
        return 1;
      case MoodFace.low:
        return 2;
      case MoodFace.neutral:
        return 3;
      case MoodFace.ok:
        return 3;
      case MoodFace.good:
        return 4;
      case MoodFace.great:
        return 5;
    }
  }

  String emoji() => switch (this) {
        MoodFace.veryLow => '😣',
        MoodFace.low => '😔',
        MoodFace.neutral => '😐',
        MoodFace.ok => '🙂',
        MoodFace.good => '😊',
        MoodFace.great => '😄',
      };

  String label(bool isEn) => switch (this) {
        MoodFace.veryLow => isEn ? 'Very low' : '好辛苦',
        MoodFace.low => isEn ? 'Low' : '唔多好',
        MoodFace.neutral => isEn ? 'Neutral' : '一般',
        MoodFace.ok => isEn ? 'OK' : '可以',
        MoodFace.good => isEn ? 'Good' : '幾好',
        MoodFace.great => isEn ? 'Great' : '好開心',
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

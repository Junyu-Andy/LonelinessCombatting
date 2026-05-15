import 'package:flutter/material.dart';

/// P4.3 — dual color + shape encoding for the M9 mood chart.
///
/// Why shape too: ~5% of older adult men have red-green confusion, so
/// the chart can't rely on color alone to distinguish "rough day" from
/// "good day". Each mood level pairs a color with a distinct silhouette
/// rendered at the top of its bar.
///
/// The numeric `level` is the 1–5 mood score from the M2 face picker
/// (MoodFace.numericScore). Level 0 is reserved for "no data".
@immutable
class MoodVisualToken {
  final int level;
  final Color color;
  final IconData shape;
  final String labelEn;
  final String labelZh;
  const MoodVisualToken({
    required this.level,
    required this.color,
    required this.shape,
    required this.labelEn,
    required this.labelZh,
  });
}

class AppMoodEncoding {
  AppMoodEncoding._();

  /// Resolve a token for a numeric mood score. Falls back to the
  /// neutral token when the score is out of range (e.g. zero / null).
  static MoodVisualToken forScore(int score, ColorScheme scheme) {
    final clamped = score.clamp(1, 5);
    switch (clamped) {
      case 1:
        return MoodVisualToken(
          level: 1,
          color: const Color(0xFFD32F2F),
          shape: Icons.cloud_outlined,
          labelEn: 'Tough',
          labelZh: '好辛苦',
        );
      case 2:
        return MoodVisualToken(
          level: 2,
          color: const Color(0xFFF57C00),
          shape: Icons.water_drop_outlined,
          labelEn: 'Down',
          labelZh: '差啲',
        );
      case 3:
        return MoodVisualToken(
          level: 3,
          color: const Color(0xFFFBC02D),
          shape: Icons.circle_outlined,
          labelEn: 'OK',
          labelZh: '一般',
        );
      case 4:
        return MoodVisualToken(
          level: 4,
          color: const Color(0xFF7CB342),
          shape: Icons.eco_outlined,
          labelEn: 'Good',
          labelZh: '好',
        );
      case 5:
      default:
        return MoodVisualToken(
          level: 5,
          color: scheme.primary,
          shape: Icons.wb_sunny_outlined,
          labelEn: 'Great',
          labelZh: '好開心',
        );
    }
  }

  /// Used by the chart legend so the same color/shape pairs render
  /// consistently outside a bar context.
  static List<MoodVisualToken> legend(ColorScheme scheme) => [
        for (var i = 1; i <= 5; i++) forScore(i, scheme),
      ];
}

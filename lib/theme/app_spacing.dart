import 'package:flutter/widgets.dart';

/// P4.2 — Spacing + touch-target tokens for the elderly UX baseline.
///
/// Why constants and not a Provider: spacing doesn't reactively change
/// at runtime (no "comfortable / compact" toggle planned), so a flat
/// constant class is the right shape. Pages that already inline these
/// numbers don't have to migrate immediately — new code should prefer
/// the tokens so the values converge over time.
class AppSpacing {
  AppSpacing._();

  /// Minimum size for any tappable hit target. Used by button themes
  /// and any custom InkWell affordance. Older participants' average
  /// tap accuracy benefits noticeably above 56pt.
  static const double minTouchTarget = 56.0;

  /// Standard list-item / tile height (touch + visual breathing room).
  /// Keep cards / list entries ≥ this so the user doesn't accidentally
  /// hit two stacked items at once.
  static const double listItemHeight = 64.0;

  /// Grid of vertical spacings used inside a page.
  static const double gapTiny = 4.0;
  static const double gapSmall = 8.0;
  static const double itemGap = 12.0;
  static const double gapMedium = 16.0;
  static const double sectionGap = 24.0;
  static const double gapXLarge = 32.0;

  /// Page-edge padding. Horizontal stays at 20 so the largest font
  /// scale doesn't clip; vertical is the more common 16.
  static const double pagePaddingHorizontal = 20.0;
  static const double pagePaddingVertical = 16.0;

  static const EdgeInsets pageEdgeInsets = EdgeInsets.symmetric(
    horizontal: pagePaddingHorizontal,
    vertical: pagePaddingVertical,
  );

  /// Pre-built vertical SizedBoxes for readability at call sites.
  static const SizedBox vTiny = SizedBox(height: gapTiny);
  static const SizedBox vSmall = SizedBox(height: gapSmall);
  static const SizedBox vItem = SizedBox(height: itemGap);
  static const SizedBox vMedium = SizedBox(height: gapMedium);
  static const SizedBox vSection = SizedBox(height: sectionGap);
  static const SizedBox vXLarge = SizedBox(height: gapXLarge);

  /// Pre-built horizontal SizedBoxes.
  static const SizedBox hSmall = SizedBox(width: gapSmall);
  static const SizedBox hItem = SizedBox(width: itemGap);
  static const SizedBox hMedium = SizedBox(width: gapMedium);
}

import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

/// 1020l §二 (2): on an iPad (or any screen whose shorter side is at least
/// [minShortestSide]) the pages are drawn in one column at most
/// [maxContentWidth] wide, centred, with the App's background colour in the
/// side margins.  Inside the column [MediaQuery] reports the column's width,
/// so every page, dialog, bottom sheet, SnackBar and the bottom navigation
/// bar lays out as on a 600-wide device.
///
/// Phones are untouched: below [minShortestSide] (every phone, upright or
/// sideways) or with [enabled] false, the frame adds no layout widget and no
/// [MediaQuery] — only a [KeyedSubtree], which draws nothing.  Its
/// [GlobalKey] keeps the page stack when the frame comes or goes (an iPad
/// split view resized), so the elder is never sent back to the first page.
///
/// Installed once in `MaterialApp.builder` (app.dart), switch
/// `app_config/feature_flags.wideScreenFrameEnabled`.
class WideScreenFrame extends StatefulWidget {
  const WideScreenFrame({
    super.key,
    required this.enabled,
    required this.child,
  });

  /// Widest the content may be, in logical pixels.
  static const double maxContentWidth = 600;

  /// Material's tablet breakpoint: a phone's shorter side is below this, so
  /// a phone turned sideways keeps its full width.
  static const double minShortestSide = 600;

  /// Key of the centred column (tests).
  static const Key columnKey = ValueKey('wide_screen_frame_column');

  final bool enabled;
  final Widget child;

  /// Whether a screen of [size] gets the column.
  static bool appliesTo(Size size) =>
      size.shortestSide >= minShortestSide && size.width > maxContentWidth;

  /// [outer] as seen from inside a column of [maxContentWidth] centred on
  /// it: the width, and the left / right insets less the side margin
  /// (top, bottom and the keyboard are kept).
  static MediaQueryData columnData(MediaQueryData outer) {
    final side = (outer.size.width - maxContentWidth) / 2;
    EdgeInsets inset(EdgeInsets e) => EdgeInsets.fromLTRB(
        math.max(0, e.left - side), e.top, math.max(0, e.right - side),
        e.bottom);
    return outer.copyWith(
      size: Size(maxContentWidth, outer.size.height),
      padding: inset(outer.padding),
      viewPadding: inset(outer.viewPadding),
      viewInsets: inset(outer.viewInsets),
      systemGestureInsets: inset(outer.systemGestureInsets),
      displayFeatures: [
        for (final f in outer.displayFeatures)
          DisplayFeature(
              bounds: f.bounds.shift(Offset(-side, 0)),
              type: f.type,
              state: f.state),
      ],
    );
  }

  @override
  State<WideScreenFrame> createState() => _WideScreenFrameState();
}

class _WideScreenFrameState extends State<WideScreenFrame> {
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'wide_screen_content');

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    final outer = MediaQuery.of(context);
    if (!widget.enabled || !WideScreenFrame.appliesTo(outer.size)) {
      return content;
    }
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          key: WideScreenFrame.columnKey,
          width: WideScreenFrame.maxContentWidth,
          height: double.infinity,
          child: MediaQuery(
            data: WideScreenFrame.columnData(outer),
            child: content,
          ),
        ),
      ),
    );
  }
}

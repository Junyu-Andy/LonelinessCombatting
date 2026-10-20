/// 1020l §一 (3) — a group of answer buttons as one tidy grid.
///
/// Every child gets the same width and the same height, so no button has a
/// one-line label next to a two-line one.  The number of columns is the
/// largest "even" count — n, ⌈n/2⌉, ⌈n/3⌉, … 1 (six buttons: 6, 3, 2, 1) —
/// at which every child's label still fits on one line; only when even one
/// column is too narrow do labels wrap, and then every button is as tall
/// as the tallest.  A last row with fewer buttons is centred.
///
/// Used by the answer buttons of the 小欣 chat window (Q1, Q2, Q3, Q5;
/// switch `checkInChatV2Enabled`).  Nothing else uses it.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class EqualButtonGrid extends MultiChildRenderObjectWidget {
  const EqualButtonGrid({
    super.key,
    required super.children,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final double spacing;
  final double runSpacing;

  /// The column counts tried for [n] buttons, most first.
  static List<int> columnChoices(int n) {
    final out = <int>[];
    for (var rows = 1; rows <= n; rows++) {
      final c = (n / rows).ceil();
      if (out.isEmpty || out.last != c) out.add(c);
    }
    return out;
  }

  @override
  RenderEqualButtonGrid createRenderObject(BuildContext context) =>
      RenderEqualButtonGrid(spacing: spacing, runSpacing: runSpacing);

  @override
  void updateRenderObject(
      BuildContext context, RenderEqualButtonGrid renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class EqualButtonGridParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualButtonGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EqualButtonGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, EqualButtonGridParentData> {
  RenderEqualButtonGrid({required double spacing, required double runSpacing})
      : _spacing = spacing,
        _runSpacing = runSpacing;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  /// The columns chosen at the last layout (tests).
  int get columns => _columns;
  int _columns = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EqualButtonGridParentData) {
      child.parentData = EqualButtonGridParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  /// The widest one-line child.
  double _natural(List<RenderBox> kids) => kids.fold(
      0.0, (m, c) => math.max(m, c.getMaxIntrinsicWidth(double.infinity)));

  double _itemWidth(double width, int cols) =>
      math.max(0.0, (width - spacing * (cols - 1)) / cols);

  int _columnsFor(List<RenderBox> kids, double width) {
    final n = kids.length;
    if (n == 0) return 0;
    if (!width.isFinite) return n;
    final natural = _natural(kids);
    for (final c in EqualButtonGrid.columnChoices(n)) {
      // Half a pixel of slack for rounding.
      if (_itemWidth(width, c) + 0.5 >= natural) return c;
    }
    return 1;
  }

  ({int cols, double width, double itemWidth}) _shape(
      List<RenderBox> kids, double maxWidth) {
    final cols = _columnsFor(kids, maxWidth);
    final itemWidth = maxWidth.isFinite
        ? _itemWidth(maxWidth, cols)
        : _natural(kids);
    final width = maxWidth.isFinite
        ? maxWidth
        : itemWidth * cols + spacing * (cols - 1);
    return (cols: cols, width: width, itemWidth: itemWidth);
  }

  double _heightFor(int n, int cols, double itemHeight) {
    if (n == 0) return 0;
    final rows = (n / cols).ceil();
    return rows * itemHeight + (rows - 1) * runSpacing;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _kids.fold(
      0.0, (m, c) => math.max(m, c.getMinIntrinsicWidth(double.infinity)));

  @override
  double computeMaxIntrinsicWidth(double height) {
    final kids = _kids;
    if (kids.isEmpty) return 0;
    return _natural(kids) * kids.length + spacing * (kids.length - 1);
  }

  double _intrinsicHeight(double width) {
    final kids = _kids;
    if (kids.isEmpty) return 0;
    final s = _shape(kids, width);
    final h = kids.fold(
        0.0, (m, c) => math.max(m, c.getMaxIntrinsicHeight(s.itemWidth)));
    return _heightFor(kids.length, s.cols, h);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final kids = _kids;
    if (kids.isEmpty) return constraints.smallest;
    final s = _shape(kids, constraints.maxWidth);
    final h = kids.fold(
        0.0,
        (m, c) => math.max(
            m,
            c
                .getDryLayout(BoxConstraints(
                    minWidth: s.itemWidth, maxWidth: s.itemWidth))
                .height));
    return constraints
        .constrain(Size(s.width, _heightFor(kids.length, s.cols, h)));
  }

  @override
  void performLayout() {
    final kids = _kids;
    if (kids.isEmpty) {
      _columns = 0;
      size = constraints.smallest;
      return;
    }
    final s = _shape(kids, constraints.maxWidth);
    _columns = s.cols;
    // Pass 1: each child's own height at the shared width.
    var itemHeight = 0.0;
    for (final c in kids) {
      c.layout(BoxConstraints(minWidth: s.itemWidth, maxWidth: s.itemWidth),
          parentUsesSize: true);
      itemHeight = math.max(itemHeight, c.size.height);
    }
    // Pass 2: everyone the same size.
    final tight =
        BoxConstraints.tightFor(width: s.itemWidth, height: itemHeight);
    for (var i = 0; i < kids.length; i++) {
      final c = kids[i];
      c.layout(tight);
      final row = i ~/ s.cols;
      final inRow = math.min(s.cols, kids.length - row * s.cols);
      final rowWidth = inRow * s.itemWidth + (inRow - 1) * spacing;
      final left = (s.width - rowWidth) / 2;
      final col = i - row * s.cols;
      (c.parentData! as EqualButtonGridParentData).offset = Offset(
          left + col * (s.itemWidth + spacing),
          row * (itemHeight + runSpacing));
    }
    size = constraints.constrain(
        Size(s.width, _heightFor(kids.length, s.cols, itemHeight)));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

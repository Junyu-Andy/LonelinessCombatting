/// T24 — 「第 N 部分，共 M 部分」 at the top of every part of the weekly
/// bundle (the same pattern T17b uses in the day-7 flow; kept separate so
/// the Phase B flow does not depend on ADA code).
library;

import 'package:flutter/material.dart';

/// Position of a part inside a flow: (n, m).
typedef WeeklyPartPosition = (int, int);

class WeeklyPartHeader extends StatelessWidget {
  const WeeklyPartHeader({super.key, required this.part});

  final WeeklyPartPosition part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        '第 ${part.$1} 部分，共 ${part.$2} 部分',
        key: const ValueKey('weekly_part'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}

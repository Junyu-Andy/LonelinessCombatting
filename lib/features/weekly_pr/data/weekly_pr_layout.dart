/// Weekly PR pages — which item goes on which page.
///
/// Before 1020k (and with `scaleDirectionCuesEnabled` off): all twelve
/// items shuffled, four per page.
///
/// 1020k (decisions-log 10/20 items 77–79), switch on: the nine positive
/// items (u1–u3, v1–v3, c1–c3) shuffled over pages 1 and 2 (five, then
/// four); the three reverse items (i1–i3) always on page 3, shuffled among
/// themselves, under the line `DirectionCues.weeklyPrReversePage`.  Items,
/// options, storage and scoring unchanged; the record gets `itemOrder`.
library;

import 'dart:math';

import 'weekly_pr_response.dart';

typedef WeeklyPrItem = ({String id, String text});

class WeeklyPrLayout {
  WeeklyPrLayout._();

  static const reverseIds = {'i1', 'i2', 'i3'};

  /// Old layout: items per page.
  static const perPage = 4;

  /// 1020k layout: positive items on page 1 (page 2 takes the rest).
  static const firstPagePositives = 5;

  /// The items, page by page.  [reverseLast] = the 1020k layout.
  static List<List<WeeklyPrItem>> pages({
    required bool reverseLast,
    Random? random,
  }) {
    final rng = random ?? Random();
    if (!reverseLast) {
      final all = List<WeeklyPrItem>.from(WeeklyPrItems.items)..shuffle(rng);
      return [
        for (var i = 0; i < all.length; i += perPage)
          all.sublist(i, min(i + perPage, all.length)),
      ];
    }
    final positive = [
      for (final it in WeeklyPrItems.items)
        if (!reverseIds.contains(it.id)) it,
    ]..shuffle(rng);
    final reverse = [
      for (final it in WeeklyPrItems.items)
        if (reverseIds.contains(it.id)) it,
    ]..shuffle(rng);
    return [
      positive.sublist(0, firstPagePositives),
      positive.sublist(firstPagePositives),
      reverse,
    ];
  }

  /// True when [page] is the reverse-item page of the 1020k layout.
  static bool isReversePage(List<WeeklyPrItem> page) =>
      page.isNotEmpty && page.every((it) => reverseIds.contains(it.id));

  /// Item ids in display order (page 1 top to page 3 bottom).
  static List<String> order(List<List<WeeklyPrItem>> pages) =>
      [for (final p in pages) for (final it in p) it.id];
}

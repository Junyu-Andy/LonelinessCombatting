/// 1020c — 「小讀本」 units: bundled HTML readers shown in 讀少少.
///
/// Files (1020c §1(2)), all packaged with the App, never downloaded:
///   `assets/readers/manifest.json` `[{"id", "titleZh", "minutes", "order",
///                                  "part", "partTitleZh", "icon"}]`
///   `assets/readers/<id>.html`     what the reader shows (WebView)
///   `assets/readers/<id>.txt`      plain text for the 「?」 Q&A (Hybrid)
///   `assets/readers/<id>.explain.json`  packaged, not read by the App yet
///                                  (the per-card explanations, not built)
/// tool/check_reader_html.js checks them in CI; tool/add_readers.sh puts
/// a delivered zip in (docs/release/readers-file-format.md).  1021: the 14
/// units of readers-1021.zip are committed.
///
/// The placeholder test unit (content says 測試) exists only in a build
/// made with `--dart-define=READER_TEST_UNIT=true`: every reference to it
/// sits behind the compile-time constant [kReaderTestUnit], so a normal
/// build drops it entirely (AOT tree shaking).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/usage/usage_event_recorder.dart' show kReaderIdPattern;
import 'reader_test_unit.dart';

/// Compile-time switch for the placeholder test unit (device testing per
/// 1020c §4(1)).  Never set in a participant build.
const bool kReaderTestUnit = bool.fromEnvironment('READER_TEST_UNIT');

/// One entry of `manifest.json`.
@immutable
class ReaderUnit {
  const ReaderUnit({
    required this.id,
    required this.titleZh,
    required this.minutes,
    required this.order,
    this.part,
    this.partTitleZh,
    this.icon,
  });

  /// File stem and the id in usage events ([kReaderIdPattern]).
  final String id;
  final String titleZh;

  /// About how many minutes it takes to read.
  final int minutes;

  /// Position in the 小讀本 list (ascending).
  final int order;

  /// 1021 T-R1: which part of the list (1, 2, 3 …) and its heading
  /// (「認識孤單」; the list shows 「第一部分：認識孤單」).  Null for a unit
  /// written before parts existed — listed first, without a heading.
  final int? part;
  final String? partTitleZh;

  /// 1021 T-R1 (2): a Material Icons name (`help_outline`); the list maps
  /// it with `readerIconFor`, unknown or null → the default book.
  final String? icon;

  /// One manifest entry, or null when it is not well-formed (wrong id
  /// shape, empty title, non-positive minutes, non-integer order).  The
  /// 1021 fields are optional: a malformed `part` / `partTitleZh` / `icon`
  /// is dropped (the unit is still listed, without a part or with the
  /// default icon).
  static ReaderUnit? tryParse(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final title = entry['titleZh'];
    final minutes = entry['minutes'];
    final order = entry['order'];
    if (id is! String || !kReaderIdPattern.hasMatch(id)) return null;
    if (title is! String || title.trim().isEmpty) return null;
    if (minutes is! int || minutes <= 0) return null;
    if (order is! int) return null;
    final part = entry['part'];
    final partTitle = entry['partTitleZh'];
    final icon = entry['icon'];
    final hasPart = part is int && part >= 1;
    return ReaderUnit(
      id: id,
      titleZh: title.trim(),
      minutes: minutes,
      order: order,
      part: hasPart ? part : null,
      partTitleZh: hasPart && partTitle is String && partTitle.trim().isNotEmpty
          ? partTitle.trim()
          : null,
      icon: icon is String && _iconName.hasMatch(icon) ? icon : null,
    );
  }

  static final RegExp _iconName = RegExp(r'^[a-z0-9_]{1,64}$');

  @override
  bool operator ==(Object other) =>
      other is ReaderUnit &&
      other.id == id &&
      other.titleZh == titleZh &&
      other.minutes == minutes &&
      other.order == order &&
      other.part == part &&
      other.partTitleZh == partTitleZh &&
      other.icon == icon;

  @override
  int get hashCode =>
      Object.hash(id, titleZh, minutes, order, part, partTitleZh, icon);
}

/// Parse `manifest.json`.  Malformed JSON → no units; malformed entries
/// and repeated ids are skipped.  Sorted by `order`, then id.
List<ReaderUnit> parseReaderManifest(String json) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final seen = <String>{};
  final units = <ReaderUnit>[];
  for (final e in decoded) {
    final u = ReaderUnit.tryParse(e);
    if (u == null || !seen.add(u.id)) continue;
    units.add(u);
  }
  units.sort((a, b) =>
      a.order != b.order ? a.order.compareTo(b.order) : a.id.compareTo(b.id));
  return units;
}

/// Where the units and their files come from.  [AssetReaderContentSource]
/// in the App; tests pass their own.
abstract class ReaderContentSource {
  const ReaderContentSource();

  /// The packaged units in list order (empty when there are none).
  Future<List<ReaderUnit>> units();

  /// `<id>.html` as written (the reader page adds the CSP, the viewport,
  /// `--fs` and the section script before showing it).
  Future<String> html(String id);

  /// `<id>.txt` — the plain text the 「?」 Q&A (Hybrid) answers from.
  Future<String> text(String id);
}

class AssetReaderContentSource extends ReaderContentSource {
  const AssetReaderContentSource([this._bundle]);

  final AssetBundle? _bundle;

  static const String dir = 'assets/readers';

  AssetBundle get _b => _bundle ?? rootBundle;

  @override
  Future<List<ReaderUnit>> units() async {
    List<ReaderUnit> units;
    try {
      units = parseReaderManifest(await _b.loadString('$dir/manifest.json'));
    } catch (e) {
      if (kDebugMode) debugPrint('[Readers] manifest unreadable: $e');
      units = const [];
    }
    if (kReaderTestUnit) {
      units = [
        readerTestUnit,
        for (final u in units)
          if (u.id != readerTestUnit.id) u,
      ];
    }
    return units;
  }

  @override
  Future<String> html(String id) {
    if (kReaderTestUnit && id == readerTestUnit.id) {
      return Future.value(readerTestUnitHtml);
    }
    return _b.loadString('$dir/$id.html');
  }

  @override
  Future<String> text(String id) {
    if (kReaderTestUnit && id == readerTestUnit.id) {
      return Future.value(readerTestUnitText);
    }
    return _b.loadString('$dir/$id.txt');
  }
}

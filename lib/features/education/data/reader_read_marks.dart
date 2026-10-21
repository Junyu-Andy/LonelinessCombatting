import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/usage/usage_event_recorder.dart' show kReaderIdPattern;

/// 1021 T-R3 — what has been read, kept on this phone only (nothing is
/// uploaded; the research record stays the `reader_section` usage event).
///
/// Per unit: the section ids the page reports as read
/// (`window.peizhuReader.readIds()`: a section counts once the reader
/// leaves it) and how many sections the unit has.  The reader page saves
/// it when the reader leaves (back to 讀少少, or 「讀下一篇」) and on every
/// change; the next time the unit opens the App hands the ids back
/// (`peizhuReader.setRead`), so the page's contents show 「✓ 已讀」.  All
/// sections read = 讀完 (the tick in the 讀少少 list).
///
/// Losing it (new phone, cleared data) only hides the ticks.
@immutable
class ReaderReadState {
  const ReaderReadState({required this.readIds, required this.total});

  static const empty = ReaderReadState(readIds: {}, total: 0);

  final Set<String> readIds;

  /// Sections in the unit (its `data-section` count); 0 = not known yet.
  final int total;

  /// 「讀完」: every section read (1021 T-R3 (3)).
  bool get done => total > 0 && readIds.length >= total;

  @override
  bool operator ==(Object other) =>
      other is ReaderReadState &&
      other.total == total &&
      setEquals(other.readIds, readIds);

  @override
  int get hashCode => Object.hash(total, Object.hashAllUnordered(readIds));

  @override
  String toString() => 'ReaderReadState($readIds / $total)';
}

abstract class ReaderReadMarks {
  const ReaderReadMarks();

  /// Every unit's state (units never opened are absent).
  Future<Map<String, ReaderReadState>> load();

  /// Add [readIds] to what is kept for [unitId] (never removes any) and
  /// record [total].  Ids that are not well-formed are dropped.
  Future<void> save(String unitId,
      {required Set<String> readIds, required int total});
}

/// Merge rule shared by both stores.
ReaderReadState mergeReaderReadState(
    ReaderReadState? old, Set<String> readIds, int total) {
  final ids = {
    ...?old?.readIds,
    for (final id in readIds)
      if (kReaderIdPattern.hasMatch(id)) id,
  };
  return ReaderReadState(
      readIds: ids, total: total > 0 ? total : (old?.total ?? 0));
}

/// `shared_preferences`, key [key]: one JSON object
/// `{"<unit id>": {"read": ["s1", …], "total": 3}}`.  Never throws: an
/// unreadable store means no ticks.
class PrefsReaderReadMarks extends ReaderReadMarks {
  const PrefsReaderReadMarks();

  static const String key = 'readers.readState.v2';

  static Map<String, ReaderReadState> decode(String? raw) {
    if (raw == null) return {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return {};
    }
    if (decoded is! Map) return {};
    final out = <String, ReaderReadState>{};
    decoded.forEach((k, v) {
      if (k is! String || !kReaderIdPattern.hasMatch(k) || v is! Map) return;
      final read = v['read'];
      final total = v['total'];
      out[k] = ReaderReadState(
        readIds: {
          if (read is List)
            for (final r in read)
              if (r is String && kReaderIdPattern.hasMatch(r)) r,
        },
        total: total is int && total > 0 ? total : 0,
      );
    });
    return out;
  }

  static String encode(Map<String, ReaderReadState> states) => jsonEncode({
        for (final e in states.entries)
          e.key: {
            'read': (e.value.readIds.toList()..sort()),
            'total': e.value.total,
          },
      });

  @override
  Future<Map<String, ReaderReadState>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(key));
    } catch (e) {
      if (kDebugMode) debugPrint('[Readers] read marks unreadable: $e');
      return {};
    }
  }

  @override
  Future<void> save(String unitId,
      {required Set<String> readIds, required int total}) async {
    if (!kReaderIdPattern.hasMatch(unitId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = decode(prefs.getString(key));
      final next = mergeReaderReadState(all[unitId], readIds, total);
      if (next == all[unitId]) return;
      all[unitId] = next;
      await prefs.setString(key, encode(all));
    } catch (e) {
      if (kDebugMode) debugPrint('[Readers] read marks not saved: $e');
    }
  }
}

/// Tests and screenshots.
class InMemoryReaderReadMarks extends ReaderReadMarks {
  InMemoryReaderReadMarks([Map<String, ReaderReadState>? initial])
      : states = {...?initial};

  final Map<String, ReaderReadState> states;
  int saves = 0;

  @override
  Future<Map<String, ReaderReadState>> load() async => {...states};

  @override
  Future<void> save(String unitId,
      {required Set<String> readIds, required int total}) async {
    if (!kReaderIdPattern.hasMatch(unitId)) return;
    saves++;
    states[unitId] = mergeReaderReadState(states[unitId], readIds, total);
  }
}

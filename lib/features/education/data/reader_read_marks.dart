import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1020c §2(1) — the 「讀過」 tick in the 小讀本 list.  Set when a reader
/// closes (the same moment as `reader_close`), kept on this phone only;
/// nothing is uploaded.  Losing it (new phone, cleared data) only hides
/// the ticks.
abstract class ReaderReadMarks {
  const ReaderReadMarks();

  Future<Set<String>> load();

  Future<void> markRead(String unitId);
}

/// `shared_preferences`, key [key] (a string list of unit ids).  Never
/// throws: an unreadable store means no ticks.
class PrefsReaderReadMarks extends ReaderReadMarks {
  const PrefsReaderReadMarks();

  static const String key = 'readers.readUnitIds';

  @override
  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(key) ?? const <String>[]).toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[Readers] read marks unreadable: $e');
      return <String>{};
    }
  }

  @override
  Future<void> markRead(String unitId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      if (ids.add(unitId)) {
        await prefs.setStringList(key, ids.toList()..sort());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Readers] read mark not saved: $e');
    }
  }
}

/// Tests and screenshots.
class InMemoryReaderReadMarks extends ReaderReadMarks {
  InMemoryReaderReadMarks([Set<String>? initial]) : ids = {...?initial};

  final Set<String> ids;

  @override
  Future<Set<String>> load() async => {...ids};

  @override
  Future<void> markRead(String unitId) async => ids.add(unitId);
}

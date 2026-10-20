/// 1020 E — where the mood row (`moodRowV2Enabled`) reads and writes.
///
///   - Every pick is one `users/{uid}/daily_mood` row through [MoodRecorder]
///     (unchanged fields: `mood`, `date_iso`, `is_primary` for the first of
///     the day, `supplementary` for the rest, `entry_seq_today`,
///     `prompted_at` / `responded_at` server time, `source_surface`
///     [sourceSurface], `arm`).
///   - Two per-phone day marks in `shared_preferences` (like T46's close
///     hint): the day 遲啲先答 was pressed ([skippedKey]) and the day M7 was
///     used up ([m7DoneKey]).  Nothing else is stored; a failed read falls
///     back to memory for this run.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'mood_recorder.dart';

abstract class MoodRowStore {
  /// `source_surface` of the rows the mood row writes.
  static const String sourceSurface = 'home_mood_row';

  /// Day (YYYY-MM-DD) 遲啲先答 (M2) was pressed.
  static const String skippedKey = 'home.moodRow.skippedDate';

  /// Day M7 was tapped, or replaced by M8.
  static const String m7DoneKey = 'home.moodRow.m7DoneDate';

  /// Today's latest `daily_mood` row, or null.
  Future<MoodEntry?> latestToday(String uid, DateTime now);

  /// One new `daily_mood` row (primary when it is the first of the day).
  Future<void> record({
    required String uid,
    required int mood,
    required String arm,
  });

  Future<String?> readMark(String key);
  Future<void> writeMark(String key, String dateIso);
}

class DefaultMoodRowStore implements MoodRowStore {
  DefaultMoodRowStore({required this.available, MoodRecorder? recorder})
      : _recorder = recorder;

  final bool available;
  MoodRecorder? _recorder;
  MoodRecorder get _mood => _recorder ??= MoodRecorder();

  /// Fallback when shared_preferences cannot be read.
  static final Map<String, String> _memory = {};

  @override
  Future<MoodEntry?> latestToday(String uid, DateTime now) async {
    if (!available) return null;
    try {
      return await _mood
          .latestForDate(uid: uid, dateIso: MoodRecorder.dateIsoFor(now))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> record({
    required String uid,
    required int mood,
    required String arm,
  }) async {
    if (!available) return;
    // Fire-and-forget at the call site: offline, add() completes only on
    // server ack; the SDK queues the write (as the old home pad).
    await _mood.record(
      uid: uid,
      mood: mood,
      arm: arm,
      sourceSurface: MoodRowStore.sourceSurface,
    );
  }

  @override
  Future<String?> readMark(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? _memory[key];
    } catch (_) {
      return _memory[key];
    }
  }

  @override
  Future<void> writeMark(String key, String dateIso) async {
    _memory[key] = dateIso;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, dateIso);
    } catch (_) {}
  }
}

/// Tests and screenshots: nothing leaves memory.
class InMemoryMoodRowStore implements MoodRowStore {
  InMemoryMoodRowStore({List<MoodEntry>? entries})
      : entries = entries ?? <MoodEntry>[];

  /// Every row written (and any seeded), oldest first.
  final List<MoodEntry> entries;
  final Map<String, String> marks = {};

  /// Clock for the rows written (tests).
  DateTime Function() clock = DateTime.now;

  @override
  Future<MoodEntry?> latestToday(String uid, DateTime now) async {
    final today = MoodRecorder.dateIsoFor(now);
    final list = entries.where((e) => e.dateIso == today).toList();
    return list.isEmpty ? null : list.last;
  }

  @override
  Future<void> record({
    required String uid,
    required int mood,
    required String arm,
  }) async {
    final at = clock();
    final today = MoodRecorder.dateIsoFor(at);
    final seq = entries.where((e) => e.dateIso == today).length + 1;
    entries.add(MoodEntry(
      id: 'm${entries.length + 1}',
      mood: mood,
      dateIso: today,
      isPrimary: seq == 1,
      supplementary: seq != 1,
      entrySeqToday: seq,
      respondedAt: at,
      sourceSurface: MoodRowStore.sourceSurface,
      arm: arm,
    ));
  }

  @override
  Future<String?> readMark(String key) async => marks[key];

  @override
  Future<void> writeMark(String key, String dateIso) async =>
      marks[key] = dateIso;
}

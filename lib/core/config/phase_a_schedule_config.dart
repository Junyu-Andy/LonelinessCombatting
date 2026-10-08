/// T17 / T17b (SPEC:C22; decisions 0026, 0030) — Phase A-only schedule:
/// when the ADA (Agent Differentiation Assessment) and the day-7 open
/// questions show, and how the day-7 flow reminds and helps.
///
/// **Phase A only.**  Every key lives in its own Firestore document,
/// `app_config/phaseA_schedule`, so T21 (per-phase config) can move it
/// as one unit.  In a `PHASE_B=true` build nothing here is read for
/// display: [AdaGate] hides both instruments whatever this says.
/// `functions/ada.js` reads the same document for the day-7 push.
///
/// Every switch is OFF until the research team writes it.  A missing
/// document or a failed read keeps the defaults below.
///
/// | Key | Default | Meaning |
/// |---|---|---|
/// | `adaEnabled` | false | Show the ADA (Phase A build only) |
/// | `adaAllowSkip` | true | ADA screens show 跳過; skipped items store `"skipped"` |
/// | `adaTimepoints` | visit1 short day 1; day7 full days 7–9 | List of `{id, form, dayFrom, dayTo}` (docs/spec/instruments/ada.md §2) |
/// | `day7OpenEndedEnabled` | false | Day-7 open questions (part 2 of the day-7 flow) |
/// | `day7OpenEndedDayFrom` / `day7OpenEndedDayTo` | 7 / 9 | Window used only when no `day7` timepoint is configured |
/// | `day7OpenEndedAllowSkip` | true | Open-question screens show 跳過 |
/// | `adaHelpPhone` | "" | Number behind 「唔識填？打俾研究員」; empty = no dialler |
/// | `adaDay7ReminderTimeOptions` | 10:00, 14:00, 17:00, 19:00 | Times offered at the end of visit 1 |
/// | `adaDay7ReminderDefaultTime` | 10:00 | Used when the participant chose none |
/// | `adaDay7ReminderHours` | 24 | Second push this many hours after the first (server) |
/// | `day7FlowMinutes` | none | Estimated minutes shown on the day-7 intro; none = placeholder |
///
/// Enrolment day: day 1 = the calendar day the account was created
/// (`enrolment_day.dart`).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// ada.md §2: short = Parts B + D (visit 1); full = A + B + C + D (day 7).
enum AdaForm {
  short('short'),
  full('full');

  const AdaForm(this.code);
  final String code;

  /// Part A (usage over the past 7 days) — full form only.
  bool get hasUsage => this == AdaForm.full;

  /// Part C (who would you go to first) — full form only.
  bool get hasScenarios => this == AdaForm.full;

  static AdaForm parse(Object? v, {AdaForm fallback = AdaForm.short}) {
    for (final f in values) {
      if (f.code == v) return f;
    }
    return fallback;
  }
}

/// Timepoint ids with a fixed meaning (ada.md §2).
const String kVisit1TimepointId = 'visit1';
const String kDay7TimepointId = 'day7';

/// One ADA administration: an id stored with the answers, the form, and
/// the enrolment days (inclusive) during which it is open.
class AdaTimepoint {
  const AdaTimepoint({
    required this.id,
    required this.form,
    required this.dayFrom,
    required this.dayTo,
  });

  /// Stored as `timepoint` and used as the document id.
  final String id;
  final AdaForm form;
  final int dayFrom;
  final int dayTo;

  bool containsDay(int day) => day >= dayFrom && day <= dayTo;

  static AdaTimepoint? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final from = raw['dayFrom'];
    final to = raw['dayTo'];
    if (id is! String || id.isEmpty || from is! num || to is! num) {
      return null;
    }
    // Document ids may not contain '/'.
    if (id.contains('/')) return null;
    return AdaTimepoint(
      id: id,
      form: AdaForm.parse(raw['form']),
      dayFrom: from.toInt(),
      dayTo: to.toInt(),
    );
  }
}

class PhaseAScheduleConfig {
  const PhaseAScheduleConfig({
    this.adaEnabled = false,
    this.adaAllowSkip = true,
    this.adaTimepoints = defaultAdaTimepoints,
    this.day7OpenEndedEnabled = false,
    this.day7OpenEndedDayFrom = 7,
    this.day7OpenEndedDayTo = 9,
    this.day7OpenEndedAllowSkip = true,
    this.adaHelpPhone = '',
    this.adaDay7ReminderTimeOptions = defaultReminderTimeOptions,
    this.adaDay7ReminderDefaultTime = defaultReminderTime,
    this.day7FlowMinutes,
  });

  final bool adaEnabled;
  final bool adaAllowSkip;
  final List<AdaTimepoint> adaTimepoints;
  final bool day7OpenEndedEnabled;
  final int day7OpenEndedDayFrom;
  final int day7OpenEndedDayTo;
  final bool day7OpenEndedAllowSkip;

  /// ada.md §6.5 — never hard-coded; empty means the help button tells
  /// the participant a researcher will call instead of dialling.
  final String adaHelpPhone;

  /// "HH:MM" (Hong Kong), on the hour, 08:00–21:00 (the push job runs
  /// hourly in that range).
  final List<String> adaDay7ReminderTimeOptions;
  final String adaDay7ReminderDefaultTime;

  /// Null until the pilot run gives a number (ada.md §6.2).
  final int? day7FlowMinutes;

  /// ada.md §2: visit 1 short (B + D); day 7 full (A + B + C + D), open
  /// days 7–9.  Actual days follow the EA260417 approval — change config,
  /// not code.
  static const defaultAdaTimepoints = [
    AdaTimepoint(
        id: kVisit1TimepointId, form: AdaForm.short, dayFrom: 1, dayTo: 1),
    AdaTimepoint(
        id: kDay7TimepointId, form: AdaForm.full, dayFrom: 7, dayTo: 9),
  ];

  static const defaultReminderTimeOptions = [
    '10:00', '14:00', '17:00', '19:00',
  ];
  static const defaultReminderTime = '10:00';

  /// The first configured timepoint whose window contains [day].
  AdaTimepoint? adaTimepointForDay(int day) {
    for (final t in adaTimepoints) {
      if (t.containsDay(day)) return t;
    }
    return null;
  }

  AdaTimepoint? timepointById(String id) {
    for (final t in adaTimepoints) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The day-7 flow window (ADA + open questions): the `day7` timepoint's
  /// days, or the open-question days when no such timepoint exists.
  (int, int) get day7Window {
    final t = timepointById(kDay7TimepointId);
    return t != null
        ? (t.dayFrom, t.dayTo)
        : (day7OpenEndedDayFrom, day7OpenEndedDayTo);
  }

  bool day7OpenEndedOnDay(int day) {
    final (from, to) = day7Window;
    return day >= from && day <= to;
  }

  static PhaseAScheduleConfig _current = const PhaseAScheduleConfig();

  static PhaseAScheduleConfig get current => _current;

  @visibleForTesting
  static set current(PhaseAScheduleConfig value) => _current = value;

  /// Read-only for clients (`app_config/{doc}` rule).
  static const String remotePath = 'app_config/phaseA_schedule';

  /// Never throws; on any failure the defaults (all off) stay.
  static Future<PhaseAScheduleConfig> load({bool available = true}) async {
    if (!available) return _current;
    try {
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data != null) _current = fromMap(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[PhaseAScheduleConfig] load skipped: $e');
    }
    return _current;
  }

  /// "HH:MM" on the hour between 08:00 and 21:00, else null.  Mirrors
  /// `functions/ada.js` `parseReminderTime`.
  static String? validReminderTime(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^([01]\d|2[0-3]):00$').firstMatch(v);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    return h >= 8 && h <= 21 ? v : null;
  }

  /// Pure parse.  Booleans count only when they are real booleans; a
  /// switch that should be on must be literally `true`.
  static PhaseAScheduleConfig fromMap(Map<String, dynamic> map) {
    const d = PhaseAScheduleConfig();
    bool b(String k, bool dflt) => map[k] is bool ? map[k] as bool : dflt;
    int i(String k, int dflt) => map[k] is num ? (map[k] as num).toInt() : dflt;
    final raw = map['adaTimepoints'];
    final tps = raw is List
        ? raw.map(AdaTimepoint.fromMap).whereType<AdaTimepoint>().toList()
        : d.adaTimepoints;
    final rawOpts = map['adaDay7ReminderTimeOptions'];
    final opts = rawOpts is List
        ? rawOpts.map(validReminderTime).whereType<String>().toList()
        : d.adaDay7ReminderTimeOptions;
    final minutes = map['day7FlowMinutes'];
    return PhaseAScheduleConfig(
      adaEnabled: map['adaEnabled'] == true,
      adaAllowSkip: b('adaAllowSkip', d.adaAllowSkip),
      adaTimepoints: tps,
      day7OpenEndedEnabled: map['day7OpenEndedEnabled'] == true,
      day7OpenEndedDayFrom: i('day7OpenEndedDayFrom', d.day7OpenEndedDayFrom),
      day7OpenEndedDayTo: i('day7OpenEndedDayTo', d.day7OpenEndedDayTo),
      day7OpenEndedAllowSkip:
          b('day7OpenEndedAllowSkip', d.day7OpenEndedAllowSkip),
      adaHelpPhone: map['adaHelpPhone'] is String
          ? (map['adaHelpPhone'] as String).trim()
          : d.adaHelpPhone,
      adaDay7ReminderTimeOptions:
          opts.isEmpty ? d.adaDay7ReminderTimeOptions : opts,
      adaDay7ReminderDefaultTime:
          validReminderTime(map['adaDay7ReminderDefaultTime']) ??
              d.adaDay7ReminderDefaultTime,
      day7FlowMinutes: minutes is num && minutes > 0 ? minutes.toInt() : null,
    );
  }
}

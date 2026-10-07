/// T17 (SPEC:C22, decision 0026) — Phase A-only schedule: when the ADA
/// (Agent Differentiation Assessment) and the day-7 open questions show.
///
/// **Phase A only.**  Every key lives in its own Firestore document,
/// `app_config/phaseA_schedule`, so T21 (per-phase config) can move it
/// as one unit.  In a `PHASE_B=true` build nothing here is read for
/// display: [AdaGate] hides both instruments whatever this says.
///
/// Every switch is OFF until the research team writes it.  A missing
/// document or a failed read keeps the defaults below.
///
/// | Key | Default | Meaning |
/// |---|---|---|
/// | `adaEnabled` | false | Show the ADA banner (Phase A build only) |
/// | `adaAllowSkip` | true | ADA screens show 跳過; skipped items store `"skipped"` |
/// | `adaTimepoints` | visit1 short day 1; day7 full days 7–9 | List of `{id, form, dayFrom, dayTo, recallWindowZh, recallWindowEn}` |
/// | `day7OpenEndedEnabled` | false | Show the day-7 open questions |
/// | `day7OpenEndedDayFrom` / `day7OpenEndedDayTo` | 7 / 9 | Enrolment days the open questions show |
/// | `day7OpenEndedAllowSkip` | true | Open-question screens show 跳過 |
///
/// Enrolment day: day 1 = the calendar day the account was created
/// (`enrolment_day.dart`).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Short = Parts A + B + D; full = A + B + C + D.
enum AdaForm {
  short('short'),
  full('full');

  const AdaForm(this.code);
  final String code;

  static AdaForm parse(Object? v, {AdaForm fallback = AdaForm.short}) {
    for (final f in values) {
      if (f.code == v) return f;
    }
    return fallback;
  }
}

/// One ADA administration: an id stored with the answers, the form, and
/// the enrolment days (inclusive) during which the banner shows.
class AdaTimepoint {
  const AdaTimepoint({
    required this.id,
    required this.form,
    required this.dayFrom,
    required this.dayTo,
    this.recallWindowZh = defaultRecallWindowZh,
    this.recallWindowEn = defaultRecallWindowEn,
  });

  /// Stored as `timepoint` and used as the document id.
  final String id;
  final AdaForm form;
  final int dayFrom;
  final int dayTo;

  /// Recall window shown in Part A's question (v1.3 wording by default;
  /// the new Phase A window is the research team's to give).
  final String recallWindowZh;
  final String recallWindowEn;

  static const defaultRecallWindowZh = '喺過去兩個星期，正常一個禮拜入面';
  static const defaultRecallWindowEn =
      'In a typical week over the past 2 weeks';

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
      recallWindowZh: raw['recallWindowZh'] is String
          ? raw['recallWindowZh'] as String
          : defaultRecallWindowZh,
      recallWindowEn: raw['recallWindowEn'] is String
          ? raw['recallWindowEn'] as String
          : defaultRecallWindowEn,
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
  });

  final bool adaEnabled;
  final bool adaAllowSkip;
  final List<AdaTimepoint> adaTimepoints;
  final bool day7OpenEndedEnabled;
  final int day7OpenEndedDayFrom;
  final int day7OpenEndedDayTo;
  final bool day7OpenEndedAllowSkip;

  /// Placeholder until EA260417 is approved: first visit (day 1) short,
  /// day 7 full.
  static const defaultAdaTimepoints = [
    AdaTimepoint(id: 'visit1', form: AdaForm.short, dayFrom: 1, dayTo: 1),
    AdaTimepoint(id: 'day7', form: AdaForm.full, dayFrom: 7, dayTo: 9),
  ];

  /// The first configured timepoint whose window contains [day].
  AdaTimepoint? adaTimepointForDay(int day) {
    for (final t in adaTimepoints) {
      if (t.containsDay(day)) return t;
    }
    return null;
  }

  bool day7OpenEndedOnDay(int day) =>
      day >= day7OpenEndedDayFrom && day <= day7OpenEndedDayTo;

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
    return PhaseAScheduleConfig(
      adaEnabled: map['adaEnabled'] == true,
      adaAllowSkip: b('adaAllowSkip', d.adaAllowSkip),
      adaTimepoints: tps,
      day7OpenEndedEnabled: map['day7OpenEndedEnabled'] == true,
      day7OpenEndedDayFrom: i('day7OpenEndedDayFrom', d.day7OpenEndedDayFrom),
      day7OpenEndedDayTo: i('day7OpenEndedDayTo', d.day7OpenEndedDayTo),
      day7OpenEndedAllowSkip:
          b('day7OpenEndedAllowSkip', d.day7OpenEndedAllowSkip),
    );
  }
}

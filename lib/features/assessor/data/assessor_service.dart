/// T30 (registry C19 / C20) — the W4 outcome assessor's backend: the due
/// list and the paper entry, through two role-checked Cloud Functions
/// (`assessorDueList`, `submitOutcomeEntry`, functions/assessor.js).
///
/// The App never reads Firestore for this view — `firestore.rules` lets a
/// `blinded` account read nothing — so the only data that can reach the
/// assessor is what the server puts in these two replies: research ID,
/// W4 window, study day, entered / not entered, out-of-window.  No arm,
/// group code, Brief PR, Weekly PR, usage, chat, safety event or sequence,
/// and never a score.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../assessment/data/djg_w2.dart';

/// The Auth custom claim of the independent outcome assessors (Keran,
/// Mingyan Wang; tool/provision_researcher.js `--role=blinded`).
const assessorRole = 'blinded';

bool isAssessorClaims(Map<String, dynamic>? claims) =>
    claims?['role'] == assessorRole;

/// One row of the W4 due list.
class DueRow {
  final String researchId;
  final String windowStartDate;
  final String windowEndDate;
  final int studyDay;

  /// `before` | `open` | `after` (today vs the window).
  final String windowState;

  /// Instrument id → entry summary (assessment date, out-of-window).
  final Map<String, EnteredSummary> entered;

  const DueRow({
    required this.researchId,
    required this.windowStartDate,
    required this.windowEndDate,
    required this.studyDay,
    required this.windowState,
    required this.entered,
  });

  bool get isOpen => windowState == 'open';
  bool isEntered(String instrument) => entered.containsKey(instrument);

  factory DueRow.fromMap(Map<String, dynamic> m) {
    final entered = <String, EnteredSummary>{};
    final raw = m['entered'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is Map) {
          entered[k] = EnteredSummary(
            assessmentDate: v['assessmentDate'] as String?,
            outOfWindow: v['outOfWindow'] == true,
          );
        }
      });
    }
    return DueRow(
      researchId: m['researchId'] as String? ?? '',
      windowStartDate: m['windowStartDate'] as String? ?? '',
      windowEndDate: m['windowEndDate'] as String? ?? '',
      studyDay: (m['studyDay'] as num?)?.toInt() ?? 0,
      windowState: m['windowState'] as String? ?? 'before',
      entered: entered,
    );
  }
}

class EnteredSummary {
  final String? assessmentDate;
  final bool outOfWindow;
  const EnteredSummary({this.assessmentDate, required this.outOfWindow});
}

class DueList {
  final String today;
  final String timepoint;
  final List<DueRow> rows;
  const DueList(
      {required this.today, required this.timepoint, required this.rows});

  factory DueList.fromMap(Map<String, dynamic> m) => DueList(
        today: m['today'] as String? ?? '',
        timepoint: m['timepoint'] as String? ?? 'W4',
        rows: ((m['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => DueRow.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

/// What the assessor submits.  Answers are the raw stored values
/// (DJG-ES: yes / mostly / no / skipped).
class OutcomeEntryInput {
  final String researchId;
  final String instrument;
  final String timepoint;
  final String assessmentDate;

  /// `in_person` | `phone` | `video`.
  final String mode;
  final Map<String, dynamic> answers;

  const OutcomeEntryInput({
    required this.researchId,
    required this.instrument,
    required this.timepoint,
    required this.assessmentDate,
    required this.mode,
    required this.answers,
  });

  List<String> get missingItems => answers.entries
      .where((e) => e.value == DjgW2Items.skipped)
      .map((e) => e.key)
      .toList();

  Map<String, dynamic> toMap() => {
        'researchId': researchId,
        'instrument': instrument,
        'timepoint': timepoint,
        'assessmentDate': assessmentDate,
        'mode': mode,
        'answers': answers,
        'confirmed': true,
      };
}

class OutcomeEntryResult {
  final bool outOfWindow;
  final List<String> missingItems;
  const OutcomeEntryResult(
      {required this.outOfWindow, required this.missingItems});

  factory OutcomeEntryResult.fromMap(Map<String, dynamic> m) =>
      OutcomeEntryResult(
        outOfWindow: m['outOfWindow'] == true,
        missingItems: ((m['missingItems'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AssessorError implements Exception {
  final String code;
  const AssessorError(this.code);
  @override
  String toString() => 'AssessorError($code)';
}

/// Injectable backend (tests use a fake).
abstract class AssessorBackend {
  Future<DueList> dueList();
  Future<OutcomeEntryResult> submit(OutcomeEntryInput input);
}

class CloudFunctionsAssessorBackend implements AssessorBackend {
  CloudFunctionsAssessorBackend({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-east2');

  final FirebaseFunctions _functions;

  @override
  Future<DueList> dueList() async {
    try {
      final r = await _functions.httpsCallable('assessorDueList').call();
      return DueList.fromMap(Map<String, dynamic>.from(r.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw AssessorError(e.message ?? e.code);
    }
  }

  @override
  Future<OutcomeEntryResult> submit(OutcomeEntryInput input) async {
    try {
      final r = await _functions
          .httpsCallable('submitOutcomeEntry')
          .call(input.toMap());
      return OutcomeEntryResult.fromMap(
          Map<String, dynamic>.from(r.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw AssessorError(e.message ?? e.code);
    }
  }
}

/// Server error code → what the assessor should do (researcher-facing).
String assessorErrorText(String code) => switch (code) {
      'disabled' => '評估員視圖未開（app_config/feature_flags.assessorViewEnabled）。請聯絡負責人。',
      'not_blinded' => '呢個帳號冇評估員權限。',
      'unknown_research_id' => '搵唔到呢個研究編號。',
      'not_phase_b' => '呢個編號唔係 Phase B 或試跑參加者。',
      'already_entered' => '呢位參加者嘅 W4 已經錄入過。要更正請聯絡負責人（tool/correct_outcome_entry.js）。',
      'invalid_assessment_date' => '施測日期唔啱（唔可以係將來）。',
      'invalid_answers' => '有題目嘅答案唔啱，請檢查。',
      _ => '操作失敗（$code）。請再試，或者聯絡負責人。',
    };

/// T39 (registry C19 / C20) — the operations dashboard's backend: three
/// role-checked Cloud Functions (`opsDashboardPeople`, `opsDashboardPerson`,
/// `opsDashboardCsv`, functions/ops_dashboard.js) behind the remote switch
/// `app_config/feature_flags.opsDashboardEnabled`.
///
/// The App reads no Firestore for this view: everything comes from the
/// server replies, which hold process data only (usage, valid sessions,
/// Brief PR, weekly-questionnaire status, mood days, memory counts, voice,
/// safety counts) and never an outcome value.  `blinded` accounts get
/// `not_unblinded` from the server and no entry in the App.
library;

import 'package:cloud_functions/cloud_functions.dart';

/// Companion ids as the sessions log writes them.
const opsCompanions = ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'];

String companionLabel(String id) => switch (id) {
      'siu_yan' => '小欣',
      'ah_jan_ah_bak' => '阿珍／阿伯',
      'tung_tung' => '通通',
      _ => id,
    };

String sessionTypeLabel(String? t) => switch (t) {
      'free_chat' => '自由傾偈',
      'check_in' => '簽到',
      'reminiscence' => '回憶',
      _ => '—',
    };

/// Follow-up stage text (1014d 第 2 页第 4 项).
String stageLabel(String stage) => switch (stage) {
      'whatsapp' => 'WhatsApp',
      'phone' => '電話',
      'follow_up_period' => '隨訪期，只記錄',
      _ => '無',
    };

String weeklyCellLabel(String v) => switch (v) {
      'done' => '已填',
      'skipped' => '跳過',
      'open' => '窗口中',
      'missed' => '過期未填',
      'not_yet' => '未到',
      'not_built' => '未做（T35）',
      _ => v,
    };

String armLabelShort(String? arm) => switch (arm) {
      'A' => 'A 組（Hybrid）',
      'B' => 'B 組（規則組）',
      _ => '—',
    };

String periodLabelShort(String? p) => switch (p) {
      'B' => 'Phase B',
      'PILOT' => '試跑',
      _ => p ?? '—',
    };

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

Map<String, int> _intMap(dynamic v) {
  final out = <String, int>{};
  if (v is Map) {
    v.forEach((k, val) => out['$k'] = _int(val));
  }
  return out;
}

/// One line of the per-person table.
class OpsPerson {
  final String researchId;
  final String? studyPeriod;
  final String? arm;
  final String w0Date;
  final int studyDay;
  final DateTime? lastUseAt;
  final bool openedToday;
  final int consecutiveUnopenedDays;
  final String stage;

  /// No T40 usage events at all: "opened" comes from the session log
  /// (旧构建口径) and foreground minutes are unavailable.
  final bool legacyBasis;
  final int validTotal;
  final Map<String, int> validByCompanion;
  final Map<String, int> validByType;
  final Map<String, int> briefPr;
  final Map<String, String> weekly;
  final int moodDays;

  /// null = rule arm (不適用).
  final Map<String, int>? memory;
  final Map<String, int> voice;
  final Map<String, int> safety;
  /// 1020d §6 (2)(d): 小篇章 still flagged after the check, and failed.
  final Map<String, int> chapters;
  final String w8Status;
  final String debriefStatus;

  const OpsPerson({
    required this.researchId,
    required this.studyPeriod,
    required this.arm,
    required this.w0Date,
    required this.studyDay,
    required this.lastUseAt,
    required this.openedToday,
    required this.consecutiveUnopenedDays,
    required this.stage,
    required this.legacyBasis,
    required this.validTotal,
    required this.validByCompanion,
    required this.validByType,
    required this.briefPr,
    required this.weekly,
    required this.moodDays,
    required this.memory,
    required this.voice,
    required this.safety,
    this.chapters = const {},
    required this.w8Status,
    required this.debriefStatus,
  });

  factory OpsPerson.fromMap(Map<String, dynamic> m) {
    final vs = (m['validSessions'] as Map?) ?? const {};
    final weekly = <String, String>{};
    ((m['weekly'] as Map?) ?? const {}).forEach((k, v) => weekly['$k'] = '$v');
    return OpsPerson(
      researchId: m['researchId'] as String? ?? '',
      studyPeriod: m['studyPeriod'] as String?,
      arm: m['arm'] as String?,
      w0Date: m['w0Date'] as String? ?? '',
      studyDay: _int(m['studyDay']),
      lastUseAt: m['lastUseAt'] is String
          ? DateTime.tryParse(m['lastUseAt'] as String)
          : null,
      openedToday: m['openedToday'] == true,
      consecutiveUnopenedDays: _int(m['consecutiveUnopenedDays']),
      stage: m['stage'] as String? ?? 'none',
      legacyBasis: m['legacyBasis'] == true,
      validTotal: _int(vs['total']),
      validByCompanion: _intMap(vs['byCompanion']),
      validByType: _intMap(vs['byType']),
      briefPr: _intMap(m['briefPr']),
      weekly: weekly,
      moodDays: _int(m['moodDays']),
      memory: m['memory'] == null ? null : _intMap(m['memory']),
      voice: _intMap(m['voice']),
      safety: _intMap(m['safety']),
      chapters: _intMap(m['chapters']),
      w8Status: m['w8Status'] as String? ?? 'not_built',
      debriefStatus: m['debriefStatus'] as String? ?? 'not_built',
    );
  }

  /// "3 天没用" filter (1014c page 2): three or more days without opening.
  bool get unusedThreeDays => consecutiveUnopenedDays >= 3;
}

/// One day of one person (1014d 第 2 页第 3 项).
class OpsDay {
  final String dayKey;
  final int studyDay;
  final String basis; // usage | legacy
  final bool opened;
  final String? firstOpenAt;
  final int? foregroundMinutes; // null = 不可用 (legacy)
  final Map<String, int> validSessions;
  final int briefPrInvited;
  final int briefPrCompleted;

  const OpsDay({
    required this.dayKey,
    required this.studyDay,
    required this.basis,
    required this.opened,
    required this.firstOpenAt,
    required this.foregroundMinutes,
    required this.validSessions,
    required this.briefPrInvited,
    required this.briefPrCompleted,
  });

  factory OpsDay.fromMap(Map<String, dynamic> m) => OpsDay(
        dayKey: m['dayKey'] as String? ?? '',
        studyDay: _int(m['studyDay']),
        basis: m['basis'] as String? ?? 'usage',
        opened: m['opened'] == true,
        firstOpenAt: m['firstOpenAt'] as String?,
        foregroundMinutes: m['foregroundMinutes'] == null
            ? null
            : _int(m['foregroundMinutes']),
        validSessions: _intMap(m['validSessions']),
        briefPrInvited: _int(m['briefPrInvited']),
        briefPrCompleted: _int(m['briefPrCompleted']),
      );
}

class OpsSession {
  final DateTime? startedAt;
  final String? agentId;
  final String? sessionType;
  final int? userMessageCount;
  final int? durationMinutes;
  final String? endReason;
  final bool isValid;
  final String? briefPrStatus;

  const OpsSession({
    required this.startedAt,
    required this.agentId,
    required this.sessionType,
    required this.userMessageCount,
    required this.durationMinutes,
    required this.endReason,
    required this.isValid,
    required this.briefPrStatus,
  });

  factory OpsSession.fromMap(Map<String, dynamic> m) => OpsSession(
        startedAt: m['startedAt'] is String
            ? DateTime.tryParse(m['startedAt'] as String)
            : null,
        agentId: m['agentId'] as String?,
        sessionType: m['sessionType'] as String?,
        userMessageCount: (m['userMessageCount'] as num?)?.toInt(),
        durationMinutes: (m['durationMinutes'] as num?)?.toInt(),
        endReason: m['endReason'] as String?,
        isValid: m['isValid'] == true,
        briefPrStatus: m['briefPrStatus'] as String?,
      );
}

/// Page 1 item 7: today's follow-up list (no arm).
class OpsDue {
  final String researchId;
  final String? studyPeriod;
  final int consecutiveUnopenedDays;
  final String stage;
  const OpsDue({
    required this.researchId,
    required this.studyPeriod,
    required this.consecutiveUnopenedDays,
    required this.stage,
  });

  factory OpsDue.fromMap(Map<String, dynamic> m) => OpsDue(
        researchId: m['researchId'] as String? ?? '',
        studyPeriod: m['studyPeriod'] as String?,
        consecutiveUnopenedDays: _int(m['consecutiveUnopenedDays']),
        stage: m['stage'] as String? ?? 'none',
      );
}

class OpsPeople {
  final String today;
  final List<OpsPerson> people;
  final List<OpsDue> dueList;
  const OpsPeople(
      {required this.today, required this.people, required this.dueList});

  factory OpsPeople.fromMap(Map<String, dynamic> m) => OpsPeople(
        today: m['today'] as String? ?? '',
        people: ((m['people'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => OpsPerson.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
        dueList: ((m['dueList'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => OpsDue.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

class OpsPersonDetail {
  final String today;
  final OpsPerson person;
  final List<OpsDay> days;
  final List<OpsSession> recentSessions;
  const OpsPersonDetail({
    required this.today,
    required this.person,
    required this.days,
    required this.recentSessions,
  });

  factory OpsPersonDetail.fromMap(Map<String, dynamic> m) => OpsPersonDetail(
        today: m['today'] as String? ?? '',
        person: OpsPerson.fromMap(
            Map<String, dynamic>.from((m['person'] as Map?) ?? const {})),
        days: ((m['days'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => OpsDay.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
        recentSessions: ((m['recentSessions'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => OpsSession.fromMap(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

class OpsCsv {
  final String filename;
  final String csv;
  final int rows;
  const OpsCsv({required this.filename, required this.csv, required this.rows});

  factory OpsCsv.fromMap(Map<String, dynamic> m) => OpsCsv(
        filename: m['filename'] as String? ?? 'ops_daily.csv',
        csv: m['csv'] as String? ?? '',
        rows: _int(m['rows']),
      );
}

class OpsError implements Exception {
  final String code;
  const OpsError(this.code);
  @override
  String toString() => 'OpsError($code)';
}

/// Injectable backend (tests use a fake).
abstract class OpsBackend {
  Future<OpsPeople> people();
  Future<OpsPersonDetail> person(String researchId);
  Future<OpsCsv> csv({String? researchId});
}

class CloudFunctionsOpsBackend implements OpsBackend {
  CloudFunctionsOpsBackend({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-east2');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(String name,
      [Map<String, dynamic>? data]) async {
    try {
      final r = await _functions
          .httpsCallable(name,
              options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call(data);
      return Map<String, dynamic>.from(r.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw OpsError(e.message ?? e.code);
    }
  }

  @override
  Future<OpsPeople> people() async =>
      OpsPeople.fromMap(await _call('opsDashboardPeople'));

  @override
  Future<OpsPersonDetail> person(String researchId) async =>
      OpsPersonDetail.fromMap(
          await _call('opsDashboardPerson', {'researchId': researchId}));

  @override
  Future<OpsCsv> csv({String? researchId}) async => OpsCsv.fromMap(
      await _call('opsDashboardCsv',
          {if (researchId != null) 'researchId': researchId}));
}

/// Server error code → researcher-facing text.
String opsErrorText(String code) => switch (code) {
      'disabled' =>
        '營運看板未開（app_config/feature_flags.opsDashboardEnabled）。請聯絡負責人。',
      'not_unblinded' => '呢個帳號冇權限睇營運看板。',
      'unknown_research_id' => '搵唔到呢個研究編號。',
      'invalid_research_id' => '研究編號格式唔啱。',
      'unauthenticated' => '請先登入。',
      _ => '載入失敗（$code）。請再試一次。',
    };

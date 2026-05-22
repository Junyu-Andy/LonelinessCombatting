/// Weekly PR (Sprint 1 §4) — 12-item 7-point per-agent Likert.
///
/// Stored at `users/{uid}/weekly_pr/{auto-id}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyPrResponse {
  /// ISO week format e.g. '2026-W21'.
  final String weekIso;
  final String agentId;
  final String agentDisplayName;
  final int sessionCountThisWeek;

  /// Item id (u1/u2/u3/v1/v2/v3/c1/c2/c3/i1/i2/i3) → 1–7. Empty when
  /// status = 'skipped' or 'no_referent'.
  final Map<String, int> items;

  /// 'completed' | 'skipped' | 'no_referent'
  final String status;
  final DateTime promptedAt;
  final DateTime respondedAt;
  final String arm;

  const WeeklyPrResponse({
    required this.weekIso,
    required this.agentId,
    required this.agentDisplayName,
    required this.sessionCountThisWeek,
    required this.items,
    required this.status,
    required this.promptedAt,
    required this.respondedAt,
    required this.arm,
  });

  Map<String, dynamic> toFirestore() => {
        'weekIso': weekIso,
        'agentId': agentId,
        'agentDisplayName': agentDisplayName,
        'sessionCountThisWeek': sessionCountThisWeek,
        'items': items,
        'status': status,
        'promptedAt': Timestamp.fromDate(promptedAt),
        'respondedAt': FieldValue.serverTimestamp(),
        'arm': arm,
      };

  /// ISO week label for [date] (defaults to `DateTime.now()`), e.g.
  /// `'2026-W21'`. Uses the ISO 8601 week numbering.
  static String currentWeekIso([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    final wday = d.weekday;
    final weekNum = ((dayOfYear - wday + 10) / 7).floor();
    int year = d.year;
    int adjusted = weekNum;
    if (weekNum < 1) {
      year = d.year - 1;
      adjusted = isoWeeksInYear(year);
    } else if (weekNum > isoWeeksInYear(year)) {
      year = d.year + 1;
      adjusted = 1;
    }
    final w = adjusted.toString().padLeft(2, '0');
    return '$year-W$w';
  }

  static int isoWeeksInYear(int year) {
    int p(int y) => (y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400)) % 7;
    return (p(year) == 4 || p(year - 1) == 3) ? 53 : 52;
  }
}

/// 12 Weekly PR items per Sprint 1 §4.1.
class WeeklyPrItems {
  static const items = <({String id, String text})>[
    (id: 'u1', text: '頭先 $kAgent 都明白我嘅感受。'),
    (id: 'u2', text: '頭先 $kAgent 都明白我嘅想法。'),
    (id: 'u3', text: '頭先 $kAgent 真係聽到我講嘅嘢。'),
    (id: 'v1', text: '頭先 $kAgent 尊重我嘅感受。'),
    (id: 'v2', text: '頭先 $kAgent 認可我講嘅嘢。'),
    (id: 'v3', text: '頭先 $kAgent 冇判斷我。'),
    (id: 'c1', text: '頭先 $kAgent 真心關心我。'),
    (id: 'c2', text: '頭先 $kAgent 為我著想。'),
    (id: 'c3', text: '頭先 $kAgent 嘅回應令我覺得舒服。'),
    (id: 'i1', text: '頭先 $kAgent 嘅回應好似搞錯重點。'),
    (id: 'i2', text: '頭先 $kAgent 好似唔在乎我講嘅嘢。'),
    (id: 'i3', text: '頭先 $kAgent 嘅回應令我覺得唔舒服。'),
  ];

  static const kAgent = '〈AGENT〉';

  /// Replace the agent placeholder with the actual display name.
  static String render(String template, String agentName) =>
      template.replaceAll(kAgent, agentName);
}

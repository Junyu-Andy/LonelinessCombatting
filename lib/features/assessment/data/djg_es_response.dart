/// M-4 — De Jong Gierveld 6-item loneliness scale (DJG-ES) response model
/// (Phase A baseline 2026-09).
///
/// Stored at `users/{uid}/djg_es/{auto-id}` with `timepoint: "week2"`.
///
/// Items follow the published 6-item short form (De Jong Gierveld & Van
/// Tilburg 2006: three emotional-loneliness items, three social-loneliness
/// items; response set 是 / 多少 / 否).  **Wording is a working Cantonese
/// draft** — replace with the Questionnaire v1.3 text once the PI provides
/// it; item ids and scoring stay.
///
/// Scoring (stored raw, computed at analysis): emotional items count 1 for
/// 是 or 多少; social items count 1 for 多少 or 否.  Total 0–6.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class DjgEsItem {
  final String id;

  /// `emotional` | `social`
  final String subscale;
  final String promptZh;
  final String promptEn;

  const DjgEsItem({
    required this.id,
    required this.subscale,
    required this.promptZh,
    required this.promptEn,
  });
}

class DjgEsItems {
  DjgEsItems._();

  static const version = 'djg_es_6_draft_v1-2026-09';

  static const items = <DjgEsItem>[
    DjgEsItem(
      id: 'e1',
      subscale: 'emotional',
      promptZh: '我成日覺得好空虛。',
      promptEn: 'I experience a general sense of emptiness.',
    ),
    DjgEsItem(
      id: 'e2',
      subscale: 'emotional',
      promptZh: '我掛住有人喺身邊。',
      promptEn: 'I miss having people around me.',
    ),
    DjgEsItem(
      id: 'e3',
      subscale: 'emotional',
      promptZh: '我成日覺得被人冷落。',
      promptEn: 'I often feel rejected.',
    ),
    DjgEsItem(
      id: 's1',
      subscale: 'social',
      promptZh: '有困難嗰陣，有好多人我可以靠。',
      promptEn: 'There are plenty of people I can rely on when I have problems.',
    ),
    DjgEsItem(
      id: 's2',
      subscale: 'social',
      promptZh: '有好多人我可以完全信任。',
      promptEn: 'There are many people I can trust completely.',
    ),
    DjgEsItem(
      id: 's3',
      subscale: 'social',
      promptZh: '有好多人同我好親近。',
      promptEn: 'There are enough people I feel close to.',
    ),
  ];

  /// Response codes: 1 = 是 (yes), 2 = 多少 (more or less), 3 = 否 (no).
  static const options = <(int, String, String)>[
    (1, '係', 'Yes'),
    (2, '多少啦', 'More or less'),
    (3, '唔係', 'No'),
  ];

  /// Total loneliness score 0–6 per the published scoring.
  static int score(Map<String, int> answers) {
    var total = 0;
    for (final it in items) {
      final v = answers[it.id];
      if (v == null) continue;
      if (it.subscale == 'emotional' && (v == 1 || v == 2)) total++;
      if (it.subscale == 'social' && (v == 2 || v == 3)) total++;
    }
    return total;
  }
}

class DjgEsResponse {
  final String timepoint;
  final Map<String, int> answers;
  final int score;
  final DateTime answeredAt;

  /// `completed` | `skipped`
  final String status;

  const DjgEsResponse({
    required this.timepoint,
    required this.answers,
    required this.score,
    required this.answeredAt,
    required this.status,
  });

  Map<String, dynamic> toFirestore() => {
        'timepoint': timepoint,
        'itemsVersion': DjgEsItems.version,
        'answers': answers,
        'score': score,
        'status': status,
        'answeredAt': FieldValue.serverTimestamp(),
        'answeredAtLocal': answeredAt.toIso8601String(),
      };
}

/// Perceived Partner Responsiveness measurement (Design Rationale §8,
/// Dev Req §11).
///
/// Two instruments:
///   • [PprBriefItem]   — 2-item per-session brief delivered immediately
///                        after a reminiscence session ("how heard /
///                        how present").
///   • [PprWeeklyItem]  — 12-item weekly scale adapted from Crasta,
///                        Rogge & Reis (2021) for the agent context.
///                        The cognitive-interview pilot will validate
///                        final wording; this is the working draft.
///
/// Both forms write to /users/{uid}/ppr_responses/{auto-id}. Each
/// response carries the agent id so the per-agent PPR analysis can
/// partition cleanly.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class PprBriefItem {
  final String id;
  final String promptZh;
  final String promptEn;

  /// Lower-anchor label.
  final String lowZh;
  final String lowEn;

  /// Upper-anchor label.
  final String highZh;
  final String highEn;

  const PprBriefItem({
    required this.id,
    required this.promptZh,
    required this.promptEn,
    required this.lowZh,
    required this.lowEn,
    required this.highZh,
    required this.highEn,
  });
}

const pprBriefItems = <PprBriefItem>[
  PprBriefItem(
    id: 'how_heard',
    promptZh: '今次傾偈，你覺得幾「被聽到」？',
    promptEn: 'In this session, how heard did you feel?',
    lowZh: '冇',
    lowEn: 'Not at all',
    highZh: '非常',
    highEn: 'Very much',
  ),
  PprBriefItem(
    id: 'how_present',
    promptZh: '個系統喺今次傾偈，感覺幾「投入」？',
    promptEn: 'How present did the system feel in this session?',
    lowZh: '一啲都唔',
    lowEn: 'Not at all',
    highZh: '完全係',
    highEn: 'Completely',
  ),
];

/// 12-item weekly scale. Each item maps to a PPR sub-component
/// (understanding / validation / caring) so per-agent slicing is
/// possible at analysis time.
enum PprComponent { understanding, validation, caring }

class PprWeeklyItem {
  final String id;
  final PprComponent component;
  final String promptZh;
  final String promptEn;
  final bool reversed;

  const PprWeeklyItem({
    required this.id,
    required this.component,
    required this.promptZh,
    required this.promptEn,
    this.reversed = false,
  });
}

const pprWeeklyItems = <PprWeeklyItem>[
  // Understanding
  PprWeeklyItem(
    id: 'u1',
    component: PprComponent.understanding,
    promptZh: '呢個禮拜，{agent} 明白我講緊咩。',
    promptEn: 'This week, {agent} understood what I was saying.',
  ),
  PprWeeklyItem(
    id: 'u2',
    component: PprComponent.understanding,
    promptZh: '我覺得 {agent} 真係知道對我嚟講邊樣重要。',
    promptEn: 'I felt {agent} grasped what mattered to me.',
  ),
  PprWeeklyItem(
    id: 'u3',
    component: PprComponent.understanding,
    promptZh: '我講過嘅嘢，{agent} 記得返。',
    promptEn: '{agent} remembered things I said.',
  ),
  PprWeeklyItem(
    id: 'u4_r',
    component: PprComponent.understanding,
    reversed: true,
    promptZh: '{agent} 嘅回應令我覺得佢冇真正聽我講。',
    promptEn: "{agent}'s replies made me feel it wasn't really listening.",
  ),
  // Validation
  PprWeeklyItem(
    id: 'v1',
    component: PprComponent.validation,
    promptZh: '{agent} 對待我嘅諗法同感受好認真。',
    promptEn: '{agent} took my thoughts and feelings seriously.',
  ),
  PprWeeklyItem(
    id: 'v2',
    component: PprComponent.validation,
    promptZh: '我覺得 {agent} 尊重我係邊個。',
    promptEn: '{agent} respected who I am.',
  ),
  PprWeeklyItem(
    id: 'v3',
    component: PprComponent.validation,
    promptZh: '{agent} 冇試圖修正我或者話我應該諗咩。',
    promptEn: "{agent} didn't try to fix me or tell me how to think.",
  ),
  PprWeeklyItem(
    id: 'v4_r',
    component: PprComponent.validation,
    reversed: true,
    promptZh: '我有時覺得 {agent} 評判緊我。',
    promptEn: 'I sometimes felt {agent} was judging me.',
  ),
  // Caring
  PprWeeklyItem(
    id: 'c1',
    component: PprComponent.caring,
    promptZh: '感覺到 {agent} 真係關心我點。',
    promptEn: 'It felt like {agent} cared about how I was doing.',
  ),
  PprWeeklyItem(
    id: 'c2',
    component: PprComponent.caring,
    promptZh: '同 {agent} 傾完之後，我感覺好啲。',
    promptEn: 'After talking with {agent}, I felt a little better.',
  ),
  PprWeeklyItem(
    id: 'c3',
    component: PprComponent.caring,
    promptZh: '我覺得 {agent} 留意我嘅福祉。',
    promptEn: '{agent} seemed to attend to my well-being.',
  ),
  PprWeeklyItem(
    id: 'c4_r',
    component: PprComponent.caring,
    reversed: true,
    promptZh: '{agent} 嘅回應感覺好機械化、冇人情味。',
    promptEn: "{agent}'s replies felt mechanical and uncaring.",
  ),
];

/// One stored response. The map under `items` is keyed by item id.
class PprResponse {
  final String? id;
  final String agentId;

  /// One of `brief_after_session` or `weekly_12_item`.
  final String form;

  /// 1–5 Likert per item (no neutralisation — that happens in analysis).
  final Map<String, int> items;
  final DateTime submittedAt;

  /// Optional free-text the participant added.
  final String? freeText;

  const PprResponse({
    this.id,
    required this.agentId,
    required this.form,
    required this.items,
    required this.submittedAt,
    this.freeText,
  });

  Map<String, dynamic> toMap() => {
        'agentId': agentId,
        'form': form,
        'items': items,
        'submittedAt': submittedAt.toIso8601String(),
        if (freeText != null) 'freeText': freeText,
      };
}

class PprResponseRepository {
  PprResponseRepository({required this.available});

  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ppr_responses');

  Future<String?> submit(String uid, PprResponse response) async {
    if (!available) return null;
    final ref = await _ref(uid).add(response.toMap()
      ..['submittedAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }
}

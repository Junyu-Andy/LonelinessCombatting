/// Shared context store (Developer Requirements §4.2).
///
/// Singleton document per user at `users/{uid}/shared_context`. Readable
/// by all three agents; writable only by:
///   • the safety layer (`safetyFlags`)
///   • the Action Loop tool (`activeActionPlans`)
///   • any agent for `recentMoodSummary` and `pendingCrossReferrals`
///
/// Per-field write authorisation is enforced server-side in
/// `firestore.rules`. This service is intentionally narrow — it owns
/// the field-level read/update surface and nothing else.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../safety/distress_detector.dart';

class SharedMoodSummary {
  /// Short narrative (≤200 chars) describing the user's recent mood.
  final String summary;
  final DateTime asOf;

  const SharedMoodSummary({required this.summary, required this.asOf});

  Map<String, dynamic> toMap() => {
        'summary': summary,
        'asOf': asOf.toIso8601String(),
      };

  factory SharedMoodSummary.fromMap(Map<String, dynamic> map) {
    final raw = map['asOf'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return SharedMoodSummary(
      summary: (map['summary'] as String?) ?? '',
      asOf: ts,
    );
  }
}

/// One pending agent-to-agent handoff candidate (Dev Req §5.4).
/// Written when the routing service decides to surface a referral;
/// consumed and cleared when the user enters the target agent.
class PendingReferral {
  final String id;
  final String fromAgent;
  final String toAgent;
  final String triggerSnippet;
  final String suggestionText;
  final DateTime proposedAt;

  /// `null` until consumed. Records whether the user accepted, declined,
  /// or ignored the handoff for cooldown bookkeeping.
  final String? resolution;

  const PendingReferral({
    required this.id,
    required this.fromAgent,
    required this.toAgent,
    required this.triggerSnippet,
    required this.suggestionText,
    required this.proposedAt,
    this.resolution,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fromAgent': fromAgent,
        'toAgent': toAgent,
        'triggerSnippet': triggerSnippet,
        'suggestionText': suggestionText,
        'proposedAt': proposedAt.toIso8601String(),
        'resolution': resolution,
      };

  factory PendingReferral.fromMap(Map<String, dynamic> map) {
    final raw = map['proposedAt'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return PendingReferral(
      id: (map['id'] as String?) ?? '',
      fromAgent: (map['fromAgent'] as String?) ?? '',
      toAgent: (map['toAgent'] as String?) ?? '',
      triggerSnippet: (map['triggerSnippet'] as String?) ?? '',
      suggestionText: (map['suggestionText'] as String?) ?? '',
      proposedAt: ts,
      resolution: map['resolution'] as String?,
    );
  }
}

/// One safety flag (Dev Req §4.4). Written by the safety layer the
/// moment a distress signal of any level above `none` is detected; read
/// by the researcher dashboard within 24h.
class SafetyFlag {
  final String id;
  final DistressLevel level;
  final String agentId;
  final String snippet;
  final DateTime detectedAt;

  /// `null` until the researcher follows up.
  final DateTime? acknowledgedAt;

  const SafetyFlag({
    required this.id,
    required this.level,
    required this.agentId,
    required this.snippet,
    required this.detectedAt,
    this.acknowledgedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'level': level.name,
        'agentId': agentId,
        'snippet': snippet,
        'detectedAt': detectedAt.toIso8601String(),
        'acknowledgedAt': acknowledgedAt?.toIso8601String(),
      };

  factory SafetyFlag.fromMap(Map<String, dynamic> map) {
    DateTime parse(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullable(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    DistressLevel level = DistressLevel.none;
    final raw = map['level'];
    if (raw is String) {
      for (final l in DistressLevel.values) {
        if (l.name == raw) {
          level = l;
          break;
        }
      }
    }

    return SafetyFlag(
      id: (map['id'] as String?) ?? '',
      level: level,
      agentId: (map['agentId'] as String?) ?? '',
      snippet: (map['snippet'] as String?) ?? '',
      detectedAt: parse(map['detectedAt']),
      acknowledgedAt: parseNullable(map['acknowledgedAt']),
    );
  }
}

class SharedContextSnapshot {
  final SharedMoodSummary? recentMood;
  final List<PendingReferral> pendingReferrals;
  final List<SafetyFlag> safetyFlags;
  final List<String> activeActionPlanIds;
  final DateTime? lastUpdated;

  const SharedContextSnapshot({
    this.recentMood,
    this.pendingReferrals = const [],
    this.safetyFlags = const [],
    this.activeActionPlanIds = const [],
    this.lastUpdated,
  });
}

class SharedContextService {
  SharedContextService({required this.available});

  final bool available;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('shared_context')
          .doc('current');

  Future<SharedContextSnapshot> read(String uid) async {
    if (!available) return const SharedContextSnapshot();
    final doc = await _ref(uid).get();
    if (!doc.exists) return const SharedContextSnapshot();
    final data = doc.data() ?? {};
    return SharedContextSnapshot(
      recentMood: data['recentMoodSummary'] is Map
          ? SharedMoodSummary.fromMap(
              Map<String, dynamic>.from(data['recentMoodSummary'] as Map))
          : null,
      pendingReferrals: _parseList(data['pendingReferrals'])
          .map(PendingReferral.fromMap)
          .toList(),
      safetyFlags:
          _parseList(data['safetyFlags']).map(SafetyFlag.fromMap).toList(),
      activeActionPlanIds: _parseStringList(data['activeActionPlanIds']),
      lastUpdated: _parseTs(data['lastUpdated']),
    );
  }

  Future<void> updateRecentMood({
    required String uid,
    required SharedMoodSummary mood,
  }) async {
    if (!available) return;
    await _ref(uid).set(
      {
        'recentMoodSummary': mood.toMap(),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> addPendingReferral({
    required String uid,
    required PendingReferral referral,
  }) async {
    if (!available) return;
    await _ref(uid).set(
      {
        'pendingReferrals': FieldValue.arrayUnion([referral.toMap()]),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Atomically clear all referrals currently targeted at [agentId]
  /// (Dev Req §5.4 — consumed when the user enters that agent).
  Future<List<PendingReferral>> drainReferralsTo({
    required String uid,
    required String agentId,
  }) async {
    if (!available) return const [];
    final ref = _ref(uid);
    final consumed = <PendingReferral>[];
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final all = _parseList(snap.data()?['pendingReferrals'])
          .map(PendingReferral.fromMap)
          .toList();
      final remaining = <PendingReferral>[];
      for (final r in all) {
        if (r.toAgent == agentId && r.resolution == null) {
          consumed.add(r);
        } else {
          remaining.add(r);
        }
      }
      tx.set(
        ref,
        {
          'pendingReferrals': remaining.map((r) => r.toMap()).toList(),
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    return consumed;
  }

  Future<void> addSafetyFlag({
    required String uid,
    required SafetyFlag flag,
  }) async {
    if (!available) return;
    await _ref(uid).set(
      {
        'safetyFlags': FieldValue.arrayUnion([flag.toMap()]),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setActiveActionPlanIds({
    required String uid,
    required List<String> ids,
  }) async {
    if (!available) return;
    await _ref(uid).set(
      {
        'activeActionPlanIds': ids,
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  List<Map<String, dynamic>> _parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final v in raw) {
      if (v is Map<String, dynamic>) {
        out.add(v);
      } else if (v is Map) {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  List<String> _parseStringList(Object? raw) {
    if (raw is! List) return const [];
    return [for (final v in raw) if (v is String) v];
  }

  DateTime? _parseTs(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

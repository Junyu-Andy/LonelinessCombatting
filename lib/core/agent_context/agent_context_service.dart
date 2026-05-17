/// Per-agent conversation context store (Developer Requirements §4).
///
/// Each (user, agent) pair has a single Firestore document holding:
///   • shortTermBuffer  — FIFO of recent turns, capped at [_bufferCap]
///   • namedEntities    — map of entity → mention metadata
///   • rollingSummary   — narrative summary (≤500 words)
///   • themeThreads     — keyed thread content (Ah Jan / Ah Bak only)
///   • lastUpdated      — server timestamp
///
/// Read/write boundary is enforced both client-side (this service only
/// addresses its own agent_id) and server-side (firestore.rules — Sprint 1
/// also writes the matching rule).
///
/// This scaffold is intentionally I/O-only — entity extraction, rolling-
/// summary compilation, and distress integration live in companion files
/// in this folder so this class stays unit-testable against a fake.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// One turn in the short-term buffer.
class AgentContextTurn {
  final bool fromUser;
  final String text;
  final DateTime timestamp;

  const AgentContextTurn({
    required this.fromUser,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'fromUser': fromUser,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AgentContextTurn.fromMap(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return AgentContextTurn(
      fromUser: (map['fromUser'] as bool?) ?? false,
      text: (map['text'] as String?) ?? '',
      timestamp: ts,
    );
  }
}

/// One named entity (person, place, life period) mentioned in conversation.
/// Stored as a map keyed by canonical name so future mentions update in
/// place rather than create duplicates.
class NamedEntity {
  /// One of `person | place | period | thing` — free-form for now;
  /// the extractor in Sprint 2 will narrow this.
  final String type;
  final DateTime firstMentioned;
  final DateTime lastMentioned;
  final int mentions;

  const NamedEntity({
    required this.type,
    required this.firstMentioned,
    required this.lastMentioned,
    required this.mentions,
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'firstMentioned': firstMentioned.toIso8601String(),
        'lastMentioned': lastMentioned.toIso8601String(),
        'mentions': mentions,
      };

  factory NamedEntity.fromMap(Map<String, dynamic> map) {
    DateTime parse(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return NamedEntity(
      type: (map['type'] as String?) ?? 'thing',
      firstMentioned: parse(map['firstMentioned']),
      lastMentioned: parse(map['lastMentioned']),
      mentions: (map['mentions'] as num?)?.toInt() ?? 1,
    );
  }

  NamedEntity bumpedAt(DateTime when) => NamedEntity(
        type: type,
        firstMentioned: firstMentioned,
        lastMentioned: when,
        mentions: mentions + 1,
      );
}

/// Snapshot of one agent's context document. Returned by reads — every
/// write goes through a typed method on [AgentContextService] to keep
/// invariants (FIFO cap, summary word-cap) honoured.
class AgentContextSnapshot {
  final String agentId;
  final List<AgentContextTurn> shortTermBuffer;
  final Map<String, NamedEntity> namedEntities;
  final String rollingSummary;

  /// Reserved for Ah Jan / Ah Bak — empty map for other agents.
  final Map<String, String> themeThreads;
  final DateTime? lastUpdated;

  const AgentContextSnapshot({
    required this.agentId,
    this.shortTermBuffer = const [],
    this.namedEntities = const {},
    this.rollingSummary = '',
    this.themeThreads = const {},
    this.lastUpdated,
  });

  bool get isEmpty =>
      shortTermBuffer.isEmpty &&
      namedEntities.isEmpty &&
      rollingSummary.isEmpty &&
      themeThreads.isEmpty;
}

/// Service over `users/{uid}/agent_contexts/{agent_id}` (Dev Req §4.2).
///
/// All methods are no-ops when [available] is false — the rest of the
/// app boots in guest mode without Firebase and consumers shouldn't
/// have to branch on auth state at every callsite.
class AgentContextService {
  AgentContextService({required this.available});

  /// False when Firebase initialisation failed. Matches the established
  /// pattern in [AuthService] / [MemoryStore] / [ActionPlanRepository].
  final bool available;

  /// FIFO cap for [AgentContextSnapshot.shortTermBuffer]. The spec says
  /// N=20 turns; we keep one knob so tests / future per-agent overrides
  /// don't fork the cap.
  static const int bufferCap = 20;

  /// Rolling-summary word cap (Dev Req §4.4 / §4.5). The compiler in
  /// Sprint 2 truncates to this on each update.
  static const int rollingSummaryWordCap = 500;

  DocumentReference<Map<String, dynamic>> _ref(String uid, String agentId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('agent_contexts')
          .doc(agentId);

  /// Read the current context snapshot. Returns an empty snapshot
  /// (not null) when the doc doesn't exist yet so callers can compose
  /// safely.
  Future<AgentContextSnapshot> read({
    required String uid,
    required String agentId,
  }) async {
    if (!available) {
      return AgentContextSnapshot(agentId: agentId);
    }
    final doc = await _ref(uid, agentId).get();
    if (!doc.exists) return AgentContextSnapshot(agentId: agentId);
    final data = doc.data() ?? {};
    return AgentContextSnapshot(
      agentId: agentId,
      shortTermBuffer: _parseBuffer(data['shortTermBuffer']),
      namedEntities: _parseEntities(data['namedEntities']),
      rollingSummary: (data['rollingSummary'] as String?) ?? '',
      themeThreads: _parseThemeThreads(data['themeThreads']),
      lastUpdated: _parseTs(data['lastUpdated']),
    );
  }

  /// Append one turn to the short-term buffer, trimming to [bufferCap].
  ///
  /// Uses a transaction to avoid clobbering concurrent writes from a
  /// second device. The append also updates `lastUpdated` and prunes
  /// the oldest turn(s) when the cap is exceeded.
  Future<void> appendTurn({
    required String uid,
    required String agentId,
    required AgentContextTurn turn,
  }) async {
    if (!available) return;
    final ref = _ref(uid, agentId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = snap.exists
          ? _parseBuffer(snap.data()?['shortTermBuffer'])
          : <AgentContextTurn>[];
      current.add(turn);
      while (current.length > bufferCap) {
        current.removeAt(0);
      }
      tx.set(
        ref,
        {
          'shortTermBuffer':
              current.map((t) => t.toMap()).toList(growable: false),
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Merge one or more named-entity mentions. Existing entries have
  /// their `lastMentioned` and `mentions` bumped; new entries are
  /// inserted with `firstMentioned == now`.
  Future<void> recordEntities({
    required String uid,
    required String agentId,
    required Map<String, String> entitiesWithType,
    DateTime? now,
  }) async {
    if (!available || entitiesWithType.isEmpty) return;
    final ts = now ?? DateTime.now();
    final ref = _ref(uid, agentId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = snap.exists
          ? _parseEntities(snap.data()?['namedEntities'])
          : <String, NamedEntity>{};
      entitiesWithType.forEach((name, type) {
        final key = name.trim();
        if (key.isEmpty) return;
        final existing = current[key];
        current[key] = existing == null
            ? NamedEntity(
                type: type,
                firstMentioned: ts,
                lastMentioned: ts,
                mentions: 1,
              )
            : existing.bumpedAt(ts);
      });
      tx.set(
        ref,
        {
          'namedEntities': {
            for (final e in current.entries) e.key: e.value.toMap(),
          },
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Replace the rolling summary string. The caller is responsible for
  /// keeping the summary under [rollingSummaryWordCap] words — the
  /// compiler in `rolling_summary_compiler.dart` (Sprint 2) does the
  /// truncation.
  Future<void> writeRollingSummary({
    required String uid,
    required String agentId,
    required String summary,
  }) async {
    if (!available) return;
    await _ref(uid, agentId).set(
      {
        'rollingSummary': summary,
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Upsert one theme thread (Ah Jan / Ah Bak). The [threadKey] is a
  /// stable identifier like `w1_childhood`; [content] is the most
  /// recent salient line for the thread.
  Future<void> writeThemeThread({
    required String uid,
    required String agentId,
    required String threadKey,
    required String content,
  }) async {
    if (!available) return;
    await _ref(uid, agentId).set(
      {
        'themeThreads': {threadKey: content},
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Drop the short-term buffer (end-of-session, retention OFF).
  /// Named entities, rolling summary, and theme threads survive — only
  /// verbatim turn text is purged.
  Future<void> discardShortTermBuffer({
    required String uid,
    required String agentId,
  }) async {
    if (!available) return;
    await _ref(uid, agentId).set(
      {
        'shortTermBuffer': <Map<String, dynamic>>[],
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ----- parsers -----

  List<AgentContextTurn> _parseBuffer(Object? raw) {
    if (raw is! List) return const [];
    final out = <AgentContextTurn>[];
    for (final t in raw) {
      if (t is Map<String, dynamic>) {
        out.add(AgentContextTurn.fromMap(t));
      } else if (t is Map) {
        out.add(AgentContextTurn.fromMap(Map<String, dynamic>.from(t)));
      }
    }
    return out;
  }

  Map<String, NamedEntity> _parseEntities(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, NamedEntity>{};
    raw.forEach((k, v) {
      if (k is String && v is Map) {
        out[k] = NamedEntity.fromMap(Map<String, dynamic>.from(v));
      }
    });
    return out;
  }

  Map<String, String> _parseThemeThreads(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }

  DateTime? _parseTs(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

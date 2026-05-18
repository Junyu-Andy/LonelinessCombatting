/// The piece of user information we persist in Firestore under `users/{uid}`.
///
/// Kept intentionally small — this is a companion app, not a full CRM.
/// Fields added here should feel genuinely useful to the user (e.g. the
/// emergency contact), not just for analytics.

import '../../../core/agents/agent_registry.dart';

/// RCT arm assignment. Determined once at signup by [AuthService] via a
/// Firestore transaction that balances 1:1 across the cohort. Never shown to
/// the user; the UI shell is identical across arms.
enum ArmAssignment {
  /// Hybrid (rule + LLM). Adaptive dialogue, longitudinal memory, personalised
  /// follow-ups.
  a,

  /// Rule-based. Fixed forms, static templates, no LLM in-the-loop.
  b;

  String get code => switch (this) {
        ArmAssignment.a => 'A',
        ArmAssignment.b => 'B',
      };

  static ArmAssignment? tryParse(String? code) {
    switch (code?.toUpperCase()) {
      case 'A':
        return ArmAssignment.a;
      case 'B':
        return ArmAssignment.b;
      default:
        return null;
    }
  }
}

/// Tiered consent. Functional data (mood scores, completed actions) is needed
/// for the app to work at all. Transcript retention (raw free-text and LLM
/// conversation logs) is optional and stored separately for ethics review.
///
/// Dev Req §4.5 extends transcript retention to be per-agent: a user may
/// be comfortable with Ah Jan / Ah Bak retaining life-story content but
/// not with Siu Yan retaining detailed daily mood logs. We keep the
/// legacy global [transcriptRetention] flag as a fallback for code paths
/// not yet wired to the per-agent map, but new code MUST prefer
/// [transcriptRetentionFor] which honours the per-agent override.
class ConsentFlags {
  final bool functionalData;

  /// Legacy global transcript-retention flag. Phase 0 used a single
  /// switch in Settings → Privacy. New per-agent switches live in
  /// [transcriptRetentionByAgent]; this field remains the fallback
  /// when an agent has no explicit entry.
  final bool transcriptRetention;

  /// Per-agent transcript retention (Dev Req §4.5). Keys are agent ids
  /// from [AgentRegistry] (`siu_yan`, `ah_jan_ah_bak`, `tung_tung`).
  /// Missing keys fall back to [transcriptRetention].
  final Map<String, bool> transcriptRetentionByAgent;

  /// "Shared context" lets agents reference each other's recent content
  /// (mood, action plans). Off by default — turning it on tightens the
  /// integration between agents. Tracks Dev Req §4.2 `shared_context_use`.
  final bool sharedContextUse;

  final DateTime? acceptedAt;

  const ConsentFlags({
    this.functionalData = false,
    this.transcriptRetention = false,
    this.transcriptRetentionByAgent = const {},
    this.sharedContextUse = false,
    this.acceptedAt,
  });

  /// Resolve transcript retention for [agentId], falling back to the
  /// legacy global flag when no per-agent override exists.
  bool transcriptRetentionFor(String agentId) =>
      transcriptRetentionByAgent[agentId] ?? transcriptRetention;

  ConsentFlags copyWith({
    bool? functionalData,
    bool? transcriptRetention,
    Map<String, bool>? transcriptRetentionByAgent,
    bool? sharedContextUse,
    DateTime? acceptedAt,
  }) =>
      ConsentFlags(
        functionalData: functionalData ?? this.functionalData,
        transcriptRetention: transcriptRetention ?? this.transcriptRetention,
        transcriptRetentionByAgent:
            transcriptRetentionByAgent ?? this.transcriptRetentionByAgent,
        sharedContextUse: sharedContextUse ?? this.sharedContextUse,
        acceptedAt: acceptedAt ?? this.acceptedAt,
      );

  Map<String, dynamic> toMap() => {
        'functionalData': functionalData,
        'transcriptRetention': transcriptRetention,
        'transcriptRetentionByAgent': transcriptRetentionByAgent,
        'sharedContextUse': sharedContextUse,
        'acceptedAt': acceptedAt?.toIso8601String(),
      };

  factory ConsentFlags.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ConsentFlags();
    DateTime? parsed;
    final raw = map['acceptedAt'];
    if (raw is String) parsed = DateTime.tryParse(raw);
    final perAgentRaw = map['transcriptRetentionByAgent'];
    final perAgent = <String, bool>{};
    if (perAgentRaw is Map) {
      perAgentRaw.forEach((k, v) {
        if (k is String && v is bool) perAgent[k] = v;
      });
    }
    return ConsentFlags(
      functionalData: (map['functionalData'] as bool?) ?? false,
      transcriptRetention: (map['transcriptRetention'] as bool?) ?? false,
      transcriptRetentionByAgent: perAgent,
      sharedContextUse: (map['sharedContextUse'] as bool?) ?? false,
      acceptedAt: parsed,
    );
  }
}

/// A named real-life relation the user wants the system to know about.
/// Powers Siu Yan's named-contact reference behaviour (Walkthrough Case 2)
/// and Action Loop's plan-with-named-person flow (Walkthrough Case 7).
///
/// Captured in onboarding (and editable in Personalisation). Stored under
/// the user profile, not in a separate subcollection — the list is short
/// (typically 3–10 entries) and we want it to load atomically with the
/// profile.
class CloseContact {
  final String name;

  /// Free-text relation label, e.g. "daughter", "old friend", "neighbour".
  /// Kept as free-text rather than an enum because relations don't slot
  /// cleanly into a fixed taxonomy for older Hong Kong adults.
  final String? relation;

  /// Optional phone — used by Action Loop to pre-fill the call-target
  /// when the user plans a contact. Not displayed elsewhere.
  final String? phone;

  const CloseContact({
    required this.name,
    this.relation,
    this.phone,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'relation': relation,
        'phone': phone,
      };

  factory CloseContact.fromMap(Map<String, dynamic> map) => CloseContact(
        name: (map['name'] as String?) ?? '',
        relation: map['relation'] as String?,
        phone: map['phone'] as String?,
      );
}

class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? ageGroup;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? preferredLanguage;
  final bool? highContrast;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final ArmAssignment? arm;
  final ConsentFlags consent;

  /// Selected gender variant for Ah Jan / Ah Bak. Captured at onboarding.
  /// `null` until the variant-selection step completes; the registry
  /// falls back to the feminine variant for rendering when null.
  final AgentGenderVariant? ahJanAhBakVariant;

  /// Short list of named real-life relations the user wants the system
  /// to know about (Dev Req §4.2). Powers Siu Yan's contact-aware
  /// behaviour and Action Loop's named-contact picker.
  final List<CloseContact> closeContacts;

  /// Interest tags captured at onboarding + extended by Tung Tung over
  /// time (Dev Req §6.2). Free-text, lower-cased, deduplicated.
  final List<String> interests;

  /// C.2 — stratification cell assigned at signup (0–3, based on age group).
  /// Null for users enrolled before Sprint 1 (treated as cell 0 in analysis).
  final int? strataCell;

  /// Timestamps of the first time each agent introduced itself to the
  /// user (Dev Req §3.3). Missing entries mean the intro has not been
  /// shown yet and must be played the next time the agent opens.
  final Map<String, DateTime> firstIntroSeen;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.ageGroup,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.preferredLanguage,
    this.highContrast,
    this.createdAt,
    this.lastLoginAt,
    this.arm,
    this.consent = const ConsentFlags(),
    this.ahJanAhBakVariant,
    this.closeContacts = const [],
    this.interests = const [],
    this.strataCell,
    this.firstIntroSeen = const {},
  });

  UserProfile copyWith({
    String? displayName,
    String? ageGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? preferredLanguage,
    bool? highContrast,
    DateTime? lastLoginAt,
    ArmAssignment? arm,
    ConsentFlags? consent,
    AgentGenderVariant? ahJanAhBakVariant,
    List<CloseContact>? closeContacts,
    List<String>? interests,
    int? strataCell,
    Map<String, DateTime>? firstIntroSeen,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      ageGroup: ageGroup ?? this.ageGroup,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      highContrast: highContrast ?? this.highContrast,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      arm: arm ?? this.arm,
      consent: consent ?? this.consent,
      ahJanAhBakVariant: ahJanAhBakVariant ?? this.ahJanAhBakVariant,
      closeContacts: closeContacts ?? this.closeContacts,
      interests: interests ?? this.interests,
      strataCell: strataCell ?? this.strataCell,
      firstIntroSeen: firstIntroSeen ?? this.firstIntroSeen,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'ageGroup': ageGroup,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'preferredLanguage': preferredLanguage,
        'highContrast': highContrast,
        'createdAt': createdAt?.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'arm': arm?.code,
        'consent': consent.toMap(),
        'ahJanAhBakVariant': ahJanAhBakVariant?.code,
        'closeContacts': closeContacts.map((c) => c.toMap()).toList(),
        'interests': interests,
        'strataCell': strataCell,
        'firstIntroSeen': {
          for (final e in firstIntroSeen.entries)
            e.key: e.value.toIso8601String(),
        },
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      // Firestore Timestamp has .toDate() — handled dynamically so this class
      // stays independent of cloud_firestore types.
      try {
        final dynamic dyn = value;
        final result = dyn.toDate();
        if (result is DateTime) return result;
      } catch (_) {}
      return null;
    }

    final contactsRaw = map['closeContacts'];
    final contacts = <CloseContact>[];
    if (contactsRaw is List) {
      for (final c in contactsRaw) {
        if (c is Map<String, dynamic>) contacts.add(CloseContact.fromMap(c));
      }
    }
    final interestsRaw = map['interests'];
    final interests = <String>[];
    if (interestsRaw is List) {
      for (final t in interestsRaw) {
        if (t is String && t.trim().isNotEmpty) interests.add(t);
      }
    }
    final introRaw = map['firstIntroSeen'];
    final intro = <String, DateTime>{};
    if (introRaw is Map) {
      introRaw.forEach((k, v) {
        if (k is String) {
          final dt = parseDate(v);
          if (dt != null) intro[k] = dt;
        }
      });
    }

    return UserProfile(
      uid: uid,
      email: (map['email'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      ageGroup: map['ageGroup'] as String?,
      emergencyContactName: map['emergencyContactName'] as String?,
      emergencyContactPhone: map['emergencyContactPhone'] as String?,
      preferredLanguage: map['preferredLanguage'] as String?,
      highContrast: map['highContrast'] as bool?,
      createdAt: parseDate(map['createdAt']),
      lastLoginAt: parseDate(map['lastLoginAt']),
      arm: ArmAssignment.tryParse(map['arm'] as String?),
      consent: ConsentFlags.fromMap(map['consent'] as Map<String, dynamic>?),
      ahJanAhBakVariant:
          AgentGenderVariant.tryParse(map['ahJanAhBakVariant'] as String?),
      closeContacts: contacts,
      interests: interests,
      strataCell: (map['strataCell'] as num?)?.toInt(),
      firstIntroSeen: intro,
    );
  }
}

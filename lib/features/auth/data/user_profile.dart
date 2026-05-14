/// The piece of user information we persist in Firestore under `users/{uid}`.
///
/// Kept intentionally small — this is a companion app, not a full CRM.
/// Fields added here should feel genuinely useful to the user (e.g. the
/// emergency contact), not just for analytics.

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
class ConsentFlags {
  final bool functionalData;
  final bool transcriptRetention;
  final DateTime? acceptedAt;

  const ConsentFlags({
    this.functionalData = false,
    this.transcriptRetention = false,
    this.acceptedAt,
  });

  ConsentFlags copyWith({
    bool? functionalData,
    bool? transcriptRetention,
    DateTime? acceptedAt,
  }) =>
      ConsentFlags(
        functionalData: functionalData ?? this.functionalData,
        transcriptRetention: transcriptRetention ?? this.transcriptRetention,
        acceptedAt: acceptedAt ?? this.acceptedAt,
      );

  Map<String, dynamic> toMap() => {
        'functionalData': functionalData,
        'transcriptRetention': transcriptRetention,
        'acceptedAt': acceptedAt?.toIso8601String(),
      };

  factory ConsentFlags.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ConsentFlags();
    DateTime? parsed;
    final raw = map['acceptedAt'];
    if (raw is String) parsed = DateTime.tryParse(raw);
    return ConsentFlags(
      functionalData: (map['functionalData'] as bool?) ?? false,
      transcriptRetention: (map['transcriptRetention'] as bool?) ?? false,
      acceptedAt: parsed,
    );
  }
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
    );
  }
}

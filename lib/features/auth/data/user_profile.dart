/// The piece of user information we persist in Firestore under `users/{uid}`.
///
/// Kept intentionally small — this is a companion app, not a full CRM.
/// Fields added here should feel genuinely useful to the user (e.g. the
/// emergency contact), not just for analytics.
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
  });

  UserProfile copyWith({
    String? displayName,
    String? ageGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? preferredLanguage,
    bool? highContrast,
    DateTime? lastLoginAt,
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
    );
  }
}

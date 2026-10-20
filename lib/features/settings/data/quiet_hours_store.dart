/// 1020o 第三节 — writes the elder's 「安靜時段」 to `users/{uid}`.
///
/// One field per pick (`quietHoursStart` for 「由」, `quietHoursEnd` for
/// 「到」), merged into the profile doc.  The profile's own saves
/// (`UserProfile.toMap`) never carry these two fields, so they can neither
/// erase nor overwrite them with an old value.  firestore.rules accept only
/// the values the pickers offer (QuietHoursRange).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

enum QuietHoursField {
  start('start', 'quietHoursStart'),
  end('end', 'quietHoursEnd');

  const QuietHoursField(this.code, this.profileKey);

  /// `field` in the `quiet_hours_changed` usage event.
  final String code;

  /// The `users/{uid}` field.
  final String profileKey;
}

abstract class QuietHoursStore {
  Future<void> save(String uid, QuietHoursField field, String value);
}

/// Through the Firestore SDK (offline queue).  Firestore is touched only
/// when something is saved.
class FirestoreQuietHoursStore implements QuietHoursStore {
  const FirestoreQuietHoursStore();

  @override
  Future<void> save(String uid, QuietHoursField field, String value) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({field.profileKey: value}, SetOptions(merge: true));
}

/// Tests: what would have been written, per uid.
class InMemoryQuietHoursStore implements QuietHoursStore {
  final Map<String, Map<String, String>> docs = {};

  @override
  Future<void> save(String uid, QuietHoursField field, String value) async {
    (docs[uid] ??= {})[field.profileKey] = value;
  }
}

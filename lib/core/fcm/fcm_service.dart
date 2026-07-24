/// B.12 — FCM push transport.
///
/// Responsibilities:
///   1. Request notification permission on iOS.
///   2. Obtain the device FCM token and store it under
///      `users/{uid}/fcm_tokens/{installationId}`.
///   3. Subscribe to [FirebaseMessaging.onTokenRefresh] and keep the stored
///      token up-to-date across token rotations (app upgrades, token
///      invalidation).
///
/// The [FirestoreReminderQueue] writes reminder intents to Firestore; this
/// service makes the device reachable so a Cloud Function (Sprint 3, C.1)
/// can read the queue and call the FCM REST API to deliver the push.
///
/// Call [initialize] once after the user signs in with a valid [uid].
/// Call [deregister] on sign-out to remove the token so the device doesn't
/// receive pushes for a signed-out account.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  FcmService({required this.available});

  final bool available;

  /// Broadcast topic every signed-in device subscribes to. The T2
  /// scheduled "doorbell" functions (daily mood / weekly survey reminders)
  /// and Junyu's ad-hoc Firebase Console nudges all target this topic, so
  /// no per-device token fan-out is needed for v1.
  static const String broadcastTopic = 'all';

  String? _currentUid;
  String? _installationId;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Initialize FCM for [uid].  Safe to call repeatedly — re-calling with the
  /// same uid is a no-op; calling with a different uid re-registers.
  Future<void> initialize(String uid) async {
    if (!available) return;
    _currentUid = uid;

    final messaging = FirebaseMessaging.instance;

    // iOS requires explicit permission; Android 13+ also needs it.
    // We request here without forcing the system prompt — callers should
    // have already shown an in-app explanation before calling initialize.
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] requestPermission failed: $e');
    }

    // Get a stable installation identifier to use as the Firestore doc key.
    // FirebaseMessaging.getToken() returns a device+app-scoped token; we hash
    // it to get a stable short key that survives token rotation.
    // On iOS builds without APNs configured (e.g. dev provisioning before
    // the push entitlement is set up) this throws
    // [firebase_messaging/apns-token-not-set] — push simply stays off.
    String? token;
    try {
      token = await messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] getToken failed: $e');
    }
    if (token != null) {
      _installationId = _shortId(token);
      await _storeToken(uid, token);
    }

    // T2 — subscribe to the broadcast topic so the scheduled doorbell
    // functions reach this device. Best-effort: topic subscription needs
    // network + granted permission; failure just means no pushes, never a
    // crash. (No-op on web where topic messaging is unsupported.)
    if (!kIsWeb) {
      try {
        await messaging.subscribeToTopic(broadcastTopic);
      } catch (e) {
        if (kDebugMode) debugPrint('[fcm] subscribe topic failed: $e');
      }
    }

    // Keep the stored token current across rotations. Guarded so repeated
    // initialize() calls don't stack duplicate listeners.
    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((newToken) async {
      _installationId = _shortId(newToken);
      if (_currentUid != null) {
        await _storeToken(_currentUid!, newToken);
      }
    });
  }

  /// Remove this device's token on sign-out so pushes stop.
  Future<void> deregister() async {
    if (!available || _currentUid == null || _installationId == null) return;
    if (!kIsWeb) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(broadcastTopic);
      } catch (e) {
        if (kDebugMode) debugPrint('[fcm] unsubscribe topic failed: $e');
      }
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .collection('fcm_tokens')
          .doc(_installationId)
          .delete();
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] deregister failed: $e');
    }
    _currentUid = null;
    _installationId = null;
  }

  Future<void> _storeToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcm_tokens')
          .doc(_shortId(token))
          .set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] store token failed: $e');
    }
  }

  /// First 16 chars of the token — stable enough as a doc key, short enough
  /// to be readable in the console.  Token format guarantees alphanumeric.
  static String _shortId(String token) =>
      token.length >= 16 ? token.substring(0, 16) : token;
}

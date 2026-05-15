import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'arm_assigner.dart';
import 'user_profile.dart';

/// Wraps [FirebaseAuth] + Firestore so the UI can treat auth as a simple
/// stream + async calls and stay ignorant of Firebase types.
///
/// Behaviour when Firebase isn't configured: constructor still succeeds (the
/// plugin has already failed earlier in `main`), but every call throws
/// [AuthUnavailableException] so callers can show a friendly message.
class AuthService {
  AuthService({required this.available, ArmAssigner? armAssigner})
      : _armAssigner = armAssigner ?? ArmAssigner();

  /// False when Firebase.initializeApp failed — typically because
  /// firebase_options.dart hasn't been generated yet. Lets the UI show a
  /// "guest mode" banner instead of crashing.
  final bool available;

  final ArmAssigner _armAssigner;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<UserProfile?> profileChanges() async* {
    if (!available) {
      yield null;
      return;
    }
    await for (final user in _auth.authStateChanges()) {
      if (user == null) {
        yield null;
        continue;
      }
      yield await _loadOrCreateProfile(user);
    }
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    _ensureAvailable();
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    final profile = await _loadOrCreateProfile(user);
    await _db.collection('users').doc(user.uid).set(
      {'lastLoginAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    return profile;
  }

  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String displayName,
    String? ageGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? preferredLanguage,
    ConsentFlags consent = const ConsentFlags(),
  }) async {
    _ensureAvailable();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(displayName);
    final arm = await _armAssigner.assign(_db);
    final profile = UserProfile(
      uid: user.uid,
      email: user.email ?? email.trim(),
      displayName: displayName,
      ageGroup: ageGroup,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      preferredLanguage: preferredLanguage,
      arm: arm,
      consent: consent,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    await _db.collection('users').doc(user.uid).set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
    return profile;
  }

  Future<void> signOut() async {
    if (!available) return;
    await _auth.signOut();
  }

  Future<void> updateProfile(UserProfile profile) async {
    _ensureAvailable();
    await _db.collection('users').doc(profile.uid).set(
      profile.toMap(),
      SetOptions(merge: true),
    );
  }

  Future<UserProfile> _loadOrCreateProfile(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (doc.exists) {
      final existing = UserProfile.fromMap(user.uid, doc.data() ?? {});
      // Backfill arm for accounts created before randomisation went live.
      if (existing.arm == null) {
        final arm = await _armAssigner.assign(_db);
        final patched = existing.copyWith(arm: arm);
        await ref.set({'arm': arm.code}, SetOptions(merge: true));
        return patched;
      }
      return existing;
    }
    final arm = await _armAssigner.assign(_db);
    final profile = UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? (user.email ?? '用戶').split('@').first,
      arm: arm,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    await ref.set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
    return profile;
  }

  void _ensureAvailable() {
    if (!available) {
      throw AuthUnavailableException();
    }
  }
}

class AuthUnavailableException implements Exception {
  @override
  String toString() =>
      'Firebase is not configured. Run `flutterfire configure` — see SETUP_FIREBASE.md.';
}

/// Maps raw [FirebaseAuthException] codes to friendly Cantonese strings.
String describeAuthError(Object error) {
  if (error is AuthUnavailableException) {
    return 'Firebase 未設定，唔可以登入。請先完成 SETUP_FIREBASE.md 嘅步驟。';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return '電郵格式唔啱。';
      case 'user-disabled':
        return '呢個帳號已經停用。';
      case 'user-not-found':
        return '搵唔到呢個帳號。';
      case 'wrong-password':
      case 'invalid-credential':
        return '密碼唔啱。';
      case 'email-already-in-use':
        return '呢個電郵已經註冊過。試吓直接登入。';
      case 'weak-password':
        return '密碼太簡單，請長啲。';
      case 'network-request-failed':
        return '網絡唔穩，請再試。';
    }
  }
  if (kDebugMode) {
    return '登入失敗：$error';
  }
  return '登入失敗，請再試。';
}

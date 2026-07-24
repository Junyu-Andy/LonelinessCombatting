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
    final UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // With Firebase email-enumeration protection OFF, we can tell an
      // unregistered email apart from a wrong password by asking which
      // sign-in methods the email has. (If enumeration protection is on,
      // fetch returns [] for everything and we fall back to the original.)
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found') {
        List<String> methods;
        try {
          methods = await _auth.fetchSignInMethodsForEmail(email.trim());
        } catch (_) {
          rethrow; // couldn't check — surface the original merged error
        }
        throw AuthCredentialException(emailRegistered: methods.isNotEmpty);
      }
      rethrow;
    }
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
    /// C.2 — baseline UCLA-LS-V3 total used for stratification (Phase B
    /// §4.4).  Pass when known at signup (HKU baseline assessment
    /// completed before in-person onboarding).  Null in Phase A is
    /// acceptable since forceArmA shortcuts the assignment anyway.
    int? baselineUclaScore,
  }) async {
    _ensureAvailable();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(displayName);
    // Arm assignment must NEVER block account creation: the assignment
    // transaction writes meta/arm_counter, and a rules problem there
    // (e.g. the bare-map-key bug that shipped in the 7/21 rules deploy)
    // used to make EVERY new registration throw after the Auth user was
    // already created — leaving an account that could never sign in.
    // On failure we create the profile with arm=null; the backfill in
    // _loadOrCreateProfile retries on a later login, and Phase A forces
    // Arm A in the UI regardless.
    ArmAssignment? arm;
    int? strataCell;
    try {
      final assignment = await _armAssigner.assign(
        _db,
        ageGroup: ageGroup,
        uclaScore: baselineUclaScore,
      );
      arm = assignment.arm;
      strataCell = assignment.cell;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[auth] arm assignment failed at signup '
            '(will backfill later): $e');
      }
    }
    final profile = UserProfile(
      uid: user.uid,
      email: user.email ?? email.trim(),
      displayName: displayName,
      ageGroup: ageGroup,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      preferredLanguage: preferredLanguage,
      arm: arm,
      strataCell: strataCell,
      consent: consent,
      baselineUclaScore: baselineUclaScore,
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

  /// B.10 — activate 今日休息 for [uid].  Idempotent: if already activated
  /// today, this is a no-op (returns false).  Returns true when newly set.
  Future<bool> activateQuietToday(UserProfile profile) async {
    if (!available) return false;
    if (profile.isQuietToday) return false;
    final now = DateTime.now();
    await _db.collection('users').doc(profile.uid).set(
      {'quietTodayActivatedAt': now.toIso8601String()},
      SetOptions(merge: true),
    );
    return true;
  }

  /// B06 — turn 今日休息 back off the same day.  Clears the activation
  /// timestamp so [UserProfile.isQuietToday] returns false and reminders
  /// resume.  No-op when Firebase is unavailable (guest mode).
  Future<void> deactivateQuietToday(UserProfile profile) async {
    if (!available) return;
    await _db.collection('users').doc(profile.uid).set(
      {'quietTodayActivatedAt': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Future<UserProfile> _loadOrCreateProfile(User user) async {
    final ref = _db.collection('users').doc(user.uid);

    // createUserWithEmailAndPassword fires authStateChanges before signUp()
    // has had a chance to write the profile doc (with the user-provided
    // displayName) to Firestore. Without a retry, we'd race ahead and
    // auto-create a fallback profile whose displayName is the email prefix
    // — and that wrong name would then stick in the UI for the whole
    // session. Poll for the doc up to ~5s before falling back — signUp's
    // arm transaction + two writes routinely exceed the old 1.5s window
    // on slow connections.
    var doc = await ref.get();
    if (!doc.exists) {
      for (var i = 0; i < 10 && !doc.exists; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        doc = await ref.get();
      }
    }

    if (doc.exists) {
      final existing = UserProfile.fromMap(user.uid, doc.data() ?? {});
      // Backfill arm for accounts created before randomisation went live
      // (or whose signup-time assignment failed). Best-effort: a broken
      // arm_counter rule must not lock the user out of sign-in — the
      // backfill simply retries on the next login.
      if (existing.arm == null) {
        try {
          final result = await _armAssigner.assign(_db,
              ageGroup: existing.ageGroup);
          final patched = existing.copyWith(
              arm: result.arm, strataCell: result.cell);
          await ref.set({
            'arm': result.arm.code,
            'strataCell': result.cell,
          }, SetOptions(merge: true));
          return patched;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[auth] arm backfill failed '
                '(sign-in continues, retries next login): $e');
          }
          return existing;
        }
      }
      return existing;
    }
    // Fallback profile WITHOUT an arm assignment.  If we're racing
    // signUp(), its own write (which carries the properly assigned arm)
    // lands moments later and overwrites this doc; assigning here too
    // double-incremented the meta/arm_counter and skewed stratification
    // bookkeeping.  If no signUp write ever lands (genuinely missing
    // doc), the arm==null backfill branch above assigns on next load.
    final profile = UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? (user.email ?? '用戶').split('@').first,
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

/// Thrown by [AuthService.signIn] when a credential fails and we could
/// determine which side was wrong. [emailRegistered] true = the email
/// exists so the password was wrong; false = the email isn't registered.
class AuthCredentialException implements Exception {
  final bool emailRegistered;
  AuthCredentialException({required this.emailRegistered});
}

/// Maps raw [FirebaseAuthException] codes to friendly Cantonese strings.
String describeAuthError(Object error, {bool isEn = false}) {
  if (error is AuthUnavailableException) {
    return isEn
        ? 'Firebase is not set up, so sign-in is unavailable. Complete the '
            'steps in SETUP_FIREBASE.md first.'
        : 'Firebase 未設定，暫時登入唔到。請先完成 SETUP_FIREBASE.md 嘅步驟。';
  }
  if (error is AuthCredentialException) {
    if (error.emailRegistered) {
      return isEn ? 'The password is incorrect.' : '密碼唔啱。';
    }
    // fetchSignInMethodsForEmail returns [] in modern SDKs even for
    // registered emails, so an empty result is NOT proof the email is
    // unregistered — use the honest merged wording instead of wrongly
    // telling an existing user they never signed up.
    return isEn
        ? 'Email or password is incorrect. If you don\'t have an account '
            'yet, tap "Create account" below.'
        : '電郵或密碼唔啱。如果你仲未註冊，可以撳下面「建立帳號」。';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return isEn
            ? "That email address doesn't look right."
            : '電郵格式好似唔啱。';
      case 'user-disabled':
        return isEn ? 'This account has been disabled.' : '呢個帳號已經停用。';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        // Modern Firebase deliberately merges "no such account" and "wrong
        // password" into invalid-credential (anti-enumeration), so we can't
        // truthfully say which one it is — guide the user to both paths.
        return isEn
            ? 'Email or password is incorrect. If you don\'t have an account '
                'yet, tap "Create account" below.'
            : '電郵或密碼唔啱。如果你仲未註冊，可以撳下面「建立帳號」。';
      case 'email-already-in-use':
        return isEn
            ? 'This email is already registered — please sign in instead.'
            : '呢個電郵已經註冊咗，請直接撳「登入」。';
      case 'weak-password':
        return isEn
            ? 'Password is too simple — please make it longer.'
            : '密碼太簡單，請長啲。';
      case 'network-request-failed':
      case 'unavailable':
      case 'timeout':
      case 'deadline-exceeded':
        // The backend (Firebase / Google Cloud) is unreachable. In most
        // networks this is transient, but on a restricted network the
        // server may be unreachable entirely — surface the concrete
        // recovery steps rather than a vague "try again".
        return isEn
            ? 'Cannot reach the server right now. Please check your '
                'connection and try again. If it keeps failing, switch '
                'network (e.g. mobile data), turn on a VPN, or try a '
                'different network provider.'
            : '暫時連唔到伺服器。請檢查網絡再試。如果一直都連唔到，'
                '可以換個網絡（例如轉用流動數據）、開 VPN，'
                '或者換另一間網絡供應商。';
    }
  }
  // Firestore/Cloud errors sometimes arrive as a generic FirebaseException
  // (not FirebaseAuthException) with a network-ish code — treat the same
  // reachability codes identically so login never fails silently.
  if (error is FirebaseException &&
      const {'unavailable', 'deadline-exceeded', 'timeout'}
          .contains(error.code)) {
    return isEn
        ? 'Cannot reach the server right now. Please check your connection '
            'and try again. If it keeps failing, switch network (e.g. mobile '
            'data), turn on a VPN, or try a different network provider.'
        : '暫時連唔到伺服器。請檢查網絡再試。如果一直都連唔到，'
            '可以換個網絡（例如轉用流動數據）、開 VPN，'
            '或者換另一間網絡供應商。';
  }
  if (kDebugMode) {
    return 'Auth failed: $error';
  }
  return isEn ? 'Sign-in failed. Please try again.' : '登入失敗，請再試。';
}

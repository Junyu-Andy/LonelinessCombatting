/// T19 (decision 0029) — sends the unblinded researcher's account straight
/// to the registration page instead of the participant App.
///
/// Reads the signed-in user's Auth custom claims once.  `role: unblinded`
/// → [EnrollmentPage]; anything else (participants, blinded staff), a
/// failure or a slow answer → [child], the normal participant App.  So a
/// participant never sees the registration entry, and the researcher does
/// not have to go through consent and onboarding on her own account.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/enrollment_service.dart';
import 'enrollment_page.dart';

class StaffGate extends StatefulWidget {
  final String uid;
  final Widget child;

  /// Injectable for tests; defaults to the current user's ID-token claims.
  final Future<Map<String, dynamic>?> Function()? loadClaims;
  final VoidCallback? onSignOut;

  const StaffGate({
    super.key,
    required this.uid,
    required this.child,
    this.loadClaims,
    this.onSignOut,
  });

  @override
  State<StaffGate> createState() => _StaffGateState();
}

Future<Map<String, dynamic>?> _currentClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final token = await user.getIdTokenResult();
  return token.claims;
}

class _StaffGateState extends State<StaffGate> {
  late Future<bool> _isUnblinded;

  @override
  void initState() {
    super.initState();
    _isUnblinded = _load();
  }

  @override
  void didUpdateWidget(StaffGate old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _isUnblinded = _load();
  }

  Future<bool> _load() async {
    try {
      final claims = await (widget.loadClaims ?? _currentClaims)()
          .timeout(const Duration(seconds: 5));
      return isUnblindedClaims(claims);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isUnblinded,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == true) {
          return EnrollmentPage(onSignOut: widget.onSignOut);
        }
        return widget.child;
      },
    );
  }
}

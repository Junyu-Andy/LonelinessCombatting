/// T19 (decision 0029) — sends the unblinded researcher's account straight
/// to the registration page instead of the participant App.
/// T30 — and a `blinded` account (the W4 outcome assessors) straight to the
/// assessor view, when `app_config/feature_flags.assessorViewEnabled` is on.
///
/// Reads the signed-in user's Auth custom claims once.  `role: unblinded`
/// → [EnrollmentPage]; `role: blinded` + switch on → [AssessorPage];
/// anything else (participants, blinded staff with the switch off), a
/// failure or a slow answer → [child], the normal participant App.  So a
/// participant never sees either staff entry, and staff accounts do not
/// go through the enrolment gate, consent or onboarding — the gate sits
/// above `EnrollmentWaitGate` in `auth_gate.dart`.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/feature_flags/remote_feature_flags.dart';
import '../../assessor/data/assessor_service.dart';
import '../../assessor/presentation/assessor_page.dart';
import '../data/enrollment_service.dart';
import 'enrollment_page.dart';

/// Where a signed-in account goes after the role is known.
enum StaffRoute { participant, enrollment, assessor }

/// Pure routing rule, unit-tested in `test/assessor_view_test.dart`.
StaffRoute staffRouteFor(Map<String, dynamic>? claims,
    {required bool assessorViewOn}) {
  if (isUnblindedClaims(claims)) return StaffRoute.enrollment;
  if (assessorViewOn && isAssessorClaims(claims)) return StaffRoute.assessor;
  return StaffRoute.participant;
}

class StaffGate extends StatefulWidget {
  final String uid;
  final Widget child;

  /// Injectable for tests; defaults to the current user's ID-token claims.
  final Future<Map<String, dynamic>?> Function()? loadClaims;
  final VoidCallback? onSignOut;

  /// T30 test hook; defaults to [RemoteFeatureFlags.current].
  final bool? assessorViewOn;

  /// T30: called once when the account is routed to a staff page.
  final Future<void> Function(String uid)? onStaffRoute;

  /// T30 test hook for the assessor view's backend.
  final AssessorBackend? assessorBackend;

  const StaffGate({
    super.key,
    required this.uid,
    required this.child,
    this.loadClaims,
    this.onSignOut,
    this.assessorViewOn,
    this.onStaffRoute,
    this.assessorBackend,
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
  late Future<StaffRoute> _route;

  @override
  void initState() {
    super.initState();
    _route = _load();
  }

  @override
  void didUpdateWidget(StaffGate old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _route = _load();
  }

  Future<StaffRoute> _load() async {
    StaffRoute route;
    try {
      final claims = await (widget.loadClaims ?? _currentClaims)()
          .timeout(const Duration(seconds: 5));
      route = staffRouteFor(claims,
          assessorViewOn: widget.assessorViewOn ??
              RemoteFeatureFlags.current.assessorViewEnabled);
    } catch (_) {
      route = StaffRoute.participant;
    }
    if (route != StaffRoute.participant) {
      try {
        await widget.onStaffRoute?.call(widget.uid);
      } catch (_) {
        // Best effort: pushes off is a nicety, the page is the point.
      }
    }
    return route;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StaffRoute>(
      future: _route,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        switch (snap.data ?? StaffRoute.participant) {
          case StaffRoute.enrollment:
            return EnrollmentPage(onSignOut: widget.onSignOut);
          case StaffRoute.assessor:
            return AssessorPage(
                backend: widget.assessorBackend, onSignOut: widget.onSignOut);
          case StaffRoute.participant:
            return widget.child;
        }
      },
    );
  }
}

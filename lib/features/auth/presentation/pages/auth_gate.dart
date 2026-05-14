import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../app/main_shell.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../consent/presentation/consent_gate.dart';
import '../../data/auth_service.dart';
import '../../data/user_profile.dart';
import 'login_page.dart';

/// Owns the routing decision: login → main shell. (Onboarding is currently
/// disabled — the original slide deck will be shown outside the app.)
///
/// Listens to [AuthService.profileChanges] so auth state changes (sign-in,
/// sign-out, token expiry) automatically swap the surface, and keeps the
/// analytics pipeline's `uid` in sync as the user signs in / out.
class AuthGate extends StatefulWidget {
  final AuthService authService;
  final AnalyticsService analytics;

  const AuthGate({
    super.key,
    required this.authService,
    required this.analytics,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid;

  @override
  Widget build(BuildContext context) {
    // Guest mode: Firebase unavailable — let the user into the main shell
    // without auth so they can still explore the demo.
    if (!widget.authService.available) {
      return const MainShell();
    }

    return StreamBuilder<UserProfile?>(
      stream: widget.authService.profileChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final profile = snapshot.data;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final settings = AppSettingsScope.read(context);
          if (settings.profile?.uid != profile?.uid) {
            settings.profile = profile;
          }
          if (_lastUid != profile?.uid) {
            final previous = _lastUid;
            _lastUid = profile?.uid;
            await widget.analytics.setUser(profile?.uid);
            if (profile != null && previous == null) {
              await widget.analytics.logAuth('signed_in');
            } else if (profile == null && previous != null) {
              await widget.analytics.logAuth('signed_out');
            }
          }
        });
        if (profile == null) {
          return LoginPage(authService: widget.authService);
        }
        return const ConsentGate(child: MainShell());
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

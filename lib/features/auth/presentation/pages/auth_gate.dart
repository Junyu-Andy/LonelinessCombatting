import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../app/main_shell.dart';
import '../../../onboarding/presentation/pages/onboarding_page.dart';
import '../../data/auth_service.dart';
import '../../data/user_profile.dart';
import 'login_page.dart';

/// Owns the routing decision: onboarding → login → main shell.
///
/// Listens to [AuthService.profileChanges] so auth state changes (sign-in,
/// sign-out, token expiry) automatically swap the surface.
class AuthGate extends StatefulWidget {
  final AuthService authService;

  const AuthGate({super.key, required this.authService});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _onboardingDone = false;

  @override
  Widget build(BuildContext context) {
    if (!_onboardingDone) {
      return OnboardingPage(
        onFinished: () => setState(() => _onboardingDone = true),
      );
    }

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
        // Keep AppSettings in sync with the latest known profile so the
        // settings page reflects the right values when it mounts.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final settings = AppSettingsScope.read(context);
          if (settings.profile?.uid != profile?.uid) {
            settings.profile = profile;
          }
        });
        if (profile == null) {
          return LoginPage(authService: widget.authService);
        }
        return const MainShell();
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

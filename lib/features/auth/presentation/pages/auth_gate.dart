import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../app/main_shell.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
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

  /// Called whenever the signed-in uid changes (sign-in, sign-out, token
  /// rotation). Used by [MyApp] to wire FCM token registration.
  final Future<void> Function(String? uid)? onAuthUidChanged;

  const AuthGate({
    super.key,
    required this.authService,
    required this.analytics,
    this.onAuthUidChanged,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid;

  @override
  Widget build(BuildContext context) {
    // Guest mode: Firebase unavailable — let the user into the main shell
    // without auth so they can still explore the demo. A persistent
    // banner makes the state visible so the tester doesn't think it's
    // a real RCT signed-in session.
    if (!widget.authService.available) {
      return const _GuestModeShell();
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
            await widget.onAuthUidChanged?.call(profile?.uid);
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
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      body: AppLoadingIndicator(
        message: isEn ? 'Just a moment…' : '等一陣…',
      ),
    );
  }
}

/// MainShell wrapped with a top banner that shows the app is running
/// without a Firebase project. Without this, a tester can't tell whether
/// they're signed in, in guest mode, or in a misconfigured build.
class _GuestModeShell extends StatelessWidget {
  const _GuestModeShell();

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    const forcedArm = String.fromEnvironment('FORCE_ARM');
    return Column(
      children: [
        Material(
          color: const Color(0xFFFEF3C7),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEn
                          ? 'Demo mode — Firebase not configured. '
                              'Sign-in, RCT arm assignment, and saving are '
                              'all disabled.'
                              '${forcedArm.isNotEmpty ? ' [FORCE_ARM=$forcedArm]' : ''}'
                          : 'Demo 模式 — Firebase 未配置。'
                              '登入、隨機分組、儲存功能都唔可用。'
                              '${forcedArm.isNotEmpty ? '【強制 ARM=$forcedArm】' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Expanded(child: MainShell()),
      ],
    );
  }
}

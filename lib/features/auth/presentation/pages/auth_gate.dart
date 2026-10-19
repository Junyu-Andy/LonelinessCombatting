import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/phase_a_config.dart';
import '../../../../core/config/phase_b_config.dart';
import '../../../../core/config/usage_copy_loader.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';

import '../../../../app/app_settings.dart';
import '../../../../app/app_settings_scope.dart';
import '../../../../app/main_shell.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../consent/presentation/consent_gate.dart';
import '../../../enrollment/presentation/enrollment_wait_gate.dart';
import '../../../enrollment/presentation/staff_gate.dart';
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

  /// T30: called when the signed-in account is research staff (the
  /// registering researcher or a W4 assessor) and is routed to a staff
  /// page.  [MyApp] uses it to keep participant pushes off that device.
  final Future<void> Function(String uid)? onStaffRoute;

  /// T40: called with every profile the auth stream emits (after the
  /// remote config was re-read on sign-in), so the usage-event recorder
  /// knows the current account and whether it is enrolled.
  final void Function(UserProfile? profile)? onProfileSeen;

  const AuthGate({
    super.key,
    required this.authService,
    required this.analytics,
    this.onAuthUidChanged,
    this.onStaffRoute,
    this.onProfileSeen,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid;

  // 10/19: ONE subscription for the life of the gate.  profileChanges() is
  // an async* generator, so calling it in build handed StreamBuilder a new
  // stream on every rebuild: it fell back to "waiting", showed the loading
  // screen and rebuilt the whole MainShell from scratch — the tab jumped
  // back to 睇今日.  The setState after the post-login config reload below
  // did exactly that about a second after signing in.
  late Stream<UserProfile?> _profiles = widget.authService.profileChanges();

  // Bumped after the post-login reload of app_config/*, so the gates below
  // re-read the switches (StaffGate re-routes, ConsentGate rebuilds)
  // without remounting the App.
  int _configRevision = 0;

  @override
  void didUpdateWidget(AuthGate old) {
    super.didUpdateWidget(old);
    if (old.authService != widget.authService) {
      _profiles = widget.authService.profileChanges();
    }
  }

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
      stream: _profiles,
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
            // B.3 — propagate arm code so every subsequent event carries it.
            widget.analytics.setEnvironment(arm: profile?.arm?.code);
            await widget.onAuthUidChanged?.call(profile?.uid);
            if (profile != null && previous == null) {
              await widget.analytics.logAuth('signed_in');
            } else if (profile == null && previous != null) {
              await widget.analytics.logAuth('signed_out');
            }
            // 10/14 fix: the startup reads of app_config/* run before anyone
            // is signed in, and the rules allow them only when signed in, so
            // on a fresh install every switch sat at its default until the
            // App was killed and reopened. Re-read once the account is known
            // and rebuild so the gates (enrolment gate, onboarding fix, …)
            // see the real values.
            if (profile != null) {
              await _reloadRemoteConfig();
              await _syncQuietHours(profile.uid, settings);
              if (mounted) setState(() => _configRevision++);
            }
          }
          widget.onProfileSeen?.call(profile);
        });
        if (profile == null) {
          return LoginPage(authService: widget.authService);
        }
        // T19: the unblinded researcher's account opens the registration
        // page; everyone else gets the participant App.  T21: with the
        // enrolment gate on, an unregistered participant (not a tester)
        // sees only the waiting page S8 — before consent and intake.
        // T30: a `blinded` assessor account opens the assessor view here,
        // before the enrolment gate, so it is never held on S8.
        return StaffGate(
          uid: profile.uid,
          configRevision: _configRevision,
          onSignOut: widget.authService.signOut,
          onStaffRoute: widget.onStaffRoute,
          child: EnrollmentWaitGate(
            profile: profile,
            // Not const on purpose: a new instance on every rebuild makes
            // ConsentGate re-read the remote switches after the reload,
            // while the const MainShell below keeps its state (tab).
            // ignore: prefer_const_constructors
            child: ConsentGate(child: const MainShell()),
          ),
        );
      },
    );
  }
}

/// Re-read every remote config document the App loaded at startup.
Future<void> _reloadRemoteConfig() async {
  try {
    await Future.wait<Object?>([
      PhaseAConfig.load(),
      RemoteFeatureFlags.load(),
      UsageCopyLoader.load(),
      PhaseBConfig.load(available: FeatureFlags.phaseB),
    ]);
  } catch (e) {
    if (kDebugMode) debugPrint('[AuthGate] remote config reload failed: $e');
  }
}

/// 10/14 fix: keep 「安靜時段」 on the phone and on the server in step.
/// The server value wins when it exists (a reinstall or a second phone
/// picks up the elder's earlier choice); when it is missing, the local
/// value is written so the push senders see the same thing the page shows.
Future<void> _syncQuietHours(String uid, AppSettings settings) async {
  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    final remote = snap.data()?['quietHoursEnabled'];
    if (remote is bool) {
      if (settings.quietHours != remote) settings.quietHours = remote;
    } else {
      await ref.set({'quietHoursEnabled': settings.quietHours},
          SetOptions(merge: true));
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[AuthGate] quiet hours sync failed: $e');
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

// 10/19 — after signing in, the first tap on 自己 bounced back to 睇今日.
// Cause: AuthGate called authService.profileChanges() (an async* stream) in
// build, so every rebuild handed StreamBuilder a NEW stream, which went back
// to "waiting", showed the loading screen and remounted the whole App.  The
// gate now subscribes once.  Synthetic, no Firebase.
import 'dart:async';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/auth/presentation/pages/auth_gate.dart';
import 'package:app_demo/features/auth/presentation/pages/login_page.dart';
import 'package:app_demo/features/enrollment/presentation/staff_gate.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed out; counts how many times the gate asks for the stream.
class _CountingAuth extends AuthService {
  _CountingAuth() : super(available: true);
  int subscriptions = 0;
  final _controller = StreamController<UserProfile?>.broadcast();

  @override
  Stream<UserProfile?> profileChanges() async* {
    subscriptions++;
    yield null;
    yield* _controller.stream;
  }
}

void main() {
  testWidgets('rebuilding the gate keeps one profile subscription and never '
      'falls back to the loading screen', (tester) async {
    final auth = _CountingAuth();
    final analytics = AnalyticsService(firebaseReady: false);
    late StateSetter rebuildParent;
    var parentBuilds = 0;

    await tester.pumpWidget(AnalyticsScope(
      analytics: analytics,
      child: AuthServiceScope(
        authService: auth,
        child: AppSettingsScope(
          settings: AppSettings(),
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: StatefulBuilder(builder: (context, setState) {
              rebuildParent = setState;
              parentBuilds++;
              return AuthGate(authService: auth, analytics: analytics);
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(auth.subscriptions, 1);

    // Rebuild the gate a few times (as the post-login reload does).
    for (var i = 0; i < 3; i++) {
      rebuildParent(() {});
      await tester.pump();
      // Never the loading screen in between: the page stays mounted.
      expect(find.byType(LoginPage), findsOneWidget);
      await tester.pumpAndSettle();
    }
    expect(parentBuilds, greaterThan(1));
    expect(auth.subscriptions, 1, reason: 'one stream for the life of the gate');
  });

  testWidgets('StaffGate re-checks on a new configRevision without taking '
      'the page down', (tester) async {
    var loads = 0;
    Future<Map<String, dynamic>?> claims() async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return null; // participant
    }

    Widget gate(int revision) => MaterialApp(
          home: StaffGate(
            uid: 'u1',
            configRevision: revision,
            loadClaims: claims,
            assessorViewOn: false,
            child: const Text('the App'),
          ),
        );

    await tester.pumpWidget(gate(0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('the App'), findsOneWidget);
    expect(loads, 1);

    await tester.pumpWidget(gate(1));
    await tester.pump(); // re-check in flight
    expect(loads, 2);
    expect(find.text('the App'), findsOneWidget, reason: 'no spinner');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('the App'), findsOneWidget);
  });
}

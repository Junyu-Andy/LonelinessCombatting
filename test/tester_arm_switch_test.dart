// Tester arm switch — 測試員工具 「切換組別（只限測試員帳號）」.
//
// Synthetic accounts, fake backend (no Firebase): the block shows only with
// the tester tools unlocked AND an isTester account; pressing a button
// calls the backend, re-reads the profile and Arm.of follows at once.
// Run with --dart-define=PHASE_B=true for the Arm.of checks (the default
// Phase A build renders Arm A for everyone).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/arm/arm_scope.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/memory/memory_mode.dart';
import 'package:app_demo/core/testing/tester_gate.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/data/tester_arm_switch.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for Firestore: the "server" copy of users/{uid}.
class _FakeServer {
  _FakeServer(this.profile);
  UserProfile profile;
}

class _FakeBackend implements TesterArmBackend {
  _FakeBackend(this.server, {this.failWith});

  final _FakeServer server;
  final String? failWith;
  final calls = <String>[];

  @override
  Future<void> setArm(String arm) async {
    calls.add(arm);
    if (failWith != null) throw TesterArmException(failWith!);
    server.profile = server.profile.copyWith(
      arm: ArmAssignment.tryParse(arm),
      cohort: server.profile.cohort ?? 'pilot',
      armAssignmentMode: 'pilot_designated',
    );
  }
}

class _FakeAuth extends AuthService {
  _FakeAuth(this.server) : super(available: true);

  final _FakeServer server;
  int reloads = 0;

  @override
  Future<UserProfile?> reloadProfile() async {
    reloads++;
    return server.profile;
  }
}

UserProfile _profile({bool tester = true, ArmAssignment? arm}) => UserProfile(
      uid: 't1',
      email: 't1@example.invalid',
      displayName: 'T1',
      isTester: tester,
      arm: arm,
    );

Future<AppSettings> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  required _FakeServer server,
  required TesterArmBackend backend,
  _FakeAuth? auth,
}) async {
  tester.view.physicalSize = const Size(1080, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettings(locale: const Locale('zh'))..profile = profile;
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: AuthServiceScope(
      authService: auth ?? _FakeAuth(server),
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Column(children: [
          Builder(
            builder: (c) => Text('arm=${Arm.of(c)?.code ?? '-'}',
                key: const Key('probe'), textDirection: TextDirection.ltr),
          ),
          Expanded(child: SettingsPage(testerArmBackend: backend)),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return settings;
}

String _probe(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('probe'))).data!;

void main() {
  setUp(() {
    TesterGate.resetForTest();
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(testerArmSwitchEnabled: true);
  });
  tearDown(() {
    TesterGate.resetForTest();
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  testWidgets('hidden until the tester tools are unlocked', (tester) async {
    final server = _FakeServer(_profile());
    await _pump(tester,
        profile: server.profile,
        server: server,
        backend: _FakeBackend(server));
    expect(find.byKey(const Key('tester_arm_switch')), findsNothing);
  });

  testWidgets('hidden for a non-tester account even when unlocked',
      (tester) async {
    TesterGate.forceUnlockForTest();
    final server = _FakeServer(_profile(tester: false));
    await _pump(tester,
        profile: server.profile,
        server: server,
        backend: _FakeBackend(server));
    expect(find.text('測試員工具'), findsOneWidget);
    expect(find.byKey(const Key('tester_arm_switch')), findsNothing);
    expect(find.text('切換組別（只限測試員帳號）'), findsNothing);
  });

  testWidgets('tester: switch to Hybrid then rule arm, Arm.of follows',
      (tester) async {
    TesterGate.forceUnlockForTest();
    final server = _FakeServer(_profile(arm: ArmAssignment.b));
    final backend = _FakeBackend(server);
    final auth = _FakeAuth(server);
    final settings = await _pump(tester,
        profile: server.profile, server: server, backend: backend, auth: auth);

    expect(find.text('切換組別（只限測試員帳號）'), findsOneWidget);
    expect(find.text('而家：規則組'), findsOneWidget);
    if (FeatureFlags.phaseB) expect(_probe(tester), 'arm=B');

    await tester.tap(find.byKey(const Key('tester_arm_a')));
    await tester.pumpAndSettle();
    expect(backend.calls, ['A']);
    expect(auth.reloads, 1);
    expect(settings.profile!.arm, ArmAssignment.a);
    expect(find.text('而家：Hybrid 組'), findsOneWidget);
    if (FeatureFlags.phaseB) {
      expect(_probe(tester), 'arm=A');
      // Same memory path as a pilot-run Hybrid elder.
      expect(MemoryModes.of(settings.profile), MemoryMode.phaseB);
    }

    await tester.tap(find.byKey(const Key('tester_arm_b')));
    await tester.pumpAndSettle();
    expect(backend.calls, ['A', 'B']);
    expect(settings.profile!.arm, ArmAssignment.b);
    expect(find.text('而家：規則組'), findsOneWidget);
    if (FeatureFlags.phaseB) {
      expect(_probe(tester), 'arm=B');
      expect(MemoryModes.of(settings.profile), MemoryMode.off);
    }
    expect(find.byKey(const Key('tester_arm_error')), findsNothing);
  });

  testWidgets('a refusal shows the reason and keeps the arm', (tester) async {
    TesterGate.forceUnlockForTest();
    final server = _FakeServer(_profile(arm: ArmAssignment.b));
    final backend = _FakeBackend(server,
        failWith: describeTesterArmError('permission-denied', null));
    final settings = await _pump(tester,
        profile: server.profile, server: server, backend: backend);
    await tester.tap(find.byKey(const Key('tester_arm_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tester_arm_error')), findsOneWidget);
    expect(find.textContaining('唔係測試員帳號'), findsOneWidget);
    expect(settings.profile!.arm, ArmAssignment.b);
    if (FeatureFlags.phaseB) expect(_probe(tester), 'arm=B');
  });

  testWidgets('switch flag off: buttons disabled, reason shown',
      (tester) async {
    TesterGate.forceUnlockForTest();
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
    final server = _FakeServer(_profile(arm: ArmAssignment.b));
    final backend = _FakeBackend(server);
    await _pump(tester,
        profile: server.profile, server: server, backend: backend);
    expect(find.textContaining('testerArmSwitchEnabled 未開'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tester_arm_a')));
    await tester.pumpAndSettle();
    expect(backend.calls, isEmpty);
  });

  test('MemoryModes: tester in A on a Phase B build = phaseB; B = off', () {
    final a = _profile(arm: ArmAssignment.a);
    expect(MemoryModes.of(a),
        FeatureFlags.phaseB ? MemoryMode.phaseB : MemoryMode.off);
    expect(MemoryModes.of(_profile(arm: ArmAssignment.b)), MemoryMode.off);
    // A participant in force_a mode is unchanged.
    expect(
        MemoryModes.of(_profile(tester: false, arm: ArmAssignment.a)
            .copyWith(armAssignmentMode: 'force_a')),
        MemoryMode.off);
  });

  test('error codes map to readable reasons', () {
    expect(describeTesterArmError('failed-precondition', null),
        contains('testerArmSwitchEnabled'));
    expect(describeTesterArmError('internal', 'x'), contains('internal'));
  });
}

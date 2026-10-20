// 1020f (Junyu 10/20) — 測試員工具:
//   - 「反饋／問卷」's PGIC tile is named like the PGIC part and its new stem;
//   - 「預覽量表」 hides the Phase A DJG-ES page in a Phase B build, leaving
//     only 「DJG W2（Phase B）」, so testers cannot open the wrong one.
// The Phase B case runs in tool/ci_flutter_tests.sh "phase B arm gating"
// (--dart-define=PHASE_B=true); the default build checks the Phase A list.
// Synthetic account, no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/testing/tester_gate.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthService {
  _FakeAuth(this.profile) : super(available: true);
  final UserProfile profile;

  @override
  Future<UserProfile?> reloadProfile() async => profile;
}

const _djgEs = 'DJG-ES（第 2 週，6 題）';
const _djgW2 = 'DJG W2（Phase B，6 題，預覽，不儲存）';

void main() {
  setUp(() {
    TesterGate.resetForTest();
    TesterGate.forceUnlockForTest();
  });
  tearDown(() {
    TesterGate.resetForTest();
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  testWidgets('PGIC tile and the DJG previews', (tester) async {
    tester.view.physicalSize = const Size(1080, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const profile = UserProfile(
      uid: 't1',
      email: 't1@example.invalid',
      displayName: 'T1',
      isTester: true,
    );
    await tester.pumpWidget(AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh'))..profile = profile,
      child: AuthServiceScope(
        authService: _FakeAuth(profile),
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SettingsPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('預覽量表'), findsOneWidget);

    // 「反饋／問卷」: the PGIC tile.
    expect(find.text('每週感受變化'), findsNothing);
    expect(find.text('過去一週，孤單感有冇變化？'), findsNothing);
    expect(find.text('同開始用之前比，孤獨感有冇變？'), findsOneWidget);

    expect(find.text(_djgW2), findsOneWidget);
    expect(find.text(_djgEs), FeatureFlags.phaseB ? findsNothing : findsOneWidget,
        reason: 'Phase A DJG-ES only outside a Phase B build');
  });
}

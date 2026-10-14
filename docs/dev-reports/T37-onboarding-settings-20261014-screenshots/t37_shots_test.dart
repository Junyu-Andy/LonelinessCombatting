// T37 screenshots (not shipped; CI does not run anything outside test/).
// Renders the two onboarding orders and the display settings with
// flutter_tester and writes PNGs next to this file:
//
//   flutter test docs/dev-reports/T37-onboarding-settings-20261014-screenshots/t37_shots_test.dart
//
// No browser is needed.  CJK text renders because the system WenQuanYi
// Zen Hei font is loaded under the family names the theme uses; on a
// machine without that file the test still passes but the text shows as
// boxes.  No Firebase, no LLM: AuthService(available: false).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/consent/presentation/consent_gate.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_wait_gate.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _font = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
final _outDir = Directory(
    'docs/dev-reports/T37-onboarding-settings-20261014-screenshots');
const _shot = Key('t37_shot');

const UserProfile _fresh =
    UserProfile(uid: 'u', email: 'e', displayName: '陳婆婆');

UserProfile _registered(UserProfile p) => p.copyWith(
      arm: ArmAssignment.b,
      armAssignmentMode: 'randomise',
      cohort: 'phase_b',
      ahJanAhBakVariant: AgentGenderVariant.masculine,
    );

UserProfile _pastIntake(UserProfile p) => p.copyWith(
      consent: p.consent.copyWith(functionalData: true),
      hasCompletedIntake: true,
    );

Future<void> _loadFonts(WidgetTester tester) async {
  final f = File(_font);
  if (!f.existsSync()) return;
  await tester.runAsync(() async {
    final bytes = await f.readAsBytes();
    for (final family in ['NotoSansHK', 'NotoSerifHK', 'Roboto']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
}

Widget _wrap(Widget home, AppSettings settings) => RepaintBoundary(
      key: _shot,
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: AppSettingsScope(
          settings: settings,
          child: AuthServiceScope(
            authService: AuthService(available: false),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: settings.highContrast
                  ? AppTheme.highContrast
                  : AppTheme.light,
              locale: const Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) {
                final base = MediaQuery.of(context);
                return MediaQuery(
                  data: base.copyWith(
                    textScaler: TextScaler.linear(
                        base.textScaler.scale(1.0) *
                            settings.fontScale.multiplier),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: home,
            ),
          ),
        ),
      ),
    );

Widget _gates({required bool gateOn}) => Builder(
      builder: (context) => EnrollmentWaitGate(
        profile: AppSettingsScope.of(context).profile,
        gateOn: gateOn,
        child: ConsentGate(
          onboardingFixOn: true,
          child: const Scaffold(body: Center(child: Text('（主頁）'))),
        ),
      ),
    );

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(_shot));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    _outDir.createSync(recursive: true);
    File('${_outDir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  testWidgets('register-first order (gate on, fix on)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _loadFonts(tester);
    UsageCopy.current = const UsageCopy({}, true); // S5 on
    final settings = AppSettings(profile: _fresh);
    await tester.pumpWidget(_wrap(_gates(gateOn: true), settings));
    await _save(tester, '1_register_first_1_waiting_S8.png');

    settings.profile = _registered(_fresh); // 登记 → 重开
    await _save(tester, '1_register_first_2_consent.png');
    await tester.tap(find.text('繼續'));
    await tester.pumpAndSettle();
    settings.profile = settings.profile!.copyWith(hasCompletedIntake: true);
    await _save(tester, '1_register_first_3_onboarding_welcome.png');
    await _next(tester);
    await _next(tester);
    await _save(tester, '1_register_first_4_pairing_preselected.png');
    await _next(tester);
    await tester.tap(find.text('飲茶／一盅兩件'));
    await _save(tester, '1_register_first_5_interests.png');
    await _next(tester);
    await _save(tester, '1_register_first_6_S5.png');
    await tester.tap(find.text('完成'));
    await _save(tester, '1_register_first_7_home.png');
    expect(settings.profile!.onboardingCompletedAt, isNotNull);
  });

  testWidgets('onboarding-first order (gate off)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _loadFonts(tester);
    final settings = AppSettings(profile: _pastIntake(_fresh));
    await tester.pumpWidget(_wrap(_gates(gateOn: false), settings));
    await _next(tester);
    await _next(tester);
    await _save(tester, '2_onboarding_first_1_pairing_unselected.png');
    await tester.tap(find.text('阿珍（同輩女性）'));
    await _save(tester, '2_onboarding_first_2_pairing_picked.png');
  });

  testWidgets('display settings persisted (特大 + 高對比, 安靜時段 off)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _loadFonts(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      AppSettings.keyFontScale: 'xLarge',
      AppSettings.keyHighContrast: true,
      AppSettings.keyQuietHours: false,
      AppSettings.keyVoiceReadback: true,
    });
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    final settings = await AppSettings.restore()
      ..profile = _pastIntake(_registered(_fresh));
    await tester.pumpWidget(_wrap(const SettingsPage(), settings));
    await _save(tester, '3_settings_restored_xlarge_contrast.png');
  });
}

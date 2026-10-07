// C20 / decision 0020: the 「保留對話紀錄」 switch is back in Settings.
// It must really turn retention off — globally and for every companion,
// since chat pages read the per-agent value first.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/privacy/transcript_retention.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What the consent page + agent onboarding write today.
const _onboarded = ConsentFlags(
  functionalData: true,
  transcriptRetention: true,
  transcriptRetentionByAgent: {
    AgentRegistry.siuYanId: true,
    AgentRegistry.ahJanAhBakId: true,
    AgentRegistry.tungTungId: true,
  },
  sharedContextUse: true,
);

UserProfile _profile([ConsentFlags consent = _onboarded]) => UserProfile(
      uid: 'u1',
      email: 'u1@example.invalid',
      displayName: 'U1',
      consent: consent,
    );

void main() {
  group('TranscriptRetention', () {
    test('default (onboarded) is on', () {
      expect(TranscriptRetention.isOn(_profile()), isTrue);
    });

    test('off turns the global flag and every companion off', () {
      final off = TranscriptRetention.set(_onboarded, false);
      expect(off.transcriptRetention, isFalse);
      for (final id in TranscriptRetention.agentIds) {
        expect(off.transcriptRetentionFor(id), isFalse, reason: id);
      }
      expect(off.sharedContextUse, isTrue, reason: 'other consent kept');
      expect(TranscriptRetention.isOn(_profile(off)), isFalse);
      final back = TranscriptRetention.set(off, true);
      expect(TranscriptRetention.isOn(_profile(back)), isTrue);
    });

    test('switched off, the summary write is skipped', () async {
      // No Firebase in tests: reaching Firestore would throw, so a clean
      // return proves the consent gate stops the write.
      final off = TranscriptRetention.set(_onboarded, false);
      await MemoryStore(available: true).writeSummary(
        uid: 'u1',
        moduleId: 'm2_check_in',
        summary: '合成內容',
        armCode: 'A',
        hasTranscriptConsent: off.transcriptRetention,
      );
    });

    test('shows off if any companion is off', () {
      final one = _onboarded.copyWith(transcriptRetentionByAgent: {
        ..._onboarded.transcriptRetentionByAgent,
        AgentRegistry.tungTungId: false,
      });
      expect(TranscriptRetention.isOn(_profile(one)), isFalse);
    });
  });

  testWidgets('Settings switch turns retention off and back on',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings(locale: const Locale('zh'))
      ..profile = _profile();
    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SettingsPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('保留對話紀錄'), findsOneWidget);
    final sw = find.descendant(
      of: find.ancestor(
          of: find.text('保留對話紀錄'), matching: find.byType(Card)),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(sw).value, isTrue, reason: 'default on');

    await tester.tap(sw);
    await tester.pumpAndSettle();
    final consent = settings.profile!.consent;
    expect(consent.transcriptRetention, isFalse);
    for (final id in TranscriptRetention.agentIds) {
      expect(consent.transcriptRetentionFor(id), isFalse, reason: id);
    }
    expect(tester.widget<Switch>(sw).value, isFalse);

    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(TranscriptRetention.isOn(settings.profile), isTrue);
  });
}

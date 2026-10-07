import 'package:flutter_test/flutter_test.dart';
import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/privacy/shared_context_consent.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';

UserProfile _profile({required bool shared}) => UserProfile(
      uid: 'u1',
      email: 'u1@example.com',
      displayName: 'U1',
      consent: ConsentFlags(
        functionalData: true,
        transcriptRetention: true,
        sharedContextUse: shared,
      ),
    );

void main() {
  const off = PhaseAConfig(enforceSharedContextConsent: false);
  const on = PhaseAConfig();

  group('C20 config defaults (decision 0020)', () {
    test('compile-time defaults', () {
      expect(on.transcriptRetentionDefault, isTrue);
      expect(on.sharedContextUseDefault, isTrue);
      expect(on.enforceSharedContextConsent, isTrue);
    });

    test('remote override merges; wrong types are ignored', () {
      final c = PhaseAConfig.fromMap({
        'transcriptRetentionDefault': false,
        'enforceSharedContextConsent': true,
        'sharedContextUseDefault': 'yes',
      });
      expect(c.transcriptRetentionDefault, isFalse);
      expect(c.enforceSharedContextConsent, isTrue);
      expect(c.sharedContextUseDefault, isTrue, reason: 'non-bool ignored');
      expect(PhaseAConfig.fromMap({}).transcriptRetentionDefault, isTrue);
    });

    test('only the consent page writes sharedContextUse', () {
      final p = _profile(shared: false);
      final consent = p.toMap()['consent'] as Map<String, dynamic>;
      expect(consent.containsKey('sharedContextUse'), isFalse,
          reason: 'a stale in-memory value must not overwrite the server');
      final withIt = p.toMap(includeSharedContextUse: true)['consent']
          as Map<String, dynamic>;
      expect(withIt['sharedContextUse'], isFalse);
      // Reading still works.
      final round = UserProfile.fromMap('u1',
          {...p.toMap(), 'consent': withIt});
      expect(round.consent.sharedContextUse, isFalse);
    });
  });

  group('SharedContextConsent', () {
    test('switch off: sharing allowed whatever the consent says', () {
      expect(
          SharedContextConsent.allowsCrossAgent(_profile(shared: false),
              config: off),
          isTrue);
      expect(
          SharedContextConsent.referralSnippet(
              _profile(shared: false), '我好掛住個孫',
              config: off),
          '我好掛住個孫');
    });

    test('switch on: only sharedContextUse == true shares', () {
      expect(
          SharedContextConsent.allowsCrossAgent(_profile(shared: true),
              config: on),
          isTrue);
      expect(
          SharedContextConsent.allowsCrossAgent(_profile(shared: false),
              config: on),
          isFalse);
      expect(SharedContextConsent.allowsCrossAgent(null, config: on), isFalse);
      expect(
          SharedContextConsent.referralSnippet(
              _profile(shared: false), '我好掛住個孫',
              config: on),
          '');
    });
  });
}

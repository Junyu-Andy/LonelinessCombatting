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
  const off = PhaseAConfig();
  const on = PhaseAConfig(enforceSharedContextConsent: true);

  group('C20 config defaults keep current behaviour', () {
    test('compile-time defaults', () {
      expect(off.transcriptRetentionDefault, isTrue);
      expect(off.sharedContextUseDefault, isFalse);
      expect(off.enforceSharedContextConsent, isFalse);
    });

    test('remote override merges; wrong types are ignored', () {
      final c = PhaseAConfig.fromMap({
        'transcriptRetentionDefault': false,
        'enforceSharedContextConsent': true,
        'sharedContextUseDefault': 'yes',
      });
      expect(c.transcriptRetentionDefault, isFalse);
      expect(c.enforceSharedContextConsent, isTrue);
      expect(c.sharedContextUseDefault, isFalse);
      expect(PhaseAConfig.fromMap({}).transcriptRetentionDefault, isTrue);
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

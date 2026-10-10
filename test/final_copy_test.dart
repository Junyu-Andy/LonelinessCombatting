// T33 — final copy in the app matches docs/spec/copy/ word for word.
//   - rule-templates.md: all 41 Arm B template replies, their mood group
//     and agent.
//   - short-texts.md: S1a (Tung Tung search-off reply), S3 (reminiscence
//     landing) and S5 (onboarding usage advice).  S2 / S4a are server-side, see
//     functions/test/final_copy_test.js.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_search_intent.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Table rows of a spec file as trimmed cells (header / rule rows kept;
/// callers match on the first cell).
List<List<String>> _rows(String file) => File('docs/spec/copy/$file')
    .readAsLinesSync()
    .where((l) => l.startsWith('| '))
    .map((l) => l
        .substring(1, l.length - 1)
        .split('|')
        .map((c) => c.trim())
        .toList())
    .toList();

const _moodBand = {
  '好開心': 'very_happy',
  '幾好': 'good',
  '一般般': 'so_so',
  '唔係幾好': 'not_good',
  '好唔開心': 'very_unhappy',
};

void main() {
  final templateRows = _rows('rule-templates.md');
  final idPattern = RegExp(r'^([XZ]\d-\d|G-1)$');
  final spec = {
    for (final r in templateRows)
      if (idPattern.hasMatch(r[0])) r[0]: r,
  };
  final pool = {for (final e in RuleReplyPool.entries) e.id: e};

  group('rule-templates.md', () {
    test('41 entries, same ids', () {
      expect(spec.length, 41);
      expect(pool.keys.toSet(), spec.keys.toSet());
    });

    test('every text is verbatim, in the right agent and mood group', () {
      for (final MapEntry(key: id, value: row) in spec.entries) {
        final e = pool[id]!;
        if (id == 'G-1') {
          expect(e.zh, row[1], reason: id);
          expect((e.agent, e.band), ('any', 'none'), reason: id);
          continue;
        }
        expect(e.zh, row[2], reason: id);
        expect(e.band, _moodBand[row[1]], reason: id);
        expect(e.agent, id.startsWith('X') ? 'siu_yan' : 'ah_jan_ah_bak',
            reason: id);
      }
    });

    test('no placeholder left, no uncorrected character', () {
      expect(RuleReplyPool.hasPlaceholders, isFalse);
      // The 「已更正的字」 table: none of the old characters remain.
      for (final old in ['侾', '傳', '諦', '゗', '捣', '鐘意']) {
        for (final e in RuleReplyPool.entries) {
          expect(e.zh.contains(old), isFalse, reason: '${e.id} $old');
        }
      }
    });
  });

  group('short-texts.md', () {
    final short = {for (final r in _rows('short-texts.md')) r[0]: r[2]};

    test('S1a: Tung Tung search-off reply', () {
      expect(TungTungSearchIntent.reply(isEn: false), short['S1a']);
      expect(TungTungSearchIntent.reply(isEn: true), short['S1a']);
    });

    test('S3: reminiscence landing count sentence', () {
      expect(ReminiscenceLandingPage.s3(4), short['S3']);
    });

    testWidgets('S3: shown on the landing page', (tester) async {
      await tester.pumpWidget(
        AppSettingsScope(
          settings: AppSettings(locale: const Locale('zh')),
          child: AuthServiceScope(
            authService: AuthService(available: false),
            child: const MaterialApp(
              locale: Locale('zh'),
              supportedLocales: [Locale('zh'), Locale('en')],
              localizationsDelegates: [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: ReminiscenceLandingPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining(short['S3']!), findsOneWidget);
      expect(find.textContaining('4 個禮拜'), findsNothing);
    });

    test('S5: onboarding usage advice', () {
      expect(UsageCopy.onboardingUsageAdviceS5, short['S5']);
    });
  });
}

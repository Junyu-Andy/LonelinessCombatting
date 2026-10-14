// T24 — the weekly bundle flow (lib/features/weekly_bundle/**): part order,
// 「第 N 部分，共 M 部分」, resume at the first unfinished part, the
// social-contact probe (S12 verbatim), PGIC-only weeks.  Fake stores, no
// Firebase, no LLM.  Both arms get this page; nothing here reads the arm.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:app_demo/features/weekly_bundle/presentation/social_contact_probe_page.dart';
import 'package:app_demo/features/weekly_bundle/presentation/weekly_bundle_flow_page.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDjgStore implements DjgW2Store {
  _FakeDjgStore([this.saved = const DjgW2Saved()]);
  DjgW2Saved saved;
  final saves = <(Map<String, String>, bool)>[];

  @override
  Future<DjgW2Saved> load() async => saved;

  @override
  Future<void> save(Map<String, String> answers,
      {required bool submit, required bool first}) async {
    saves.add((Map.of(answers), submit));
    saved = DjgW2Saved(
        status: submit ? 'submitted' : 'in_progress',
        answers: Map.of(answers),
        hasStarted: true);
  }
}

class _FakeSocialStore implements SocialContactStore {
  SocialContactSaved saved = const SocialContactSaved();
  final saves = <(Map<String, int>, bool)>[];

  @override
  Future<SocialContactSaved> load() async => saved;

  @override
  Future<void> save(Map<String, int> answers,
      {required bool submit, required bool first}) async {
    saves.add((Map.of(answers), submit));
    saved = SocialContactSaved(
        status: submit ? 'submitted' : 'in_progress',
        answers: Map.of(answers),
        hasStarted: true);
  }
}

class _FakeBundleStore implements WeeklyBundleStore {
  _FakeBundleStore(this.status);
  final Map<WeeklyPart, String?> status;
  int loads = 0;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async {
    loads++;
    return {for (final p in bundle.parts) p: status[p]};
  }
}

const _cfg = PhaseBConfig(weeklyScheduleV2Enabled: true);
const _cfgSocial =
    PhaseBConfig(weeklyScheduleV2Enabled: true, socialContactProbeEnabled: true);

WeeklyBundle _bundle(String id, {PhaseBConfig cfg = _cfg}) =>
    WeeklySchedule.bundleById(cfg, WeeklyScheduleMode.standard, id)!;

Widget _wrap(Widget home) => AnalyticsScope(
      analytics: AnalyticsService(firebaseReady: false),
      child: AppSettingsScope(
        settings: AppSettings(),
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: home,
        ),
      ),
    );

/// Tall surface so every option and button of a ListView page is built.
Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _answerDjg(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('提交'));
  await tester.pumpAndSettle();
}

String _s12Row() {
  final lines = File('docs/spec/copy/short-texts.md').readAsLinesSync();
  return lines.firstWhere((l) => l.startsWith('| S12 |'));
}

void main() {
  group('parts and order (pure)', () {
    test('W1–W3 start with DJG, W4 without, W5–W7 PGIC only', () {
      expect(_bundle('W1').parts,
          [WeeklyPart.djg, WeeklyPart.weeklyPr, WeeklyPart.pgic]);
      expect(_bundle('W4').parts, [WeeklyPart.weeklyPr, WeeklyPart.pgic]);
      expect(_bundle('W6').parts, [WeeklyPart.pgic]);
      expect(_bundle('W1', cfg: _cfgSocial).parts, [
        WeeklyPart.djg,
        WeeklyPart.weeklyPr,
        WeeklyPart.pgic,
        WeeklyPart.socialContact,
      ]);
      expect(_bundle('W5', cfg: _cfgSocial).parts, [WeeklyPart.pgic]);
    });

    test('next part = first not final; in_progress counts as open', () {
      final due = WeeklyBundleDue(
        bundle: _bundle('W1'),
        window: WeeklyWindow(DateTime(2026), DateTime(2027)),
        status: {
          WeeklyPart.djg: 'submitted',
          WeeklyPart.weeklyPr: 'in_progress',
          WeeklyPart.pgic: null,
        },
      );
      expect(due.nextPart, WeeklyPart.weeklyPr);
      expect(due.allDone, false);
      final done = WeeklyBundleDue(
        bundle: _bundle('W6'),
        window: due.window,
        status: {WeeklyPart.pgic: 'submitted'},
      );
      expect(done.allDone, true);
      expect(done.nextPart, null);
    });

    test('final-status rule per part matches the server', () {
      expect(WeeklyPartStatus.isFinal(WeeklyPart.djg, {'status': 'submitted'}), true);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.djg, {'status': 'in_progress'}), false);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.weeklyPr, {'status': 'no_referent'}), true);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.pgic, {'value': 4}), true);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.pgic, {'bundle': 'W1'}), false);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.socialContact, {'status': 'missed'}), true);
      expect(WeeklyPartStatus.isFinal(WeeklyPart.socialContact, null), false);
    });
  });

  group('S12 verbatim', () {
    test('items, options and footnote equal docs/spec/copy/short-texts.md', () {
      final row = _s12Row();
      for (final it in SocialContactItems.items) {
        expect(row.contains(it.text), true, reason: it.text);
      }
      expect(row.contains('冇／1 至 2 日／3 至 4 日／5 日或以上'), true);
      expect(SocialContactItems.options.map((o) => o.$2).join('／'),
          '冇／1 至 2 日／3 至 4 日／5 日或以上');
      expect(SocialContactItems.options.map((o) => o.$1).toList(), [0, 1, 2, 3]);
      expect(row.contains(SocialContactItems.footnote), true);
    });
  });

  group('flow page', () {
    testWidgets('week with DJG: 3 parts in order, headers 1/3 → 2/3 → 3/3, done',
        (tester) async {
      await _tall(tester);
      final djg = _FakeDjgStore();
      final store = _FakeBundleStore({});
      var noReferentCalls = 0;
      await tester.pumpWidget(_wrap(WeeklyBundleFlowPage(
        bundle: _bundle('W1'),
        store: store,
        djgStoreFor: (_) => djg,
        socialStoreFor: (_) => _FakeSocialStore(),
        referentFor: (_) async => null,
        noReferent: (_) async => noReferentCalls++,
      )));
      await tester.pumpAndSettle();
      expect(find.text('【占位】每週問卷'), findsOneWidget);
      expect(find.textContaining('一共有 3 部分'), findsOneWidget);
      expect(find.text('第 1 部分：${weeklyPartTitle(WeeklyPart.djg)}'), findsOneWidget);
      expect(find.text('第 2 部分：${weeklyPartTitle(WeeklyPart.weeklyPr)}'), findsOneWidget);
      expect(find.text('第 3 部分：${weeklyPartTitle(WeeklyPart.pgic)}'), findsOneWidget);
      expect(find.text('開始'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('weekly_start')));
      await tester.pumpAndSettle();
      // Part 1 — DJG, item 1, with the part header and the bundle title.
      expect(find.text('第 1 部分，共 3 部分'), findsOneWidget);
      expect(find.text('我有一種空虛的感覺。'), findsOneWidget);
      expect(find.text('第 2 週問卷'), findsNothing);
      await _answerDjg(tester);
      expect(djg.saves.last.$2, true); // submitted
      // Part 2 — Weekly PR: no referent → no_referent record, straight on to
      // part 3 — PGIC.
      expect(noReferentCalls, 1);
      expect(find.text('第 3 部分，共 3 部分'), findsOneWidget);
      expect(find.text('同上個星期比較，你而家覺得自己嘅孤單感整體上有冇變化？'), findsOneWidget);
      await tester.tap(find.text('冇變'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      // Back on the intro: all done.
      expect(find.text('【占位】全部做完喇，多謝你！'), findsOneWidget);
      expect(find.byKey(const ValueKey('weekly_done')), findsOneWidget);
      expect(find.text('【占位】已完成'), findsNWidgets(3));
    });

    testWidgets('resume: DJG done, Weekly PR half-way → continue opens part 2',
        (tester) async {
      await _tall(tester);
      final agent = WeeklyPrAgentUsage(
          agentId: 'siu_yan', displayName: '小欣', sessionCount: 2,
          firstUseAt: DateTime(2026, 10, 20));
      await tester.pumpWidget(_wrap(WeeklyBundleFlowPage(
        bundle: _bundle('W2'),
        store: _FakeBundleStore({
          WeeklyPart.djg: 'submitted',
          WeeklyPart.weeklyPr: 'in_progress',
        }),
        djgStoreFor: (_) => _FakeDjgStore(),
        socialStoreFor: (_) => _FakeSocialStore(),
        referentFor: (_) async => agent,
        noReferent: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('繼續'), findsOneWidget);
      expect(find.text('【占位】已完成'), findsOneWidget);
      expect(find.text('【占位】做咗一半'), findsOneWidget);
      expect(find.text('【占位】未開始'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weekly_start')));
      await tester.pumpAndSettle();
      // Straight to part 2 (Weekly PR), not the DJG.
      expect(find.text('第 2 部分，共 3 部分'), findsOneWidget);
      expect(find.text('每週夥伴評估'), findsOneWidget);
      expect(find.text('我有一種空虛的感覺。'), findsNothing);
      // Leave half-way: back on the intro, nothing marked done.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('繼續'), findsOneWidget);
      expect(find.text('【占位】已完成'), findsOneWidget);
    });

    testWidgets('DJG resumes at the first unanswered item', (tester) async {
      await _tall(tester);
      final djg = _FakeDjgStore(const DjgW2Saved(
          status: 'in_progress', answers: {'q1': 'yes', 'q2': 'no'}, hasStarted: true));
      await tester.pumpWidget(_wrap(WeeklyBundleFlowPage(
        bundle: _bundle('W3'),
        store: _FakeBundleStore({WeeklyPart.djg: 'in_progress'}),
        djgStoreFor: (_) => djg,
        socialStoreFor: (_) => _FakeSocialStore(),
        referentFor: (_) async => null,
        noReferent: (_) async {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('weekly_start')));
      await tester.pumpAndSettle();
      expect(find.text('第 3 題（共 6 題）'), findsOneWidget);
      expect(find.text('我經常覺得自己被人排斥。'), findsOneWidget);
    });

    testWidgets('social-contact switch on: 4th part, S12 screens, values 0–3',
        (tester) async {
      await _tall(tester);
      final social = _FakeSocialStore();
      await tester.pumpWidget(_wrap(WeeklyBundleFlowPage(
        bundle: _bundle('W1', cfg: _cfgSocial),
        store: _FakeBundleStore({
          WeeklyPart.djg: 'submitted',
          WeeklyPart.weeklyPr: 'no_referent',
          WeeklyPart.pgic: 'submitted',
        }),
        djgStoreFor: (_) => _FakeDjgStore(),
        socialStoreFor: (_) => social,
        referentFor: (_) async => null,
        noReferent: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('一共有 4 部分'), findsOneWidget);
      expect(find.text('第 4 部分：${weeklyPartTitle(WeeklyPart.socialContact)}'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weekly_start')));
      await tester.pumpAndSettle();
      expect(find.text('第 4 部分，共 4 部分'), findsOneWidget);
      expect(find.text(SocialContactItems.items[0].text), findsOneWidget);
      expect(find.text(SocialContactItems.footnote), findsOneWidget);
      for (final o in SocialContactItems.options) {
        expect(find.text(o.$2), findsOneWidget);
      }
      await tester.tap(find.text('3 至 4 日'));
      await tester.pumpAndSettle();
      expect(find.text(SocialContactItems.items[1].text), findsOneWidget);
      expect(find.text('第 2 題（共 2 題）'), findsOneWidget);
      // Back keeps the answer.
      await tester.tap(find.text('上一題'));
      await tester.pumpAndSettle();
      expect(find.text(SocialContactItems.items[0].text), findsOneWidget);
      await tester.tap(find.text('3 至 4 日'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('冇'));
      await tester.pumpAndSettle();
      expect(social.saves.last.$1, {'q1': 2, 'q2': 0});
      expect(social.saves.last.$2, true);
      expect(find.text('【占位】全部做完喇，多謝你！'), findsOneWidget);
    });

    testWidgets('PGIC-only week: one part, header 1/1', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(_wrap(WeeklyBundleFlowPage(
        bundle: _bundle('W6'),
        store: _FakeBundleStore({}),
        djgStoreFor: (_) => _FakeDjgStore(),
        socialStoreFor: (_) => _FakeSocialStore(),
        referentFor: (_) async => null,
        noReferent: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('一共有 1 部分'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weekly_start')));
      await tester.pumpAndSettle();
      expect(find.text('第 1 部分，共 1 部分'), findsOneWidget);
      expect(find.text('每週感受變化'), findsOneWidget);
    });

    testWidgets('stand-alone probe page: closed record shows the closed text',
        (tester) async {
      await _tall(tester);
      final social = _FakeSocialStore()
        ..saved = const SocialContactSaved(status: 'missed');
      await tester.pumpWidget(MaterialApp(
          home: SocialContactProbePage(store: social, part: (4, 4))));
      await tester.pumpAndSettle();
      expect(find.text('呢份問卷已經完成或者已經截止，唔使再答。'), findsOneWidget);
      expect(find.text('第 4 部分，共 4 部分'), findsOneWidget);
    });
  });
}

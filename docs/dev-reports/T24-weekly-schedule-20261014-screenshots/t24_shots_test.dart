// T24 screenshots (not shipped; CI does not run anything outside test/).
// Renders the weekly bundle flow with flutter_tester and writes PNGs next
// to this file:
//
//   flutter test docs/dev-reports/T24-weekly-schedule-20261014-screenshots/t24_shots_test.dart
//
// No browser is needed.  CJK text renders because the system WenQuanYi
// Zen Hei font is loaded under the family names the theme uses; on a
// machine without that file the test still passes but the text shows as
// boxes.  No Firebase, no LLM: fake stores, synthetic data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/djg_w2_page.dart';
import 'package:app_demo/features/assessment/presentation/pages/pgic_page.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:app_demo/features/weekly_bundle/presentation/social_contact_probe_page.dart';
import 'package:app_demo/features/weekly_bundle/presentation/weekly_bundle_flow_page.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/features/weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _font = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
final _outDir =
    Directory('docs/dev-reports/T24-weekly-schedule-20261014-screenshots');
const _shot = Key('t24_shot');

class _Store implements WeeklyBundleStore {
  _Store(this.status);
  final Map<WeeklyPart, String?> status;
  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle b) async =>
      {for (final p in b.parts) p: status[p]};
}

class _Djg implements DjgW2Store {
  @override
  Future<DjgW2Saved> load() async => const DjgW2Saved();
  @override
  Future<void> save(Map<String, String> a,
      {required bool submit, required bool first}) async {}
}

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

Widget _wrap(Widget home) => RepaintBoundary(
      key: _shot,
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: AppSettingsScope(
          settings: AppSettings(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: home,
          ),
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

const _cfg = PhaseBConfig(weeklyScheduleV2Enabled: true);
const _cfgSocial =
    PhaseBConfig(weeklyScheduleV2Enabled: true, socialContactProbeEnabled: true);
WeeklyBundle _b(String id, [PhaseBConfig cfg = _cfg]) =>
    WeeklySchedule.bundleById(cfg, WeeklyScheduleMode.standard, id)!;

Widget _flow(WeeklyBundle b, Map<WeeklyPart, String?> status) =>
    WeeklyBundleFlowPage(
      bundle: b,
      store: _Store(status),
      djgStoreFor: (_) => _Djg(),
      socialStoreFor: (_) => PreviewSocialContactStore(),
      referentFor: (_) async => null,
      noReferent: (_) async {},
    );

void main() {
  testWidgets('T24 screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _loadFonts(tester);

    // A. Week with DJG (W1): intro, part 1 (DJG), part 3 (PGIC).
    await tester.pumpWidget(_wrap(_flow(_b('W1'), {})));
    await _save(tester, 'A1_w1_intro_3_parts.png');
    await tester.pumpWidget(_wrap(DjgW2Page(
        store: _Djg(), part: (1, 3), title: kWeeklyBundleTitle)));
    await _save(tester, 'A2_w1_part1_djg_item1.png');
    await tester.pumpWidget(_wrap(WeeklyPrPage(
        agent: WeeklyPrAgentUsage(
            agentId: 'siu_yan',
            displayName: '小欣',
            sessionCount: 3,
            firstUseAt: DateTime(2026, 10, 20)),
        bundle: 'W1',
        part: (2, 3))));
    await _save(tester, 'A3_w1_part2_weekly_pr.png');
    await tester.pumpWidget(_wrap(const PgicPage(bundle: 'W1', part: (3, 3))));
    await _save(tester, 'A4_w1_part3_pgic.png');
    await tester.pumpWidget(_wrap(_flow(_b('W1'), {
      WeeklyPart.djg: 'submitted',
      WeeklyPart.weeklyPr: 'in_progress',
    })));
    await _save(tester, 'A5_w1_resume_half_way.png');

    // B. Week without DJG (W4): intro with 2 parts.
    await tester.pumpWidget(_wrap(_flow(_b('W4'), {})));
    await _save(tester, 'B1_w4_intro_2_parts_no_djg.png');
    await tester.pumpWidget(_wrap(const PgicPage(bundle: 'W4', part: (2, 2))));
    await _save(tester, 'B2_w4_part2_pgic.png');

    // C. PGIC-only week (W6).
    await tester.pumpWidget(_wrap(_flow(_b('W6'), {})));
    await _save(tester, 'C1_w6_intro_pgic_only.png');
    await tester.pumpWidget(_wrap(const PgicPage(bundle: 'W6', part: (1, 1))));
    await _save(tester, 'C2_w6_part1_pgic.png');

    // D. Social-contact probe on (W1, 4 parts) and its two screens (S12).
    await tester.pumpWidget(_wrap(_flow(_b('W1', _cfgSocial), {
      WeeklyPart.djg: 'submitted',
      WeeklyPart.weeklyPr: 'no_referent',
      WeeklyPart.pgic: 'submitted',
    })));
    await _save(tester, 'D1_w1_intro_4_parts_social_on.png');
    await tester.pumpWidget(_wrap(SocialContactProbePage(
        store: PreviewSocialContactStore(), part: (4, 4))));
    await _save(tester, 'D2_s12_item1.png');
    await tester.tap(find.text('3 至 4 日'));
    await _save(tester, 'D3_s12_item2.png');

    // E. All done.
    await tester.pumpWidget(_wrap(_flow(_b('W6'), {WeeklyPart.pgic: 'submitted'})));
    await _save(tester, 'E1_all_done.png');
  });
}

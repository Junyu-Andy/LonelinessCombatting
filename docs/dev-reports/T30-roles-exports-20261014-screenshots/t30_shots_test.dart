// T30 screenshots (not shipped; CI does not run anything outside test/).
// Renders the assessor view with a fake backend and writes PNGs next to
// this file:
//
//   flutter test docs/dev-reports/T30-roles-exports-20261014-screenshots/t30_shots_test.dart
//
// No Firebase: the backend is a fake with three synthetic Phase B rows.
// CJK text renders because the system WenQuanYi Zen Hei font is loaded
// under the family names the theme uses (same pattern as T37).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessor/data/assessor_service.dart';
import 'package:app_demo/features/assessor/presentation/assessor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _font = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
final _outDir =
    Directory('docs/dev-reports/T30-roles-exports-20261014-screenshots');
const _shot = Key('t30_shot');

class _FakeBackend implements AssessorBackend {
  @override
  Future<DueList> dueList() async => const DueList(
        today: '2026-11-27',
        timepoint: 'W4',
        rows: [
          DueRow(
              researchId: 'PB-001',
              windowStartDate: '2026-11-26',
              windowEndDate: '2026-12-02',
              studyDay: 26,
              windowState: 'open',
              entered: {}),
          DueRow(
              researchId: 'PB-002',
              windowStartDate: '2026-12-05',
              windowEndDate: '2026-12-11',
              studyDay: 17,
              windowState: 'before',
              entered: {}),
          DueRow(
              researchId: 'PB-003',
              windowStartDate: '2026-11-14',
              windowEndDate: '2026-11-20',
              studyDay: 38,
              windowState: 'after',
              entered: {
                'DJG-ES': EnteredSummary(
                    assessmentDate: '2026-11-27', outOfWindow: true)
              }),
        ],
      );

  @override
  Future<OutcomeEntryResult> submit(OutcomeEntryInput input) async =>
      OutcomeEntryResult(outOfWindow: false, missingItems: input.missingItems);
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

void main() {
  testWidgets('assessor view screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _loadFonts(tester);
    await tester.pumpWidget(RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: AssessorPage(
            backend: _FakeBackend(),
            onSignOut: () {},
            today: () => DateTime(2026, 11, 27)),
      ),
    ));
    await _save(tester, '1_due_list_W4.png');
    await tester.tap(find.byKey(const Key('enter_PB-001')));
    await _save(tester, '2_entry_date_mode.png');
    await tester.tap(find.byKey(const Key('entry_mode_in_person')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('entry_next')));
    await _save(tester, '3_entry_item_q1.png');
    final answers = ['yes', 'mostly', 'no', 'skipped', 'yes', 'no'];
    for (var i = 0; i < 6; i++) {
      await tester
          .tap(find.byKey(Key('entry_${DjgW2Items.items[i].id}_${answers[i]}')));
      await tester.pumpAndSettle();
    }
    await _save(tester, '4_entry_summary.png');
    await tester.tap(find.byKey(const Key('entry_submit')));
    await _save(tester, '5_confirm_1.png');
    await tester.tap(find.byKey(const Key('confirm1_ok')));
    await _save(tester, '6_confirm_2.png');
    await tester.tap(find.byKey(const Key('confirm2_ok')));
    await _save(tester, '7_recorded.png');
  });
}

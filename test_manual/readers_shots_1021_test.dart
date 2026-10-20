// 1021 小讀本 — screenshots for Junyu, both arms, phone 360 × 800 at the
// largest App text size (1.30): the 讀少少 list, and one unit's contents,
// one section and the finished contents (with the 小欣 block) inside the
// App's native top bar.  Takes whatever units are in assets/readers/.
// Not part of CI.  Run it through the script, which does three steps:
//
//   tool/readers_shots_1021.sh [unit id]      (default: the first unit)
//
//   1. this test with READER_SHOTS_STEP=prepare writes, per arm, the HTML
//      the App would load (reader_html.dart: CSP, data-chrome, data-ask
//      for Hybrid, --fs 1.30, setRead, the App's page script) and the
//      size of the WebView area under the top bar, to
//      build/readers_shots_1021/;
//   2. tool/render_reader_shots.js renders those pages in headless
//      Chromium at exactly that size (and checks every unit: no sideways
//      overflow at 1.30, the peizhu:view / back() / readIds() interface,
//      the 「?」 explain buttons hidden, nothing fetched);
//   3. this test with READER_SHOTS_STEP=frame draws the real App screens
//      with the Chromium pictures in place of the WebView, to
//      docs/dev-reports/readers-1021-shots/.
//
// The arm comes from the profile only in a Phase B build; the script
// passes the phase_b_templates defines.  Needs the WenQuanYi Zen Hei font
// (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc).  Synthetic; nothing is
// written anywhere else.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/education/data/reader_html.dart';
import 'package:app_demo/features/education/data/reader_read_marks.dart';
import 'package:app_demo/features/education/data/reader_unit.dart';
import 'package:app_demo/features/education/presentation/pages/education_library_page.dart';
import 'package:app_demo/features/education/presentation/pages/reader_page.dart';
import 'package:app_demo/features/education/presentation/reader/reader_surface.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _step = String.fromEnvironment('READER_SHOTS_STEP');
const _unitId = String.fromEnvironment('READER_SHOT_UNIT');
const _dir = '../docs/dev-reports/readers-1021-shots';
const _work = 'build/readers_shots_1021';

const _phone = Size(360, 800);
const _scale = 1.30; // AppFontScale.xLarge
const _dpr = 2.0;

/// The states drawn for one unit.
const _states = ['toc', 'section', 'done'];

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The packaged units and files, read from assets/readers/ on disk (the
/// same files the App bundles).
class _Packaged extends ReaderContentSource {
  _Packaged(this.list, this.files);
  final List<ReaderUnit> list;
  final Map<String, String> files;

  static _Packaged read() {
    final dir = Directory('assets/readers');
    final units = parseReaderManifest(
        File('${dir.path}/manifest.json').readAsStringSync());
    return _Packaged(units, {
      for (final u in units) ...{
        '${u.id}.html': File('${dir.path}/${u.id}.html').readAsStringSync(),
        '${u.id}.txt': File('${dir.path}/${u.id}.txt').readAsStringSync(),
      },
    });
  }

  @override
  Future<List<ReaderUnit>> units() async => list;

  @override
  Future<String> html(String id) async => files['$id.html']!;

  @override
  Future<String> text(String id) async => files['$id.txt']!;
}

UserProfile _profile(ArmAssignment arm) => UserProfile(
    uid: 'shots', email: 'e', displayName: '陳婆婆', arm: arm, cohort: 'phase_b');

Widget _app(Widget home, ArmAssignment arm) => AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh'), profile: _profile(arm)),
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: AnalyticsScope(
          analytics: AnalyticsService(firebaseReady: false),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(_scale)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    );

/// Step 1: keeps the request; shows nothing.
class _CaptureSurface extends ReaderSurface {
  ReaderSurfaceRequest? last;
  Size? size;

  @override
  Widget build(BuildContext context, ReaderSurfaceRequest request) {
    last = request;
    return LayoutBuilder(builder: (context, c) {
      size = c.biggest;
      return const SizedBox.expand();
    });
  }
}

/// Step 3: the Chromium picture where the WebView would be.
class _PictureSurface extends ReaderSurface {
  _PictureSurface(this.image);
  final ImageProvider image;
  ReaderSurfaceRequest? last;

  @override
  Widget build(BuildContext context, ReaderSurfaceRequest request) {
    last = request;
    return SizedBox.expand(
      child: Image(image: image, fit: BoxFit.fill, alignment: Alignment.topCenter),
    );
  }
}

String _armName(ArmAssignment arm) => arm == ArmAssignment.a ? 'hybrid' : 'rule';

Future<void> _pumpReader(WidgetTester tester, ArmAssignment arm,
    ReaderUnit unit, _Packaged source, ReaderSurface surface,
    Map<String, ReaderReadState> marks) async {
  await tester.pumpWidget(_app(
      ReaderPage(
        unit: unit,
        source: source,
        surface: surface,
        readMarks: InMemoryReaderReadMarks(marks),
      ),
      arm));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _usePhone(WidgetTester tester, {double height = 800}) {
  tester.view.physicalSize = Size(_phone.width, height) * _dpr;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late _Packaged packaged;
  late ReaderUnit unit;

  setUpAll(() {
    ChatSessionRecorder.resetProcessStateForTest();
    packaged = _Packaged.read();
    if (packaged.list.isEmpty) fail('assets/readers/ has no unit');
    unit = packaged.list.firstWhere((u) => u.id == _unitId,
        orElse: () => packaged.list.first);
  });

  setUp(() => RemoteFeatureFlags.current =
      const RemoteFeatureFlags(htmlReadersEnabled: true));
  tearDown(RemoteFeatureFlags.resetForTest);

  testWidgets('step 1: the prepared pages and the WebView size', (tester) async {
    if (!_shots || _step != 'prepare') return;
    _usePhone(tester);
    final all = {for (final s in packaged.list) s.id};
    final jobs = <Map<String, Object?>>[];
    Directory(_work).createSync(recursive: true);
    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      for (final state in _states) {
        final surface = _CaptureSurface();
        await _pumpReader(tester, arm, unit, packaged, surface, {
          if (state == 'done')
            unit.id: ReaderReadState(
                readIds: readerSectionIds(packaged.files['${unit.id}.html']!),
                total: 3),
        });
        final req = surface.last!;
        final size = surface.size!;
        final name = '${_armName(arm)}_$state';
        File('$_work/$name.html').writeAsStringSync(req.html);
        jobs.add({
          'name': name,
          'html': '$_work/$name.html',
          'png': '$_work/$name.png',
          'width': size.width,
          'height': size.height,
          'dpr': _dpr,
          if (state == 'section') 'section': readerSectionIds(
                  packaged.files['${unit.id}.html']!)
              .first,
        });
        await tester.pumpWidget(const SizedBox());
      }
      // Every unit, contents view, for the checks (no pictures kept).
      for (final u in packaged.list) {
        final surface = _CaptureSurface();
        await _pumpReader(tester, arm, u, packaged, surface, const {});
        final name = 'check_${_armName(arm)}_${u.id}';
        File('$_work/$name.html').writeAsStringSync(surface.last!.html);
        jobs.add({
          'name': name,
          'html': '$_work/$name.html',
          'width': surface.size!.width,
          'height': surface.size!.height,
          'dpr': 1.0,
          'check': true,
          'arm': _armName(arm),
          'unit': u.id,
          'sections':
              readerSectionIds(packaged.files['${u.id}.html']!).toList(),
          'units': all.toList(),
        });
        await tester.pumpWidget(const SizedBox());
      }
    }
    File('$_work/jobs.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(jobs));
  });

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    final name = _armName(arm);

    testWidgets('step 3: 讀少少 list ($name)', (tester) async {
      if (!_shots || _step != 'frame') return;
      await tester.runAsync(_loadFonts);
      // A unit read through and one read halfway, to show 「✓ 讀完」.
      final marks = InMemoryReaderReadMarks({
        packaged.list[0].id:
            const ReaderReadState(readIds: {'s1', 's2', 's3'}, total: 3),
        if (packaged.list.length > 1)
          packaged.list[1].id:
              const ReaderReadState(readIds: {'s1'}, total: 3),
      });
      for (final (file, height) in [('list', 800.0), ('list_full', 3000.0)]) {
        _usePhone(tester, height: height);
        await tester.pumpWidget(_app(
            EducationLibraryPage(
              readerSource: packaged,
              readerSurface: _CaptureSurface(),
              readMarks: marks,
            ),
            arm));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('readers_section')), findsOneWidget);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('$_dir/${file}_$name.png'));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('step 3: reader with the native top bar ($name)',
        (tester) async {
      if (!_shots || _step != 'frame') return;
      await tester.runAsync(_loadFonts);
      _usePhone(tester);
      final sections = readerSectionIds(packaged.files['${unit.id}.html']!);
      for (final state in _states) {
        final png = File('$_work/${name}_$state.png');
        if (!png.existsSync()) fail('run tool/render_reader_shots.js first');
        final image = MemoryImage(png.readAsBytesSync());
        final surface = _PictureSurface(image);
        await _pumpReader(tester, arm, unit, packaged, surface, {
          if (state == 'done')
            unit.id: ReaderReadState(readIds: sections, total: 3),
        });
        if (state == 'section') {
          surface.last!.onMessage(jsonEncode({
            'view': sections.first,
            'index': 1,
            'total': sections.length,
            'read': <String>[],
          }));
        } else {
          surface.last!.onMessage(jsonEncode({
            'view': 'toc',
            'index': 0,
            'total': sections.length,
            'read': state == 'done' ? sections.toList() : <String>[],
          }));
        }
        await tester.runAsync(() async {
          final ctx = tester.element(find.byType(Image));
          await precacheImage(image, ctx);
        });
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        expect(find.byKey(ReaderPage.askKey),
            arm == ArmAssignment.a ? findsOneWidget : findsNothing);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('$_dir/${state}_$name.png'));
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}

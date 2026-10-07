// T18 screenshot entrypoint (not shipped): renders the W2 DJG page with an
// in-memory store so Playwright can drive it in Chromium.
//
//   flutter build web --no-web-resources-cdn \
//     -t docs/dev-reports/T18-djg-w2-20261007-screenshots/t18_screens_main.dart
//   open index.html            (fresh)
//   open index.html?state=missed
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/djg_w2_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _MemStore implements DjgW2Store {
  _MemStore(this.saved);
  final DjgW2Saved saved;
  @override
  Future<DjgW2Saved> load() async => saved;
  @override
  Future<void> save(Map<String, String> answers, {required bool submit, required bool first}) async {}
}

void main() {
  final state = Uri.base.queryParameters['state'];
  final saved = state == 'missed' ? const DjgW2Saved(status: 'missed') : const DjgW2Saved();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('zh', 'HK'),
    supportedLocales: const [Locale('zh', 'HK')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(builder: (_) => DjgW2Page(store: _MemStore(saved)))),
            child: const Text('打開問卷'),
          ),
        ),
      ),
    ),
  ));
}

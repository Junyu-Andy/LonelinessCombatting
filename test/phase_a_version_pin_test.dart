/// V-1 — the generated `build_info.g.dart` must match the artefacts on
/// disk.  Recomputes `promptBundleHash` with the same recipe as
/// `tool/export_spec_inputs.py` (path + "\n" + bytes + "\n", fixed order).
/// Fails when someone edits a prompt / safety JSON / lexicon without
/// re-running the tool.
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/version/build_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _bundleOrder = [
  'functions/prompts/siu_yan_v1.txt',
  'functions/prompts/ah_jan_ah_bak_v1.txt',
  'functions/prompts/tung_tung_v1.txt',
  'docs/prompts/context_suffix_template.txt',
  'functions/prompts/safety_acknowledgements.json',
  'functions/prompts/crisis_resources.json',
  'assets/config/llm_fallback_messages.json',
];

void main() {
  test('promptBundleHash in build_info.g.dart matches the repo files', () {
    final bytes = BytesBuilder();
    for (final p in _bundleOrder) {
      final f = File(p);
      expect(f.existsSync(), true, reason: '$p missing');
      bytes.add(utf8.encode('$p\n'));
      bytes.add(f.readAsBytesSync());
      bytes.add(utf8.encode('\n'));
    }
    expect(sha256.convert(bytes.toBytes()).toString(), BuildInfo.promptBundleHash,
        reason: 'run: python3 tool/export_spec_inputs.py');
  });

  test('lexicon version pin matches the detector', () {
    expect(BuildInfo.lexiconVersion, DistressDetector.wordlistVersion);
  });

  test('app version pin matches pubspec.yaml', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)', multiLine: true).firstMatch(pub)!;
    expect(BuildInfo.appVersion, m.group(1));
    expect(BuildInfo.buildNumber, m.group(2));
  });

  test('Ah Jan prompt is rev 2026-09 and rule 9 no longer stops reminiscence',
      () {
    final p = File('functions/prompts/ah_jan_ah_bak_v1.txt').readAsStringSync();
    expect(p.split('\n').first, contains('v1 (rev 2026-09)'));
    expect(p, contains('9. **Distress 處理。**'));
    expect(p, isNot(contains('停低 reminiscence')));
  });

  test('context suffix template names the injected blocks (V-2)', () {
    final t = File('docs/prompts/context_suffix_template.txt').readAsStringSync();
    for (final marker in ['[過往摘要]', '[注意]', '[今週主題]', '[模組]']) {
      expect(t, contains(marker));
    }
  });
}

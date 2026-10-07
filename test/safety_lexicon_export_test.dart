// T10 / decision 0024: the server checks the elder's own words with the
// SAME lexicon as the App. functions/safety_lexicon.json is generated from
// DistressDetector.lexicon; this test fails when the two drift apart.
//
// Regenerate after any lexicon change:
//   UPDATE_SAFETY_LEXICON=1 flutter test test/safety_lexicon_export_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

const _path = 'functions/safety_lexicon.json';

String _export() {
  final rows = [
    for (final e in DistressDetector.lexicon)
      jsonEncode([e.$1.tierCode, e.$2.code, e.$3]),
  ];
  return '{\n'
      '  "_comment": "GENERATED from lib/core/safety/distress_detector.dart '
      'by test/safety_lexicon_export_test.dart. Do not edit by hand.",\n'
      '  "wordlistVersion": ${jsonEncode(DistressDetector.wordlistVersion)},\n'
      '  "terms": [\n    ${rows.join(',\n    ')}\n  ]\n'
      '}\n';
}

void main() {
  test('functions/safety_lexicon.json matches DistressDetector.lexicon', () {
    final want = _export();
    final file = File(_path);
    if (Platform.environment['UPDATE_SAFETY_LEXICON'] == '1') {
      file.writeAsStringSync(want);
    }
    expect(file.existsSync(), isTrue, reason: '$_path missing');
    expect(file.readAsStringSync(), want,
        reason: 'lexicon changed: regenerate with UPDATE_SAFETY_LEXICON=1');
  });

  test('shared cases give the same tier and term as the server', () {
    const detector = DistressDetector();
    final cases = (jsonDecode(
            File('test/fixtures/safety_lexicon_cases.json').readAsStringSync())
        as Map<String, dynamic>)['cases'] as List<dynamic>;
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final m = detector.analyze(c['text'] as String);
      expect(m.level.tierCode, c['tier'], reason: c['text'] as String);
      expect(m.matchedTerm, c['term'], reason: c['text'] as String);
    }
  });
}

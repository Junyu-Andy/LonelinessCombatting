// dev-tasks-1014e §2.6 (N7) — the education articles' crisis hint named
// the wrong organisation for 2382 0000: that number is 生命熱線 (Suicide
// Prevention Services); 香港撒瑪利亞防止自殺會 is 2389 2222.  The number is
// untouched (common rule 5: hotline numbers are not changed here); only
// the organisation name is corrected.
//
// 10/21 (decisions-log 133 (1)): the 15 old articles are gone, so the
// checks of their text went with them; the crisis page's own entry stays.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> numberToNameZh;
  late Map<String, String> numberToNameEn;

  setUpAll(() {
    final json = jsonDecode(File('functions/prompts/crisis_resources.json')
        .readAsStringSync()) as Map<String, dynamic>;
    numberToNameZh = {};
    numberToNameEn = {};
    for (final r in (json['resources'] as List).cast<Map<String, dynamic>>()) {
      numberToNameZh[r['number'] as String] = r['nameZh'] as String;
      numberToNameEn[r['number'] as String] = r['nameEn'] as String;
    }
  });

  test('2382 0000 is 生命熱線 on the crisis page', () {
    expect(numberToNameZh['2382 0000'], '生命熱線');
    expect(numberToNameEn['2382 0000'], 'Suicide Prevention Services');
  });
}

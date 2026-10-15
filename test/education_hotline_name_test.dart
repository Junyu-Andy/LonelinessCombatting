// dev-tasks-1014e §2.6 (N7) — the education articles' crisis hint named
// the wrong organisation for 2382 0000: that number is 生命熱線 (Suicide
// Prevention Services); 香港撒瑪利亞防止自殺會 is 2389 2222.  The number is
// untouched (common rule 5: hotline numbers are not changed here); only
// the organisation name is corrected, and every hotline named in the
// library must match the crisis page's resource list.
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/features/education/data/education_library.dart';
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

  test('no article hint pairs 撒瑪利亞 with 2382 0000; the hint names 生命熱線',
      () {
    final hints = <String>[];
    for (final a in EducationLibrary.articles) {
      if (a.crisisHintZh != null) hints.add(a.crisisHintZh!);
      if (a.crisisHintEn != null) hints.add(a.crisisHintEn!);
    }
    expect(hints, isNotEmpty);
    for (final h in hints) {
      if (h.contains('2382 0000')) {
        expect(h, isNot(contains('撒瑪利亞')), reason: h);
        expect(h, isNot(contains('Samaritans')), reason: h);
        expect(h, anyOf(contains('生命熱線'), contains('Suicide Prevention')),
            reason: h);
      }
      expect(h, isNot(contains('【占位】')));
    }
  });

  test('every hotline number in the library body text is on the crisis '
      'page with the same organisation', () {
    final re = RegExp(r'(\d{4} \d{4})');
    for (final a in EducationLibrary.articles) {
      for (final body in [a.bodyZh, a.bodyEn]) {
        for (final line in body.split('\n')) {
          final m = re.firstMatch(line);
          if (m == null) continue;
          final number = m.group(1)!;
          expect(numberToNameZh.containsKey(number), isTrue,
              reason: 'unknown hotline $number in: $line');
          final zh = numberToNameZh[number]!;
          final en = numberToNameEn[number]!;
          expect(line.contains(zh) || line.contains(en) ||
              line.contains('Samaritans Hong Kong') && zh == '撒瑪利亞會',
              isTrue, reason: '$number labelled wrongly in: $line');
        }
      }
    }
  });
}

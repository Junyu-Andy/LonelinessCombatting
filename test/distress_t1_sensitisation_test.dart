import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// T1 (Dev TestWeek) — locks the fail-safe distress wordlist additions so a
/// future edit can't silently regress them. Detection LOGIC is unchanged;
/// these only assert the new term coverage + versioning.
void main() {
  const detector = DistressDetector();

  test('wordlist is versioned', () {
    expect(DistressDetector.wordlistVersion, isNotEmpty);
  });

  test('「負累」 burden cognition escalates to moderate', () {
    expect(detector.analyze('我係個負累').level, DistressLevel.moderate);
    expect(detector.analyze('我覺得自己係個負累，拖住屋企人').level,
        DistressLevel.moderate);
  });

  group('acute fail-safe broadenings (former corpus misses)', () {
    const acutePhrases = [
      'I keep thinking about taking my own life.',
      'My only way out is dying.',
      "It's better if I'm dead.",
      "I don't see a reason to live.",
      'I have no will to live.',
      '唔想再生，希望快啲完。',
      '冇我會好過晒，唔再麻煩屋企人。',
    ];
    for (final p in acutePhrases) {
      test('"$p" → acute', () {
        expect(detector.analyze(p).level, DistressLevel.acute);
      });
    }
  });

  test('routine text still does not over-trigger (precision guard)', () {
    expect(detector.analyze('今日去咗街市買餸，遇到舊鄰居傾咗幾句。').level,
        DistressLevel.none);
    expect(detector.analyze('阿仔送咗一部新手機畀我用，我都未慣。').level,
        DistressLevel.none);
  });
}

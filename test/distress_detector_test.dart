import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = DistressDetector();

  group('DistressDetector', () {
    test('empty input is none', () {
      expect(detector.analyze('').level, DistressLevel.none);
      expect(detector.analyze('   ').level, DistressLevel.none);
    });

    test('routine content is none', () {
      expect(
        detector.analyze('今日去咗街市買餸，遇到舊鄰居傾咗幾句。').level,
        DistressLevel.none,
      );
    });

    test('flags low for loneliness language', () {
      expect(detector.analyze('我好孤獨').level, DistressLevel.low);
      expect(detector.analyze('I feel lonely today').level, DistressLevel.low);
      expect(detector.analyze('一個人坐喺屋企').level, DistressLevel.low);
    });

    test('flags moderate for burden / hopelessness / grief', () {
      expect(detector.analyze('我覺得自己係個拖累').level, DistressLevel.moderate);
      expect(detector.analyze('I feel hopeless').level, DistressLevel.moderate);
      expect(
        detector.analyze('我先生上個月剛過咗身').level,
        DistressLevel.moderate,
      );
    });

    test('flags acute for suicidal ideation', () {
      expect(detector.analyze('我想死').level, DistressLevel.acute);
      expect(
        detector.analyze("I can't go on like this").level,
        DistressLevel.acute,
      );
      expect(detector.analyze('不如死咗算').level, DistressLevel.acute);
    });

    test('returns the matched term for audit', () {
      final m = detector.analyze('我覺得好孤單');
      expect(m.level, DistressLevel.low);
      expect(m.matchedTerm, isNotNull);
    });

    test('isEscalation true for moderate and acute only', () {
      expect(detector.analyze('').isEscalation, false);
      expect(detector.analyze('我好孤獨').isEscalation, false);
      expect(detector.analyze('我係個負累').isEscalation, true);
      expect(detector.analyze('我想死').isEscalation, true);
    });
  });
}

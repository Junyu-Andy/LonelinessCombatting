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

    test('flags moderate_interrupt for burden / hopelessness', () {
      expect(detector.analyze('我覺得自己係個拖累').level,
          DistressLevel.moderateInterrupt);
      expect(detector.analyze('I feel hopeless').level,
          DistressLevel.moderateInterrupt);
    });

    test('flags moderate_review for grief / past hardship (S-1)', () {
      final grief = detector.analyze('我先生上個月剛過咗身');
      expect(grief.level, DistressLevel.moderateReview);
      expect(grief.category, DistressCategory.lossGrief);
      expect(grief.isEscalation, true);
      expect(grief.interrupts, false);
      final hard = detector.analyze('嗰陣做嘢好辛苦，成日通宵');
      expect(hard.level, DistressLevel.moderateReview);
      expect(hard.category, DistressCategory.hardship);
    });

    test('interrupt wins over review when both appear in one message', () {
      final m = detector.analyze('我老伴過咗身之後冇人理我');
      expect(m.level, DistressLevel.moderateInterrupt);
      expect(m.matchedTerm, '冇人理我');
    });

    test('S-1 split keeps the v4 term set: 19 review / 48 interrupt', () {
      expect(DistressDetector.termsFor(DistressLevel.moderateReview).length, 19);
      expect(
          DistressDetector.termsFor(DistressLevel.moderateInterrupt).length, 48);
      expect(DistressDetector.wordlistVersion, 'v5-2026-09');
    });

    test('category is populated for every tier and null for none', () {
      expect(detector.analyze('我想殺人').category, DistressCategory.harmToOthers);
      expect(detector.analyze('我個老友當年諗唔開自殺').category,
          DistressCategory.ideation);
      expect(detector.analyze('我好孤獨').category, DistressCategory.low);
      expect(detector.analyze('今日食咗蝦餃').category, isNull);
    });

    test('S-7 hopelessness family follows the configured tier', () {
      for (final t in ['我冇晒希望', '沒晒希望', '無晒希望喇', '没有希望']) {
        expect(detector.analyze(t).level, DistressDetector.hopelessnessTier);
      }
    });

    test('flags acute for suicidal ideation', () {
      // v4 D1: bare 想死 is moderate_interrupt (hyperbole); 好想死 stays acute.
      expect(detector.analyze('我想死').level, DistressLevel.moderateInterrupt);
      expect(detector.analyze('我好想死').level, DistressLevel.acute);
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
      expect(detector.analyze('我先生過咗身').isEscalation, true); // review tier
    });
  });
}

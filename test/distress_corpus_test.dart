import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// P5.4 — distress classification recall / precision test.
///
/// The corpus below is intentionally synthetic, written by the
/// engineering team to cover the keyword surface area. **Pilot
/// launch criterion** is to replace / supplement these with the
/// dissertation co-design corpus (≥200 annotated utterances, 50
/// per band) plus a cultural-advisor review pass.
///
/// Acceptance thresholds (P5.4):
///   - acute  recall  ≥ 0.95   (false negatives are the unsafe
///                              outcome — must stay close to 1.0).
///   - moderate recall ≥ 0.80
///   - none   precision ≥ 0.90 (avoid over-triggering at baseline).
///
/// When a real co-design corpus lands, the synthetic items can stay
/// alongside it — they exercise direct keyword matches that a
/// natural-language corpus may under-represent.

class _LabeledUtterance {
  final String text;
  final DistressLevel groundTruth;
  const _LabeledUtterance(this.text, this.groundTruth);
}

const _corpus = <_LabeledUtterance>[
  // -------------------- NONE (40) --------------------
  _LabeledUtterance('今日去咗街市買餸，遇到舊鄰居傾咗幾句。', DistressLevel.none),
  _LabeledUtterance('阿May琴日打電話畀我，講佢條狗最近學識識坐低。', DistressLevel.none),
  _LabeledUtterance('I made congee for breakfast and walked to the park.', DistressLevel.none),
  _LabeledUtterance('琴日去飲茶食咗蝦餃，仲遇到阿陳。', DistressLevel.none),
  _LabeledUtterance('天氣熱，我喺屋企睇電視。', DistressLevel.none),
  _LabeledUtterance('我啱啱煲咗綠豆沙，等阿仔放工返嚟一齊食。', DistressLevel.none),
  _LabeledUtterance('Watched the news this morning, then took a nap.', DistressLevel.none),
  _LabeledUtterance('阿婆教我整蘿蔔糕，今年過年自己整。', DistressLevel.none),
  _LabeledUtterance('部車死火咗，搵咗師傅嚟修。', DistressLevel.none), // tests "死火" not acute
  _LabeledUtterance('My grandson called from Canada, he\'s doing well.', DistressLevel.none),
  _LabeledUtterance('今日去拜山，攞咗啲鮮花上去。', DistressLevel.none),
  _LabeledUtterance('街市條魚好新鮮，搶住買。', DistressLevel.none),
  _LabeledUtterance('我啱啱睇完一齣戲，幾好笑。', DistressLevel.none),
  _LabeledUtterance('Reading the paper now. Tea is hot.', DistressLevel.none),
  _LabeledUtterance('阿女話下個禮拜帶埋孫過嚟食飯。', DistressLevel.none),
  _LabeledUtterance('行咗一個鐘公園，腳有啲攰但精神。', DistressLevel.none),
  _LabeledUtterance('家姐話佢識嘅張師傅退休咗，搬咗去新界住。', DistressLevel.none),
  _LabeledUtterance('My knees ached this morning so I rested.', DistressLevel.none),
  _LabeledUtterance('屋企部冷氣壞咗，又要等師傅。', DistressLevel.none),
  _LabeledUtterance('琴日去咗超市，買咗一打蛋。', DistressLevel.none),
  _LabeledUtterance('阿仔送咗一部新手機畀我用，我都未慣。', DistressLevel.none),
  _LabeledUtterance('Just watered the plants on the balcony.', DistressLevel.none),
  _LabeledUtterance('琴晚同朋友食晚飯，傾咗幾個鐘。', DistressLevel.none),
  _LabeledUtterance('而家學緊用 WhatsApp 同孫女傾偈。', DistressLevel.none),
  _LabeledUtterance('屋企樓下有個新開嘅茶餐廳，奶茶幾好飲。', DistressLevel.none),
  _LabeledUtterance('我有去飲茶會，識到幾個新朋友。', DistressLevel.none),
  _LabeledUtterance('Picked up some fruit at the market, mangoes are cheap now.', DistressLevel.none),
  _LabeledUtterance('阿仔放假帶我去咗離島睇日落。', DistressLevel.none),
  _LabeledUtterance('琴日去剪頭髮，個師傅手藝唔錯。', DistressLevel.none),
  _LabeledUtterance('My doctor says my blood pressure is okay this month.', DistressLevel.none),
  _LabeledUtterance('阿婆教緊我打麻雀，我輸晒。', DistressLevel.none),
  _LabeledUtterance('琴晚瞓得好，今朝起身精神。', DistressLevel.none),
  _LabeledUtterance('屋企個花瓶打爛咗，要去買返個。', DistressLevel.none),
  _LabeledUtterance('我啱啱整咗碟炒飯，多咗少少醬油。', DistressLevel.none),
  _LabeledUtterance('Took the bus to visit my sister this afternoon.', DistressLevel.none),
  _LabeledUtterance('琴日落雨，留咗喺屋企睇舊相簿。', DistressLevel.none),
  _LabeledUtterance('阿May話佢嫁女嗰陣好開心，講足成晚。', DistressLevel.none),
  _LabeledUtterance('我啱啱用熱水浸腳，舒服晒。', DistressLevel.none),
  _LabeledUtterance('教會有個新傳道人，講道有趣。', DistressLevel.none),
  _LabeledUtterance('Bought a new kettle today, the old one was leaking.', DistressLevel.none),

  // -------------------- LOW (50) --------------------
  _LabeledUtterance('我好孤獨', DistressLevel.low),
  _LabeledUtterance('屋企得我一個人，靜到聽到時鐘聲。', DistressLevel.low),
  _LabeledUtterance('I feel lonely today.', DistressLevel.low),
  _LabeledUtterance('成日都唔開心，又唔知做咩。', DistressLevel.low),
  _LabeledUtterance('一個人食飯總係冇胃口。', DistressLevel.low),
  _LabeledUtterance('好悶啊，個個都唔得閒。', DistressLevel.low),
  _LabeledUtterance('Feeling a bit isolated this week.', DistressLevel.low),
  _LabeledUtterance('呢排心情差，唔知點解。', DistressLevel.low),
  _LabeledUtterance('屋企空虛，連電視都唔想開。', DistressLevel.low),
  _LabeledUtterance('成日得我自己一個，冇人陪。', DistressLevel.low),
  _LabeledUtterance('No one to talk to during the day.', DistressLevel.low),
  _LabeledUtterance('呢排冇心機做嘢。', DistressLevel.low),
  _LabeledUtterance('日子有啲悶悶哋。', DistressLevel.low),
  _LabeledUtterance('感覺好失落，唔知點形容。', DistressLevel.low),
  _LabeledUtterance('I\'ve been feeling alone since my husband retired.', DistressLevel.low),
  _LabeledUtterance('成日望住個窗，發吓呆。', DistressLevel.low),
  _LabeledUtterance('心情有少少低落。', DistressLevel.low),
  _LabeledUtterance('冇精神，做咩都唔想。', DistressLevel.low),
  _LabeledUtterance('Just feeling a bit down today.', DistressLevel.low),
  _LabeledUtterance('呢個禮拜冇人打畀我。', DistressLevel.low),
  _LabeledUtterance('好耐冇朋友傾偈。', DistressLevel.low),
  _LabeledUtterance('一個人坐喺屋企，心入面空空哋。', DistressLevel.low),
  _LabeledUtterance('Feeling low after my friend moved away.', DistressLevel.low),
  _LabeledUtterance('成日諗起以前嘅朋友，而家都散晒。', DistressLevel.low),
  _LabeledUtterance('心情差，連飲茶都冇興趣。', DistressLevel.low),
  _LabeledUtterance('屋企靜到悶死。', DistressLevel.low),
  _LabeledUtterance('我覺得自己越嚟越孤單。', DistressLevel.low),
  _LabeledUtterance('I just feel empty most days.', DistressLevel.low),
  _LabeledUtterance('成日諗起阿婆，覺得寂寞。', DistressLevel.low),
  _LabeledUtterance('冇神冇氣咁，做唔到嘢。', DistressLevel.low),
  _LabeledUtterance('呢個禮拜都係一個人食飯。', DistressLevel.low),
  _LabeledUtterance('Feeling isolated since my friend stopped calling.', DistressLevel.low),
  _LabeledUtterance('屋企冇人陪我傾偈。', DistressLevel.low),
  _LabeledUtterance('成日望住電話等人打嚟。', DistressLevel.low),
  _LabeledUtterance('好悶啊，做咩都冇興趣。', DistressLevel.low),
  _LabeledUtterance('感覺自己同個世界隔咗一層。', DistressLevel.low),
  _LabeledUtterance('I miss having someone around in the evenings.', DistressLevel.low),
  _LabeledUtterance('夜晚個屋企特別靜。', DistressLevel.low),
  _LabeledUtterance('呢排心情真係唔多好。', DistressLevel.low),
  _LabeledUtterance('唔開心，又唔想搵人講。', DistressLevel.low),
  _LabeledUtterance('一個人飲茶，連茶都冇味。', DistressLevel.low),
  _LabeledUtterance('Sometimes I feel really alone here.', DistressLevel.low),
  _LabeledUtterance('成日都係自己一個人坐。', DistressLevel.low),
  _LabeledUtterance('好耐冇笑過喇。', DistressLevel.low),
  _LabeledUtterance('日子過得空虛。', DistressLevel.low),
  _LabeledUtterance('阿仔搬咗出去之後，我一個人住。', DistressLevel.low),
  _LabeledUtterance('I find myself just sitting and thinking too much.', DistressLevel.low),
  _LabeledUtterance('呢排冇咩心機。', DistressLevel.low),
  _LabeledUtterance('我覺得有少少失落。', DistressLevel.low),
  _LabeledUtterance('feeling kind of sad lately', DistressLevel.low),

  // -------------------- MODERATE (50) --------------------
  _LabeledUtterance('我覺得自己係個拖累', DistressLevel.moderate),
  _LabeledUtterance('I feel hopeless lately.', DistressLevel.moderate),
  _LabeledUtterance('我先生上個月剛過咗身', DistressLevel.moderate),
  _LabeledUtterance('阿媽剛走咗，我撐唔住。', DistressLevel.moderate),
  _LabeledUtterance('I lost my husband three weeks ago. Everything is heavy.', DistressLevel.moderate),
  _LabeledUtterance('成日覺得自己冇用。', DistressLevel.moderate),
  _LabeledUtterance('真係頂唔順喇，唔知點算。', DistressLevel.moderate),
  _LabeledUtterance('I feel like a burden to my children.', DistressLevel.moderate),
  _LabeledUtterance('我屋企人都唔關心我。', DistressLevel.moderate),
  _LabeledUtterance('阿伯走咗之後我哀傷到瞓唔到。', DistressLevel.moderate),
  _LabeledUtterance('Nobody cares whether I show up anymore.', DistressLevel.moderate),
  _LabeledUtterance('我覺得自己係個累贅，阿仔阿女都辛苦。', DistressLevel.moderate),
  _LabeledUtterance('過咗身嘅人越嚟越多，我自己又一個人。', DistressLevel.moderate),
  _LabeledUtterance('成日辛苦到唔知點算。', DistressLevel.moderate),
  _LabeledUtterance('My sister passed away last month. I keep thinking about it.', DistressLevel.moderate),
  _LabeledUtterance('我覺得絕望，連天都係灰嘅。', DistressLevel.moderate),
  _LabeledUtterance('阿婆走咗，我哀傷到食唔落飯。', DistressLevel.moderate),
  _LabeledUtterance('I just can\'t cope with him being gone.', DistressLevel.moderate),
  _LabeledUtterance('我老公剛去世，屋企空咗。', DistressLevel.moderate),
  _LabeledUtterance('成日諗起佢，悲痛到喊。', DistressLevel.moderate),
  _LabeledUtterance('呢排撐唔住，連飲茶都唔想去。', DistressLevel.moderate),
  _LabeledUtterance('I feel overwhelmed every day.', DistressLevel.moderate),
  _LabeledUtterance('屋企人都好忙，冇人理我。', DistressLevel.moderate),
  _LabeledUtterance('阿仔講話我拖累佢哋，我聽到好難受。', DistressLevel.moderate),
  _LabeledUtterance('好辛苦，唔識點同人講。', DistressLevel.moderate),
  _LabeledUtterance('I feel completely hopeless about everything.', DistressLevel.moderate),
  _LabeledUtterance('我覺得自己冇用，乜都做唔到。', DistressLevel.moderate),
  _LabeledUtterance('過世嘅朋友越嚟越多，諗起好辛苦。', DistressLevel.moderate),
  _LabeledUtterance('呢個世界冇人關心我。', DistressLevel.moderate),
  _LabeledUtterance('I\'m falling apart and nobody notices.', DistressLevel.moderate),
  _LabeledUtterance('我哀傷到瞓唔著，每晚都喊。', DistressLevel.moderate),
  _LabeledUtterance('連阿仔阿女都唔理我。', DistressLevel.moderate),
  _LabeledUtterance('我覺得自己係個負擔，唔該人哋。', DistressLevel.moderate),
  _LabeledUtterance('grieving everyday since my wife passed away', DistressLevel.moderate),
  _LabeledUtterance('屋企空咗，自從佢走咗之後。', DistressLevel.moderate),
  _LabeledUtterance('絕望啊，唔知仲可以做咩。', DistressLevel.moderate),
  _LabeledUtterance('My friend just died last week. I don\'t know what to do.', DistressLevel.moderate),
  _LabeledUtterance('我嘅老朋友剛走，諗起就喊。', DistressLevel.moderate),
  _LabeledUtterance('I can\'t cope, things are just too much.', DistressLevel.moderate),
  _LabeledUtterance('呢排頂唔順，連起身都費事。', DistressLevel.moderate),
  _LabeledUtterance('阿伯離世咗，我成日哀傷。', DistressLevel.moderate),
  _LabeledUtterance('崩潰咗，連飯都唔識煮。', DistressLevel.moderate),
  _LabeledUtterance('I feel like nobody cares if I exist.', DistressLevel.moderate),
  _LabeledUtterance('我成日覺得自己係累贅。', DistressLevel.moderate),
  _LabeledUtterance('呢個禮拜先生剛離世，唔識點過。', DistressLevel.moderate),
  _LabeledUtterance('I\'m falling apart inside.', DistressLevel.moderate),
  _LabeledUtterance('唔開心到崩到爆，唔知點傾偈。', DistressLevel.moderate),
  _LabeledUtterance('It\'s hopeless. I can\'t see a way through.', DistressLevel.moderate),
  _LabeledUtterance('我老公啱啱去世，我頂唔順。', DistressLevel.moderate),
  _LabeledUtterance('辛苦到絕望，但又唔識同人講。', DistressLevel.moderate),

  // -------------------- ACUTE (50) --------------------
  _LabeledUtterance('我想死', DistressLevel.acute),
  _LabeledUtterance("I can't go on like this", DistressLevel.acute),
  _LabeledUtterance('不如死咗算', DistressLevel.acute),
  _LabeledUtterance('I want to kill myself.', DistressLevel.acute),
  _LabeledUtterance('我想自殺', DistressLevel.acute),
  _LabeledUtterance('結束自己算撚咗。', DistressLevel.acute),
  _LabeledUtterance('There\'s no point living anymore.', DistressLevel.acute),
  _LabeledUtterance('冇咗我會好啲，唔使阿仔操心。', DistressLevel.acute),
  _LabeledUtterance('I would rather be dead.', DistressLevel.acute),
  _LabeledUtterance('我唔想再生喺呢個世界。', DistressLevel.acute),
  _LabeledUtterance('Better off dead, all of us.', DistressLevel.acute),
  _LabeledUtterance('我準備好咗，冇後路。', DistressLevel.acute),
  _LabeledUtterance('冇咗我會好過，阿仔阿女就可以正常生活。', DistressLevel.acute),
  _LabeledUtterance('I don\'t want to live anymore.', DistressLevel.acute),
  _LabeledUtterance('再活落去都冇意思。', DistressLevel.acute),
  _LabeledUtterance('我想消失，徹底消失。', DistressLevel.acute),
  _LabeledUtterance('I see no reason to live.', DistressLevel.acute),
  _LabeledUtterance('我已經冇晒希望。', DistressLevel.acute),
  _LabeledUtterance('No way out of this.', DistressLevel.acute),
  _LabeledUtterance('我唔想再生，真係冇辦法。', DistressLevel.acute),
  _LabeledUtterance('I want to end my life.', DistressLevel.acute),
  _LabeledUtterance('生存冇意義喇，我夠晒。', DistressLevel.acute),
  _LabeledUtterance('I keep thinking about taking my own life.', DistressLevel.acute),
  _LabeledUtterance('想跳樓算了。', DistressLevel.acute),
  _LabeledUtterance('I am going to end it all soon.', DistressLevel.acute),
  _LabeledUtterance('上吊都好過咁辛苦活落去。', DistressLevel.acute),
  _LabeledUtterance('I want to die. Please understand.', DistressLevel.acute),
  _LabeledUtterance('結束我嘅生命會好過呢家咁。', DistressLevel.acute),
  _LabeledUtterance('There is no reason to live anymore.', DistressLevel.acute),
  _LabeledUtterance('我想了結自己。', DistressLevel.acute),
  _LabeledUtterance('I plan to kill myself this week.', DistressLevel.acute),
  _LabeledUtterance('冇得救喇，我撐唔到。', DistressLevel.acute),
  _LabeledUtterance('Suicide feels like my only option.', DistressLevel.acute),
  _LabeledUtterance('冇路可走，唯有死。', DistressLevel.acute),
  _LabeledUtterance('I want to take my own life.', DistressLevel.acute),
  _LabeledUtterance('我覺得想消失，永遠咁消失。', DistressLevel.acute),
  _LabeledUtterance('My only way out is dying.', DistressLevel.acute),
  _LabeledUtterance('冇我嘅世界會好啲。', DistressLevel.acute),
  _LabeledUtterance('I can\'t go on living like this.', DistressLevel.acute),
  _LabeledUtterance('再活落去冇意思，唔係咩。', DistressLevel.acute),
  _LabeledUtterance("It's better if I'm dead.", DistressLevel.acute),
  _LabeledUtterance('我想了結生命，呢個世界冇我嘅位。', DistressLevel.acute),
  _LabeledUtterance('I don\'t see a reason to live.', DistressLevel.acute),
  _LabeledUtterance('消失咗就好，唔再煩人。', DistressLevel.acute),
  _LabeledUtterance('I have no will to live.', DistressLevel.acute),
  _LabeledUtterance('唔想再生，希望快啲完。', DistressLevel.acute),
  _LabeledUtterance('Going to take my own life soon.', DistressLevel.acute),
  _LabeledUtterance('我計劃好咗結束自己。', DistressLevel.acute),
  _LabeledUtterance('Better if I just kill myself.', DistressLevel.acute),
  _LabeledUtterance('冇我會好過晒，唔再麻煩屋企人。', DistressLevel.acute),
];

void main() {
  const detector = DistressDetector();

  group('DistressDetector — labeled corpus (P5.4)', () {
    test('acute recall ≥ 0.95', () {
      final acute =
          _corpus.where((c) => c.groundTruth == DistressLevel.acute).toList();
      var tp = 0;
      final misses = <String>[];
      for (final c in acute) {
        if (detector.analyze(c.text).level == DistressLevel.acute) {
          tp++;
        } else {
          misses.add(c.text);
        }
      }
      final recall = tp / acute.length;
      // Print confusion info for the dissertation methods chapter.
      // ignore: avoid_print
      print('acute recall: ${recall.toStringAsFixed(3)}  '
          '(${tp}/${acute.length}; ${misses.length} miss)');
      if (misses.isNotEmpty) {
        // ignore: avoid_print
        print('acute misses:\n  - ${misses.join("\n  - ")}');
      }
      expect(recall, greaterThanOrEqualTo(0.95));
    });

    test('moderate recall ≥ 0.80 (informational, excludes acute escalations)',
        () {
      final moderate = _corpus
          .where((c) => c.groundTruth == DistressLevel.moderate)
          .toList();
      var tp = 0;
      var acuteEscalation = 0;
      for (final c in moderate) {
        final lvl = detector.analyze(c.text).level;
        if (lvl == DistressLevel.moderate) {
          tp++;
        } else if (lvl == DistressLevel.acute) {
          // Escalation to acute is safe in the "miss" direction —
          // count it separately so we can report it.
          acuteEscalation++;
        }
      }
      final recall = tp / moderate.length;
      // ignore: avoid_print
      print('moderate recall: ${recall.toStringAsFixed(3)}  '
          '(${tp}/${moderate.length}; '
          '$acuteEscalation escalated to acute)');
      expect(recall, greaterThanOrEqualTo(0.80));
    });

    test('none precision ≥ 0.90 (no false escalations on routine text)', () {
      final none =
          _corpus.where((c) => c.groundTruth == DistressLevel.none).toList();
      var tp = 0;
      final falsePositives = <String>[];
      for (final c in none) {
        final lvl = detector.analyze(c.text).level;
        if (lvl == DistressLevel.none) {
          tp++;
        } else {
          falsePositives.add('${c.text} → ${lvl.name}');
        }
      }
      final precision = tp / none.length;
      // ignore: avoid_print
      print('none precision: ${precision.toStringAsFixed(3)}  '
          '(${tp}/${none.length})');
      if (falsePositives.isNotEmpty) {
        // ignore: avoid_print
        print('none false positives:\n  - ${falsePositives.join("\n  - ")}');
      }
      expect(precision, greaterThanOrEqualTo(0.90));
    });

    test('confusion matrix printout (informational only)', () {
      // ignore: avoid_print
      print('\n--- Confusion matrix (rows = ground truth) ---');
      for (final truth in DistressLevel.values) {
        final items =
            _corpus.where((c) => c.groundTruth == truth).toList();
        final counts = <DistressLevel, int>{
          for (final l in DistressLevel.values) l: 0,
        };
        for (final c in items) {
          counts[detector.analyze(c.text).level] =
              (counts[detector.analyze(c.text).level] ?? 0) + 1;
        }
        // ignore: avoid_print
        print('  ${truth.name.padRight(10)} '
            '→ none=${counts[DistressLevel.none]}  '
            'low=${counts[DistressLevel.low]}  '
            'mod=${counts[DistressLevel.moderate]}  '
            'acute=${counts[DistressLevel.acute]}');
      }
    });
  });
}

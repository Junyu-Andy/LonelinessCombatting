// 10/18 — UI 扫一遍：这次批次（#108–#119）动过的老人页面，在四种手机宽度
// （320 / 360 / 375 / 390 逻辑像素，对应 iPhone 放大显示、小安卓、iPhone SE、
// iPhone 14）和两档字体（1.0 和 1.3 = App 的封顶，见 app.dart：手机系统字体 ×
// App「字號」合起来最多 1.3 倍）下渲染并做基本交互。
//
// 任何 RenderFlex 溢出、断言或异常都会让那个用例失败（错误收集后一次列出）。
// 带 --dart-define=SWEEP_SHOTS=true --update-goldens 运行时，每个画面另存一张
// PNG 到 test_manual/_sweep_shots/（本机看，不入库），并尽量用一套 CJK 字体渲染。
//
// 放在 test_manual/ 而不是 test/：`flutter test` 不带路径只跑 test/，所以
// CI 的「phase A (default build)」那套不会碰它；两套 Phase B 构建
// （tool/ci_flutter_tests.sh）按路径跑它，约一分钟。没装 CJK 字体时测试用
// 默认字体（每个字一样宽，数字和标点比真字体宽），所以这里比真机更挤。
//
//   flutter test --dart-define=PHASE_B=true test_manual/ui_text_scale_sweep_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test_manual/ui_text_scale_sweep_test.dart
//
// 只用合成数据：所有服务 available false，LLM 是假的。
// 不在 test/ 下，分析器会把 @visibleForTesting 的调用当成误用；这份就是测试。
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: invalid_use_of_protected_member

import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/testing/tester_gate.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_a_page.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_b_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/auth/presentation/pages/login_page.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_shared.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/education/data/education_library.dart';
import 'package:app_demo/features/education/presentation/pages/education_article_page.dart';
import 'package:app_demo/features/memory/presentation/pages/remembered_page.dart';
import 'package:app_demo/features/onboarding/data/intake_repository.dart';
import 'package:app_demo/features/onboarding/data/intake_response.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:app_demo/features/onboarding/presentation/pages/intake_people_page.dart';
import 'package:app_demo/features/onboarding/presentation/pages/intake_short_page.dart';
import 'package:app_demo/features/personalization/presentation/pages/personalization_page.dart';
import 'package:app_demo/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:app_demo/features/settings/data/tester_arm_switch.dart';
import 'package:app_demo/features/settings/presentation/pages/faq_page.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/features/settings/presentation/widgets/tester_arm_switch_card.dart';
import 'package:app_demo/features/today/data/mood_recorder.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _armB = String.fromEnvironment('FORCE_ARM') == 'B';
const _shots = bool.fromEnvironment('SWEEP_SHOTS');

/// Debug aid: leave the framework's own error reporting on (full details).
const _raw = bool.fromEnvironment('SWEEP_RAW');

/// Logical widths and the matching heights of common phones.
const _sizes = <Size>[
  Size(320, 568), // iPhone with Display Zoom / iPhone SE (1st)
  Size(360, 780), // small Android
  Size(375, 667), // iPhone SE (2nd/3rd)
  Size(390, 844), // iPhone 14
];

/// 1.0 and the App's cap (AppFontScale.xLarge): system × App never exceeds it.
const _scales = <double>[1.0, 1.3];

const _reply =
    '好呀，同我講多啲。你頭先講嗰件事我記住咗，不如慢慢講下當時係點樣，發生咗啲乜嘢，你自己覺得點？';

class _Llm implements LlmClient {
  @override
  Future<LlmRawResponse> complete({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
    bool regenerate = false,
    Map<String, dynamic>? agentContextSnapshot,
  }) async =>
      const LlmRawResponse(text: _reply);
}

class _MemRepo extends IntakeRepository {
  @override
  Future<void> save(String uid, IntakeResponse response) async {}

  @override
  Future<void> savePeople(String uid,
      {required List<PersonEntry> important,
      required List<PersonEntry> reconnect}) async {}
}

/// No mood today and none before: the check-in page shows its mood gate.
class _NoMoodYet extends MoodRecorder {
  @override
  Future<MoodEntry?> latestForDate(
          {required String uid, required String dateIso}) async =>
      null;

  @override
  Future<MoodEntry?> mostRecent({required String uid}) async => null;
}

/// Synthetic memory for the 「我記得嘅嘢」 page: eight facts over four
/// categories and three past chats over two days.
class _SyntheticMemory extends MemoryV1Service {
  const _SyntheticMemory();

  @override
  Stream<List<MemoryItem>> watch(String uid, MemoryLayer layer) {
    final today = DateTime.now();
    String key(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
    switch (layer) {
      case MemoryLayer.fact:
        return Stream.value([
          for (var i = 0; i < 4; i++)
            MemoryItem(
                id: 'f$i', layer: layer, agentId: 'siu_yan',
                title: '家人 $i', body: '阿明係你個仔，住喺沙田',
                category: 'family'),
          const MemoryItem(
              id: 'h1', layer: MemoryLayer.fact, agentId: 'tung_tung',
              title: '鍾意', body: '飲早茶', category: 'hobby'),
          const MemoryItem(
              id: 'l1', layer: MemoryLayer.fact, agentId: 'siu_yan',
              title: '住', body: '深水埗', category: 'living'),
          const MemoryItem(
              id: 'x1', layer: MemoryLayer.fact, agentId: 'ah_jan_ah_bak',
              title: '細個', body: '喺唐樓長大', category: 'story'),
          const MemoryItem(
              id: 'u1', layer: MemoryLayer.fact, agentId: 'siu_yan',
              title: '未知', body: '類目冇寫'),
        ]);
      case MemoryLayer.followup:
        return Stream.value(const []);
      case MemoryLayer.summary:
        return Stream.value([
          MemoryItem(
              id: 's1', layer: layer, agentId: 'siu_yan',
              title: key(today), body: '今日講咗去公園行咗一陣，心情幾好。'),
          MemoryItem(
              id: 's2', layer: layer, agentId: 'tung_tung',
              title: key(today), body: '同通通傾咗飲茶同打牌。'),
          MemoryItem(
              id: 's3', layer: layer, agentId: 'ah_jan_ah_bak',
              title: key(today.subtract(const Duration(days: 1))),
              body: '講返細個喺唐樓嘅日子。'),
        ]);
    }
  }
}

class _TesterBackend implements TesterArmBackend {
  @override
  Future<void> setArm(String arm) async {}
}

UserProfile _profile({List<String>? interests, bool tester = false}) =>
    UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: _armB ? ArmAssignment.b : ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      cohort: 'pilot',
      isTester: tester,
      hasCompletedIntake: true,
      ahJanAhBakVariant: AgentGenderVariant.feminine,
      consent: const ConsentFlags(
        functionalData: true,
        transcriptRetention: true,
      ),
      interests: interests ?? const ['yum_cha', 'mahjong', 'hiking', 'news'],
      avoidTopics: '病',
      closeContacts: const [
        CloseContact(name: '阿明', relation: '仔', share: true),
        CloseContact(name: '陳太', relation: '鄰居', share: true),
      ],
      reconnectContacts: const [
        CloseContact(name: '芳姐', relation: '舊同事', share: true),
      ],
      firstIntroSeen: {
        'siu_yan': DateTime(2026, 10, 1),
        'ah_jan_ah_bak': DateTime(2026, 10, 1),
        'tung_tung': DateTime(2026, 10, 1),
      },
    );

bool _fontLoaded = false;

Future<void> _loadCjkFont() async {
  if (!_shots || _fontLoaded) return;
  final f = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  for (final family in ['WQY', 'NotoSerifHK', 'NotoSansHK']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  _fontLoaded = true;
}

class _Ctx {
  _Ctx(this.tester, this.size, this.scale, this.navKey);
  final WidgetTester tester;
  final Size size;
  final double scale;
  final GlobalKey<NavigatorState> navKey;
  final errors = <String>[];

  String get tag => 'w${size.width.toInt()}_s$scale';

  Future<void> shot(String name) async {
    if (!_shots) return;
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('_sweep_shots/${name}_$tag.png'));
  }
}

Widget _shell(_Ctx c, {required Widget home, UserProfile? profile,
    AuthService? auth}) {
  final llm = LlmGateway(client: _Llm());
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  var theme = AppTheme.light;
  if (_fontLoaded) {
    theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'WQY'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'WQY'));
  }
  return AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: profile ?? _profile()),
    child: AuthServiceScope(
      authService: auth ?? AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: CoreServicesScope(
          llm: llm,
          memory: memory,
          distress: const DistressDetector(),
          distressState: state,
          distressRouter: DistressRouter(state: state),
          crossModuleMemory: CrossModuleMemoryService(
            memory: memory,
            firestoreAvailable: false,
          ),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
            agentContext: agentContext,
            sharedContext: sharedContext,
          ),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          memoryV1: const MemoryV1Service(),
          child: MaterialApp(
            navigatorKey: c.navKey,
            theme: theme,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            // Same wrapper as app.dart: the combined (capped) text scale.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(c.scale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          ),
        ),
      ),
    ),
  );
}

/// Pump [home] as the app's root (pages that must not be popped).
Future<void> _pumpHome(_Ctx c, Widget home,
    {UserProfile? profile, AuthService? auth}) async {
  await c.tester.pumpWidget(_shell(c, home: home, profile: profile, auth: auth));
  await c.tester.pumpAndSettle();
}

/// Push [page] on top of a trivial home (pages that pop themselves).
Future<void> _pushPage(_Ctx c, Widget page, {UserProfile? profile}) async {
  await c.tester.pumpWidget(_shell(c,
      home: const Scaffold(body: Center(child: Text('home'))),
      profile: profile));
  await c.tester.pumpAndSettle();
  c.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await c.tester.pumpAndSettle();
}

/// Tap the first match if there is one; scroll it into view first.
Future<bool> _tap(_Ctx c, Finder f) async {
  if (f.evaluate().isEmpty) return false;
  final t = c.tester;
  try {
    await t.ensureVisible(f.first);
  } catch (_) {}
  await t.pumpAndSettle();
  await t.tap(f.first, warnIfMissed: false);
  await t.pumpAndSettle();
  return true;
}

/// Scroll a lazy list until [f] is built, forwards first, then back up.
Future<void> _scrollInto(_Ctx c, Finder f) async {
  if (f.evaluate().isNotEmpty) {
    await c.tester.ensureVisible(f.first);
    await c.tester.pumpAndSettle();
    return;
  }
  final list = find.byType(Scrollable).first;
  try {
    await c.tester.scrollUntilVisible(f, 150, scrollable: list);
  } catch (_) {
    await c.tester.scrollUntilVisible(f, -150, scrollable: list);
  }
  await c.tester.pumpAndSettle();
}

/// Like [_tap] but for a widget that may not be built yet (lazy lists).
Future<bool> _scrollTap(_Ctx c, Finder f) async {
  final t = c.tester;
  if (f.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
    try {
      await t.scrollUntilVisible(f, 150,
          scrollable: find.byType(Scrollable).first);
    } catch (_) {}
  }
  return _tap(c, f);
}

Future<void> _dismissIntro(_Ctx c) async {
  await _tap(c, find.text('好，開始'));
}

Future<void> _send(_Ctx c, String text) async {
  final t = c.tester;
  final field = find.byType(TextField);
  if (field.evaluate().isEmpty) return;
  await t.enterText(field.first, text);
  await t.pumpAndSettle();
  await _tap(c, find.byIcon(Icons.arrow_upward_rounded));
  await t.pump(const Duration(seconds: 1));
  await t.pumpAndSettle();
}

Future<void> _back(_Ctx c) async {
  await c.tester.binding.handlePopRoute();
  await c.tester.pumpAndSettle();
}

/// The reply bubble uses the width it was given (10/16: 0.88 of the screen).
void _expectWideBubble(_Ctx c, String text) {
  final f = find.textContaining(text.substring(0, 8));
  if (f.evaluate().isEmpty) return;
  final w = c.tester.getSize(f.first).width;
  expect(w, lessThanOrEqualTo(c.size.width * 0.88 + 1),
      reason: 'bubble text no wider than 88% of the screen');
  expect(w, greaterThan(c.size.width * 0.5),
      reason: 'bubble text uses the width (not squeezed)');
}

typedef _Flow = Future<void> Function(_Ctx c);

final _flows = <String, _Flow>{
  '注册页（建立帳號）': (c) async {
    final auth = AuthService(available: false);
    await _pumpHome(c, LoginPage(authService: auth), auth: auth);
    await c.shot('login');
    await _scrollTap(c, find.text('未有帳號？建立一個'));
    await c.shot('login_signup');
    await _scrollTap(c, find.byKey(const Key('login_show_password')));
    await c.shot('login_signup_eye');
    expect(find.byType(TextFormField), findsNWidgets(7));
  },
  '入组五题（开关关，一题一屏）': (c) async {
    await _pumpHome(c, IntakeShortPage(onComplete: () {}, repository: _MemRepo()));
    for (var i = 0; i < 5; i++) {
      await c.shot('intake_short_$i');
      await _scrollTap(c, find.byKey(const Key('intake_short_person_add')));
      if (!await _scrollTap(c, find.text(IntakeShortCopy.next))) {
        await _scrollTap(c, find.text(IntakeShortCopy.done));
      }
    }
  },
  '乙部两页：重要嘅人 / 想重新聯絡嘅人': (c) async {
    await _pumpHome(c, IntakePeoplePage(onComplete: () {}, repository: _MemRepo()));
    await c.shot('intake_people');
    for (var i = 0; i < 12; i++) {
      if (!await _scrollTap(
          c, find.byKey(const Key('intake_people_add_important')))) {
        break;
      }
    }
    expect(find.byKey(const Key('intake_people_add_important')), findsNothing,
        reason: 'the add button goes away at 10 rows');
    await c.shot('intake_people_10');
    await _scrollTap(c, find.byKey(const Key('intake_people_done')));
  },
  '介紹三個夥伴（通通一页有兴趣按钮）': (c) async {
    await _pumpHome(c, const AgentOnboardingPage(researcherIntakeOn: false),
        profile: _profile(interests: const []));
    for (var i = 0; i < 4; i++) {
      await c.shot('onboarding_$i');
      if (!await _scrollTap(c, find.text('下一步'))) break;
    }
    await c.shot('onboarding_last');
    await _scrollTap(c, find.text('完成'));
  },
  '通通（兴趣按钮 + 气泡）': (c) async {
    await _pumpHome(c, const TungTungPage());
    await _dismissIntro(c);
    await c.shot('tung_open');
    await _tap(c, find.byKey(const Key('tung_interest_shuffle')));
    await _send(c, '我今日飲咗早茶');
    await c.shot('tung_chat');
    if (!_armB) _expectWideBubble(c, _reply);
  },
  '小欣签到页（先揀心情嗰屏）': (c) async {
    // 10/19 field test: the mood gate overflowed on a short screen × large
    // font and 開始傾偈 was off the bottom.  Pick a face, start, back.
    await _pushPage(c, CheckInArmA(moodRecorder: _NoMoodYet()));
    await c.shot('checkin_gate');
    await _tap(c, find.descendant(
        of: find.byType(MoodFacePicker), matching: find.byType(InkWell)));
    await _scrollTap(c, find.byKey(const Key('check_in_mood_gate_start')));
    await _dismissIntro(c);
    await c.shot('checkin_after_gate');
    expect(find.byType(TextField), findsWidgets,
        reason: 'the chat opened after the gate');
    await _back(c);
  },
  '小欣签到页': (c) async {
    await _pushPage(c, const CheckInArmA(initialMoodValue: 4));
    await _dismissIntro(c);
    await c.shot('checkin_open');
    await _send(c, '今日幾好，去咗公園行下');
    await c.shot('checkin_chat');
    if (!_armB) _expectWideBubble(c, _reply);
    await _back(c);
  },
  '规则组签到表格（首页带心情进来）': (c) async {
    // 10/19: homeMoodOpensCheckInEnabled opens the rule-arm form with the
    // face chosen.  Hybrid builds render the page too (no arm gate here).
    await _pushPage(c, const CheckInArmB(initialMoodValue: 3));
    final picker = c.tester.widget<MoodFacePicker>(find.byType(MoodFacePicker));
    expect(picker.value, MoodFace.values[2], reason: 'face 3 pre-chosen');
    await c.shot('checkin_b_prefilled');
    await _back(c);
  },
  '阿珍／阿伯回忆页': (c) async {
    await _pushPage(c, ReminiscenceArmAPage(theme: ReminiscenceTheme.all.first));
    await _dismissIntro(c);
    await c.shot('reminiscence_open');
    await _send(c, '細個住喺深水埗');
    await c.shot('reminiscence_chat');
    await _back(c);
  },
  '阿珍／阿伯自由对话页': (c) async {
    await _pushPage(c, const ReflectiveDialoguePage());
    await _dismissIntro(c);
    await c.shot('reflective_open');
    await _send(c, '最近成日諗起以前嘅事');
    await c.shot('reflective_chat');
    await _back(c);
  },
  '行动计划（同邊個 有人名按钮）': (c) async {
    await _pushPage(
        c, _armB ? const ActionLoopArmBPage() : const ActionLoopArmAPage());
    await c.shot('action_0');
    if (_armB) {
      // One page with every picker; the names are plain list entries
      // (lazy list: scroll the 同邊個 picker into view first).
      await _scrollTap(c, find.textContaining('芳姐'));
      expect(find.textContaining('芳姐'), findsWidgets,
          reason: '想重新聯絡嘅人 shows among the quick picks');
    } else {
      // Step pages: 做乜 → 幾時 → 邊度 → 同邊個 (each needs an answer).
      for (final answer in ['去飲茶', '聽日朝早', '樓下茶樓']) {
        await c.tester.enterText(find.byType(TextField).first, answer);
        await c.tester.pumpAndSettle();
        await _scrollTap(c, find.text('下一步'));
      }
      expect(find.byKey(const Key('plan_contact_芳姐')), findsOneWidget,
          reason: '想重新聯絡嘅人 shows among the quick picks');
      expect(find.byKey(const Key('plan_contact_阿明')), findsOneWidget);
    }
    await c.shot('action_who');
    await _back(c);
  },
  '常見問題': (c) async {
    await _pumpHome(c, const FaqPage());
    await c.shot('faq_top');
    await c.tester.fling(find.byType(Scrollable).first, const Offset(0, -2000), 3000);
    await c.tester.pumpAndSettle();
    await c.shot('faq_bottom');
    expect(find.textContaining('英文'), findsNothing);
    expect(find.textContaining('English'), findsNothing);
  },
  '個人化設定': (c) async {
    await _pumpHome(c, const PersonalizationPage());
    await c.shot('personalization');
  },
  '設定頁（測試員工具卡）': (c) async {
    TesterGate.forceUnlockForTest();
    addTearDown(TesterGate.lock);
    await _pumpHome(c, SettingsPage(testerArmBackend: _TesterBackend()),
        profile: _profile(tester: true));
    await c.shot('settings_top');
    await _scrollTap(c, find.byType(TesterArmSwitchCard));
    await c.shot('settings_tester_card');
  },
  '我記得嘅嘢（分組）': (c) async {
    // 10/19 (Junyu): facts by category, past chats by day, a count line.
    if (_armB) return;
    await _pumpHome(c, const RememberedPage(service: _SyntheticMemory()));
    expect(find.textContaining('記住咗 8 件關於你嘅嘢、3 次傾偈'), findsOneWidget);
    await c.shot('remembered_grouped');
    // Lazy list: scroll each group header into view before looking.
    for (final label in ['家人（4）', '興趣（1）', '其他（1）', '今日（2）', '昨日（1）']) {
      await _scrollInto(c, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The long 家人 group is folded; open it (tap the tile, not the text,
    // so a header sitting half under the app bar still registers).
    final header = find.text('家人（4）');
    await _scrollInto(c, header);
    await c.tester.tap(find.ancestor(
        of: header, matching: find.byType(ExpansionTile)));
    await c.tester.pumpAndSettle();
    final child = find.textContaining('阿明係你個仔');
    await _scrollInto(c, child);
    expect(child, findsWidgets);
    await c.shot('remembered_family_open');
  },
  '健康資訊文章页': (c) async {
    await _pushPage(
        c, EducationArticlePage(article: EducationLibrary.articles.first));
    await c.shot('education_open');
    await _send(c, '呢篇講乜嘢？');
    await c.shot('education_chat');
    await _back(c);
  },
};

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedStore;

  setUpAll(() async {
    SessionCloseHint.claimFirstUse();
    await _loadCjkFont();
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedStore;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  for (final size in _sizes) {
    for (final scale in _scales) {
      group('${size.width.toInt()}×${size.height.toInt()} × 字体 $scale', () {
        for (final entry in _flows.entries) {
          testWidgets(entry.key, (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (call) async => ['wifi'],
            );
            final c = _Ctx(tester, size, scale, GlobalKey<NavigatorState>());
            // Collect every framework error (overflow included) and list
            // them together instead of stopping at the first.
            final old = FlutterError.onError;
            void collect(FlutterErrorDetails d) {
              final line = d.exceptionAsString().split('\n').first;
              // Plugin stubs (connectivity stream etc.) are not UI problems.
              if (line.contains('MissingPluginException')) return;
              // Keep the widget location so the report says which Row.
              final m = RegExp(r'file:///\S+?\.dart:\d+:\d+')
                  .firstMatch(d.toString());
              final where = m == null ? '' : m.group(0)!.split('/lib/').last;
              c.errors.add(where.isEmpty ? line : '$line  (lib/$where)');
            }

            if (!_raw) FlutterError.onError = collect;
            try {
              await entry.value(c);
            } finally {
              FlutterError.onError = old;
            }
            expect(c.errors, isEmpty,
                reason: '${entry.key} @ ${c.tag}: ${c.errors.join(' | ')}');
          });
        }
      });
    }
  }
}

// T17b screenshot entrypoint (not shipped): ADA v1.0, the day-7 flow, the
// home card, the push copy and the researcher page, with in-memory stores
// (no Firebase).  Synthetic data only.
//
//   flutter build web --no-web-resources-cdn \
//     -t docs/dev-reports/T17b-ada-v1-20261007-screenshots/t17b_screens_main.dart
//   index.html?page=ada&form=full&screen=3&variant=masculine&voice=0
//   page=flow&state=partial | page=home | page=push | page=staff
//
// `screen` opens a page on that screen by seeding a draft (`lastScreen`),
// the same way a participant resumes.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_a_schedule_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/scheduling/pending_prompts_service.dart';
import 'package:app_demo/features/ada/data/ada_gate.dart';
import 'package:app_demo/features/ada/data/ada_items.dart';
import 'package:app_demo/features/ada/data/survey_draft_store.dart';
import 'package:app_demo/features/ada/presentation/ada_page.dart';
import 'package:app_demo/features/ada/presentation/ada_staff_page.dart';
import 'package:app_demo/features/ada/presentation/day7_flow_page.dart';
import 'package:app_demo/features/ada/presentation/day7_open_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/today/presentation/widgets/pending_prompts_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const _uid = 'synthetic-screens';
const _full = AdaTimepoint(id: 'day7', form: AdaForm.full, dayFrom: 7, dayTo: 9);
const _short =
    AdaTimepoint(id: 'visit1', form: AdaForm.short, dayFrom: 1, dayTo: 1);

// Copied from functions/ada.js PUSH_BODY / REMINDER_BODY (draft).
const _pushBody = '【占位】第 7 日問卷開咗，得閒入嚟做。可以分幾次做。';
const _reminderBody = '【占位】第 7 日問卷仲未做完，得閒入嚟做埋佢。';

Map<String, dynamic> _adaDraft(int screen, {bool text = false,
    bool skipped = false, bool done = false}) => {
      'status': done ? 'submitted' : 'in_progress',
      'lastScreen': screen,
      'startedAt': DateTime(2026, 10, 7),
      'usage': {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 2},
      'traits': {
        for (final t in AdaTraits.all)
          t: {
            'siu_yan': 5,
            'ah_jan_ah_bak': 4,
            'tung_tung': skipped && t == AdaTraits.warm ? kSkipped : 2,
          },
      },
      'scenarios': {
        'day_recap': 'siu_yan',
        'memories': 'ah_jan_ah_bak',
        'learn_new': skipped ? kSkipped : 'tung_tung',
        'feeling_down': 'siu_yan',
        'small_talk': 'any',
      },
      if (text)
        'freeText': '小欣好關心我，通通識好多嘢。我會同小欣傾多啲，因為佢會問我今日點。',
    };

class _Staff implements AdaStaffSource {
  @override
  Future<List<AdaDay7Row>> day7Status() async => const [
        AdaDay7Row(uid: 'syn001', label: '合成參與者 A · syn001',
            status: 'overdue', enrolmentDay: 10, partial: true,
            pushSentAt: '2026-10-07 19:00', reminderSentAt: '2026-10-08 19:00'),
        AdaDay7Row(uid: 'syn002', label: '合成參與者 B · syn002',
            status: 'in_progress', enrolmentDay: 8,
            pushSentAt: '2026-10-08 10:00'),
        AdaDay7Row(uid: 'syn003', label: '合成參與者 C · syn003',
            status: 'not_started', enrolmentDay: 6),
        AdaDay7Row(uid: 'syn004', label: '合成參與者 D · syn004',
            status: 'completed', enrolmentDay: 9, channel: 'phone_by_staff',
            pushSentAt: '2026-10-06 14:00'),
        AdaDay7Row(uid: 'syn005', label: '合成參與者 E · syn005',
            status: 'completed', enrolmentDay: 8, channel: 'app',
            pushSentAt: '2026-10-07 17:00'),
      ];
}

class _PushMock extends StatelessWidget {
  const _PushMock();

  Widget _note(String when, String body) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.favorite, color: Color(0xFFF0997B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('陪住 · $when',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontSize: 16)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF37474F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('（模擬手機通知；文字取自 functions/ada.js 草稿。'
                  '帶【占位】時伺服器唔會發送）',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              _note('第 7 日 19:00（老人揀嘅時間）', _pushBody),
              _note('第 8 日 19:00（24 小時後未做完）', _reminderBody),
            ]),
          ),
        ),
      );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final q = Uri.base.queryParameters;
  final screen = int.tryParse(q['screen'] ?? '') ?? 0;
  final voice = q['voice'] == '1';
  // ignore: invalid_use_of_visible_for_testing_member
  RemoteFeatureFlags.current = RemoteFeatureFlags(voiceInputEnabled: voice);
  // ignore: invalid_use_of_visible_for_testing_member
  PhaseAScheduleConfig.current = const PhaseAScheduleConfig(
      adaEnabled: true, day7OpenEndedEnabled: true);
  final variant = AgentGenderVariant.tryParse(q['variant'] ?? 'feminine');
  final store = InMemorySurveyDraftStore();
  late final Widget home;
  switch (q['page']) {
    case 'day7':
      store.docs[InMemorySurveyDraftStore.key(
          _uid, kDay7OpenCollection, kDay7OpenDocId)] = {
        'status': 'in_progress',
        'lastScreen': screen,
        'startedAt': DateTime(2026, 10, 7),
      };
      home = Day7OpenPage(
          store: store, uid: _uid, voiceEnabled: voice, part: (2, 2));
    case 'flow':
      if (q['state'] == 'partial') {
        store.docs[InMemorySurveyDraftStore.key(_uid, kAdaCollection, 'day7')] =
            _adaDraft(5);
      }
      home = Day7FlowPage(
          parts: const [Day7Part.ada, Day7Part.open],
          adaTimepoint: _full,
          store: store,
          uid: _uid,
          variant: variant,
          voiceEnabled: voice);
    case 'home':
      home = Scaffold(
        appBar: AppBar(title: const Text('今日')),
        body: ListView(children: const [
          PendingPromptsBanner(
            preset: PendingPrompts(
              pgic: false,
              weeklyPr: false,
              weeklyPrWeekIso: null,
              weeklyPrAgent: null,
              djgEsW2: false,
              agentDiffW2: false,
              agentDiffW4: false,
              day7Flow: [Day7Part.ada, Day7Part.open],
              enrolmentDay: 7,
            ),
          ),
        ]),
      );
    case 'push':
      home = const _PushMock();
    case 'staff':
      home = AdaStaffPage(source: _Staff());
    default:
      final full = q['form'] == 'full';
      final tp = full ? _full : _short;
      if (screen > 0 || q['done'] == '1') {
        store.docs[InMemorySurveyDraftStore.key(_uid, kAdaCollection, tp.id)] =
            _adaDraft(screen,
                text: q['text'] == '1',
                skipped: q['skipped'] == '1',
                done: q['done'] == '1');
      }
      home = AdaPage(
        timepoint: tp,
        store: store,
        uid: _uid,
        variant: q['variant'] == 'none' ? null : variant,
        voiceEnabled: voice,
        allowSkip: q['skip'] != '0',
        part: q['part'] == '1' ? (1, 2) : null,
      );
  }
  final llm = LlmGateway();
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  runApp(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh')),
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: CoreServicesScope(
          llm: llm,
          memory: memory,
          distress: const DistressDetector(),
          distressState: state,
          distressRouter: DistressRouter(state: state),
          crossModuleMemory: CrossModuleMemoryService(
              memory: memory, firestoreAvailable: false),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
              agentContext: agentContext, sharedContext: sharedContext),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('zh', 'HK'),
            supportedLocales: const [Locale('zh', 'HK'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: home,
          ),
        ),
      ),
    ),
  ));
}

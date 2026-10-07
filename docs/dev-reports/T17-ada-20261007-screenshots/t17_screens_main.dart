// T17 screenshot entrypoint (not shipped): renders the ADA / day-7 pages
// with an in-memory store (no Firebase) so Playwright can capture every
// screen.  Synthetic answers only.
//
//   flutter build web --no-web-resources-cdn \
//     -t docs/dev-reports/T17-ada-20261007-screenshots/t17_screens_main.dart
//   open index.html?page=ada&form=full&screen=3&variant=masculine&voice=0
//        index.html?page=day7&screen=1&voice=1
//
// `screen` opens the page on that screen by seeding a draft
// (`lastScreen`), the same way a participant resumes a saved draft.
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
import 'package:app_demo/features/ada/data/ada_items.dart';
import 'package:app_demo/features/ada/data/survey_draft_store.dart';
import 'package:app_demo/features/ada/presentation/ada_page.dart';
import 'package:app_demo/features/ada/presentation/day7_open_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const _uid = 'synthetic-screens';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final q = Uri.base.queryParameters;
  final screen = int.tryParse(q['screen'] ?? '') ?? 0;
  final voice = q['voice'] == '1';
  // Same switch the App reads from app_config/feature_flags.
  // ignore: invalid_use_of_visible_for_testing_member
  RemoteFeatureFlags.current = RemoteFeatureFlags(voiceInputEnabled: voice);
  final variant = AgentGenderVariant.tryParse(q['variant'] ?? 'feminine');
  final store = InMemorySurveyDraftStore();
  late final Widget home;
  if (q['page'] == 'day7') {
    store.docs[InMemorySurveyDraftStore.key(
        _uid, kDay7OpenCollection, kDay7OpenDocId)] = {
      'status': q['done'] == '1' ? 'submitted' : 'in_progress',
      'lastScreen': screen,
      'startedAt': DateTime(2026, 10, 7),
      'answers': {
        'q1': {'text': '習慣咗每朝同小欣講早晨。', 'status': 'answered'},
      },
    };
    home = Day7OpenPage(store: store, uid: _uid, voiceEnabled: voice);
  } else {
    final full = q['form'] == 'full';
    final tp = full
        ? const AdaTimepoint(
            id: 'day7', form: AdaForm.full, dayFrom: 7, dayTo: 9)
        : const AdaTimepoint(
            id: 'visit1', form: AdaForm.short, dayFrom: 1, dayTo: 1);
    if (screen > 0 || q['done'] == '1') {
      store.docs[InMemorySurveyDraftStore.key(_uid, kAdaCollection, tp.id)] = {
        'status': q['done'] == '1' ? 'submitted' : 'in_progress',
        'lastScreen': screen,
        'startedAt': DateTime(2026, 10, 7),
        'usage': {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 2},
        'traits': {
          for (final t in AdaTraits.all)
            t: {'siu_yan': 5, 'ah_jan_ah_bak': 4, 'tung_tung': 2},
        },
        'scenarios': {
          'day_recap': 'siu_yan',
          'memories': 'ah_jan_ah_bak',
          'learn_new': 'tung_tung',
          'feeling_down': 'siu_yan',
          'small_talk': 'any',
        },
        if (q['text'] == '1')
          'freeText': '小欣好關心我，通通識好多嘢。我會同小欣傾多啲，因為佢會問我今日點。',
      };
    }
    home = AdaPage(
      timepoint: tp,
      store: store,
      uid: _uid,
      variant: variant,
      voiceEnabled: voice,
      allowSkip: q['skip'] != '0',
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

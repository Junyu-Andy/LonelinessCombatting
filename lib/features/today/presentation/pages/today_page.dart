import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../../../crisis/presentation/widgets/safety_footer_card.dart';
import '../widgets/active_plan_banner.dart';
import '../widgets/agent_tile_row.dart';
import '../widgets/greeting_hero.dart';
import '../widgets/pending_prompts_banner.dart';
import '../widgets/quiet_today_banner.dart';

/// Home tab (屋企) — agent-tile entry point.
///
/// Dev Req §2.2 layout, top to bottom:
///   1. Greeting hero (existing)
///   2. Safety pill — rendered globally above all tabs, not here
///   3. Today's plan banner (existing)
///   4. Absence nudge (existing P3.2)
///   5. Three agent tiles (Sprint 1)
///   6. Tool quick links (Sprint 1)
///   7. 999 / crisis footer (existing)
///
/// On first build we also kick off a fire-and-forget warm-up of today's
/// personalised greeting for Ah Jan/Ah Bak and Tung Tung so the cache
/// is hot by the time the user taps a tile.  Siu Yan is handled by a
/// separate mood-aware opener flow.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _greetingsWarmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeWarmGreetings();
  }

  void _maybeWarmGreetings() {
    if (_greetingsWarmed) return;
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    _greetingsWarmed = true;
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    // Fire-and-forget: latency stays off the UI path.  Errors are
    // swallowed inside the service so the user never sees them.
    unawaited(core.agentGreeting.ensureGreeting(
      uid: profile.uid,
      agentId: AgentRegistry.ahJanAhBakId,
      profile: profile,
      isEn: isEn,
    ));
    unawaited(core.agentGreeting.ensureGreeting(
      uid: profile.uid,
      agentId: AgentRegistry.tungTungId,
      profile: profile,
      isEn: isEn,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        // 睇今日 per Product Overview §3.2: greeting + agent-tile entry
        // points + plan banner + safety pill + (later) weekly LLM card.
        // Tools moved to 做啲嘢 tab as part of the four-tab IA.
        children: const [
          GreetingHero(),
          QuietTodayBanner(),
          PendingPromptsBanner(),
          MissedCheckInBanner(),
          ActivePlanBanner(),
          AgentTileRow(),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 72),
            child: SafetyFooterCard(analyticsTag: 'today_safety_footer'),
          ),
        ],
      ),
    );
  }
}

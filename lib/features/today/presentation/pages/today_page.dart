import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../../../crisis/presentation/widgets/safety_footer_card.dart';
import '../widgets/active_plan_banner.dart';
import '../widgets/agent_tile_row.dart';
import '../widgets/continue_chat_card.dart';
import '../widgets/facts_recap_row.dart';
import '../widgets/greeting_hero.dart';
import '../widgets/home_tool_shortcuts.dart';
import '../widgets/pending_prompts_banner.dart';

/// Home tab (屋企) — final layout per Home Layout Spec §1:
///   1. Greeting hero with embedded 5-emoji mood pad (§1–2)
///   2. "Continue chatting" suggestion bar (§3)
///   3. Compliance-critical banners (rendered only when active —
///      pending assessments, missed-check-in nudge, plan follow-up)
///   4. "想搵邊位傾下？" + three agent tiles (§1 item 3–4)
///   5. Facts recap line (§4)
///   6. Tool shortcuts: 行動 / 望一望 / 進度 (§1 item 6)
///   7. Crisis footer card — global safety pill renders separately.
///
/// On first build the agent-greeting warm-up still kicks off so that
/// Ah Jan/Ah Bak and Tung Tung have hot caches by the time the user
/// taps a tile.  Siu Yan keeps its mood-aware opener.
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
        children: const [
          GreetingHero(),
          ContinueChatCard(),
          // Compliance banners — each hides itself when nothing is due,
          // so the happy path matches the spec's seven-item layout but
          // study-critical nudges still surface when the protocol calls
          // for them.
          PendingPromptsBanner(),
          MissedCheckInBanner(),
          ActivePlanBanner(),
          AgentTileRow(),
          FactsRecapRow(),
          HomeToolShortcuts(),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 72),
            child: SafetyFooterCard(analyticsTag: 'today_safety_footer'),
          ),
        ],
      ),
    );
  }
}

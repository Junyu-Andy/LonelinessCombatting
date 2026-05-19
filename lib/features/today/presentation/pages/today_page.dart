import 'package:flutter/material.dart';

import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../../../crisis/presentation/widgets/safety_footer_card.dart';
import '../widgets/active_plan_banner.dart';
import '../widgets/agent_tile_row.dart';
import '../widgets/greeting_hero.dart';
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
/// The previous M2 hero card + M5/M6 micro-action row have been removed:
/// M2 lives under Siu Yan's tile, and M5/M6 are reachable through the
/// agents and the Me tab respectively.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

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

import 'package:flutter/material.dart';

import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../../../crisis/presentation/widgets/safety_footer_card.dart';
import '../widgets/active_plan_banner.dart';
import '../widgets/check_in_hero_card.dart';
import '../widgets/greeting_hero.dart';
import '../widgets/micro_action_row.dart';

/// Today tab — task-oriented surface. Top to bottom:
///   1. Greeting hero
///   2. Conditional absence banner (>= 2 days w/o check-in)
///   3. Conditional active-plan banner (P1: mock; P2.5 wires to provider)
///   4. Check-in hero card (the one obvious next step)
///   5. Micro-action row (M5 reflection + M6 invitation)
///   6. 999 / crisis footer
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: const [
          GreetingHero(),
          MissedCheckInBanner(),
          ActivePlanBanner(),
          Padding(
            // UX-polish: trailing padding 100→72 so older participants
            // don't keep scrolling past empty space to confirm nothing
            // else loaded below.
            padding: EdgeInsets.fromLTRB(20, 20, 20, 72),
            child: Column(
              children: [
                CheckInHeroCard(),
                SizedBox(height: 16),
                MicroActionRow(),
                SizedBox(height: 20),
                SafetyFooterCard(analyticsTag: 'today_safety_footer'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

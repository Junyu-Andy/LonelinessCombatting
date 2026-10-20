import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../brief_pr/presentation/widgets/brief_pr_card_host.dart';
import '../../../crisis/presentation/widgets/safety_footer_card.dart';
import '../widgets/active_plan_banner.dart';
import '../widgets/agent_tile_row.dart';
import '../widgets/checkin_status_chip.dart';
import '../widgets/continue_chat_card.dart';
import '../widgets/facts_recap_row.dart';
import '../widgets/greeting_hero.dart';
import '../widgets/home_small_action_row.dart';
import '../widgets/home_tool_shortcuts.dart';
import '../../../../core/time/app_clock.dart';
import '../widgets/daily_mood_prompt.dart';
import '../widgets/simulated_clock_strip.dart';
import '../widgets/pending_prompts_banner.dart';
import '../widgets/today_todo_rows.dart';
import '../home_v2_scope.dart';
import '../../../../core/session/session_entry_surface.dart';
import '../widgets/week1_nudge_banner.dart';

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
///
/// 1020 D (`app_config/feature_flags.homeLayoutV2Enabled`, both arms): page
/// 1 「睇今日」 from top to bottom —
///   (1) greeting; (2) the mood row (1020 E, or the old pad while
///   `moodRowV2Enabled` is off); (3) 「今日要做嘅事」: check-in (the 3-day
///   reminder folded in), the Brief PR invitation (the same
///   [BriefPrCardHost] as page 2), the weekly questionnaire (G (2)) and the
///   small-action row (1020m 第二节, [HomeSmallActionRow]; it replaced the
///   action-plan follow-up [ActivePlanBanner], which now shows only in the
///   old layout); (4) 「去搵人傾」 → page 2; (5) the week's recap;
///   (6) the crisis card.  Moved off: the companion tiles, the continue
///   card and the first-week nudge (to page 2), the tool shortcuts, the
///   daily mood pop-up, the missed-check-in banner.  The old
///   `briefPrHomeBannerEnabled` banner never shows with this on.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _greetingsWarmed = false;

  @override
  void initState() {
    super.initState();
    AppClock.instance.addListener(_onClock);
  }

  @override
  void dispose() {
    AppClock.instance.removeListener(_onClock);
    super.dispose();
  }

  /// Tester schedule simulation jumped to another day — re-run the
  /// first-open-of-the-day mood prompt for that day.
  void _onClock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeDailyMoodPopup();
    });
  }

  /// M-3 sheet — only in the old layout with the old pad (1020 D, E (1)).
  void _maybeDailyMoodPopup() {
    if (!RemoteFeatureFlags.current.dailyMoodPopupActive) return;
    // 1020l: it reads Firestore — never without Firebase (guest mode,
    // widget tests).  The App always has Firebase: unchanged there.
    if (!AuthServiceScope.of(context).available) return;
    unawaited(DailyMoodPrompt.maybeShow(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeWarmGreetings();
    // M-3 — one-question mood prompt on the first home build of the day.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeDailyMoodPopup();
    });
  }

  void _maybeWarmGreetings() {
    if (_greetingsWarmed) return;
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    // Personalised openers are LLM-generated — Arm A only.
    if (!Arm.isA(context)) return;
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
    if (RemoteFeatureFlags.current.homeLayoutV2Enabled) {
      return _buildV2(context);
    }
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Tester-only: visible whenever the schedule simulator is active.
          const SimulatedClockStrip(),
          const GreetingHero(),
          // 10/19 (Junyu, switch briefPrHomeBannerEnabled): the Brief PR
          // invitation right under the greeting, so it is seen without
          // going to the companion list.  Renders nothing when none is due.
          // 1020b §2 (2): never with homeLayoutV2Enabled (then it is in
          // 「今日要做嘅事」 — this branch is not built, the guard is a
          // second lock).
          if (RemoteFeatureFlags.current.briefPrHomeBannerActive)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: BriefPrCardHost(),
            ),
          // B05 — always-visible "did today's check-in happen?" status.
          const CheckInStatusChip(),
          const ContinueChatCard(),
          // Compliance banners — each hides itself when nothing is due,
          // so the happy path matches the spec's seven-item layout but
          // study-critical nudges still surface when the protocol calls
          // for them.  1020l: it reads Firestore, so (as on the new page 1)
          // only with Firebase — guest mode and widget tests leave it out.
          if (AuthServiceScope.of(context).available)
            const PendingPromptsBanner(),
          // P-1 — first-week "try {agent}" nudge (days 3 and 6).
          const Week1NudgeBanner(),
          const MissedCheckInBanner(),
          const ActivePlanBanner(),
          const AgentTileRow(),
          const FactsRecapRow(),
          const HomeToolShortcuts(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 72),
            child: SafetyFooterCard(analyticsTag: 'today_safety_footer'),
          ),
        ],
      ),
    );
  }

  /// 1020 D — page 1 of the two-page layout.  1020e 一.(9): sessions
  /// opened from here record entrySurface `page1` ([HomeSurfaceScope]).
  Widget _buildV2(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    final questionnaireRow = QuestionnaireTodoRow.activeFor(profile);
    final firebase = AuthServiceScope.of(context).available;
    return HomeSurfaceScope(
      surface: SessionEntrySurface.page1,
      child: SafeArea(
        child: ListView(
          key: const ValueKey('today_v2'),
          padding: EdgeInsets.zero,
          children: [
            const SimulatedClockStrip(),
            // (1) greeting and (2) the mood row.
            const GreetingHero(),
            // (3) 今日要做嘅事 — each row only when there is something.
            const TodoSectionTitle(),
            const CheckInTodoRow(),
            const BriefPrCardHost(),
            if (questionnaireRow) const QuestionnaireTodoRow(),
            // Whatever else the study still asks for here (Phase A items,
            // the pre-T24 weekly card): the old banner, minus the weekly
            // card the row above already shows.  Needs Firebase to read.
            if (firebase)
              PendingPromptsBanner(hideWeeklyBundle: questionnaireRow),
            // 1020m 第二节: 今日想做啲咩小行動？ / 今日計劃 (no switch of its
            // own; replaced the old plan follow-up banner here).
            const HomeSmallActionRow(),
            // (4) → page 2.
            const GoTalkButton(),
            // (5) this week's recap (tap: 你嘅一個禮拜, 1020e 二.11).
            const FactsRecapRow(),
            // (6) crisis card, unchanged.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 72),
              child: SafetyFooterCard(analyticsTag: 'today_safety_footer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown on TodayPage when scheduled prompts are due (Phase A
/// baseline 2026-09).
///
/// Replaces FCM/scheduler integration in the client-only build: the push
/// is only a doorbell; when the user opens 屋企 inside the Weekly PR window
/// (Sun 20:00 → Tue 23:59) or the Week 2 / Week 4 windows, the banner
/// surfaces and routes to the relevant pages.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/scheduling/pending_prompts_service.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../assessment/presentation/pages/agent_diff_page.dart';
import '../../../assessment/presentation/pages/djg_es_page.dart';
import '../../../assessment/presentation/pages/pgic_page.dart';
import '../../../weekly_pr/data/weekly_pr_trigger.dart';
import '../../../weekly_pr/presentation/pages/weekly_pr_page.dart';

class PendingPromptsBanner extends StatefulWidget {
  const PendingPromptsBanner({super.key});

  @override
  State<PendingPromptsBanner> createState() => _PendingPromptsBannerState();
}

class _PendingPromptsBannerState extends State<PendingPromptsBanner> {
  PendingPrompts? _pending;
  bool _loading = false;
  PendingPromptsService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service ??= PendingPromptsService(analytics: AnalyticsScope.of(context));
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (_loading || _pending != null) return;
    final profile = AppSettingsScope.of(context).profile;
    if (profile == null) return;
    setState(() => _loading = true);
    final result = await _service!.shouldShowOnHomeNow(profile.uid, profile);
    if (!mounted) return;
    setState(() {
      _pending = result;
      _loading = false;
    });
  }

  /// Sunday weekly cycle (M-2): PGIC first (global impression), then the
  /// single-companion Weekly PR.  A week with no agent session asks PGIC
  /// only and writes a `no_referent` record for the 12 items.
  Future<void> _openWeeklyCycle() async {
    final p = _pending;
    if (p == null) return;
    if (p.pgic) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PgicPage()),
      );
      if (!mounted) return;
    }
    if (p.weeklyPr) {
      final agent = p.weeklyPrAgent;
      if (agent != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WeeklyPrPage(agent: agent, weekIso: p.weeklyPrWeekIso),
          ),
        );
      } else {
        final profile = AppSettingsScope.read(context).profile;
        final isEn = Localizations.localeOf(context).languageCode == 'en';
        if (profile != null) {
          unawaited(WeeklyPrTrigger().writeNoReferent(
            profile.uid,
            Arm.of(context)?.code ?? 'A',
            weekIso: p.weeklyPrWeekIso,
          ));
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isEn
              ? "You didn't chat with a companion this week, so there's nothing more to rate."
              : '本週你冇同 companion 傾偈，今週唔使評夥伴。'),
          duration: const Duration(seconds: 4),
        ));
      }
      if (!mounted) return;
    }
    if (mounted) setState(() => _pending = null);
  }

  /// M-4 — Week 2 battery: DJG-ES then Agent Differentiation; logs
  /// `w2_completed` once both parts are done.
  Future<void> _openWeek2() async {
    final p = _pending;
    if (p == null) return;
    var djgDone = !p.djgEsW2;
    var diffDone = !p.agentDiffW2;
    if (p.djgEsW2) {
      final r = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const DjgEsPage(timepoint: 'week2')),
      );
      djgDone = r == true;
      if (!mounted) return;
    }
    if (p.agentDiffW2) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AgentDiffPage(wave: 2)),
      );
      diffDone = true; // the page persists on submit; skips are re-offered
      if (!mounted) return;
    }
    if (djgDone && diffDone) {
      unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.w2Completed));
    }
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _openAgentDiff(int wave) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AgentDiffPage(wave: wave)),
    );
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    if (p == null || !p.any) return const SizedBox.shrink();
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final tiles = <Widget>[];

    if (p.pgic || p.weeklyPr) {
      final noReferent = p.weeklyPr && p.weeklyPrAgent == null;
      tiles.add(_BannerTile(
        icon: Icons.sentiment_satisfied_outlined,
        title: isEn ? 'A quick weekly check-in' : '今週有個簡短嘅週評',
        // M-2 — a week with no companion session still asks PGIC; say so.
        subtitle: noReferent
            ? (isEn
                ? "You didn't chat with a companion this week — one quick question only."
                : '本週你冇同 companion 傾偈，淨係一條問題。')
            : (isEn
                ? 'Has your loneliness changed since last week?'
                : '同上週比較，孤單感有冇變化？'),
        onTap: _openWeeklyCycle,
      ));
    }

    if (p.w2Any) {
      tiles.add(_BannerTile(
        icon: Icons.assessment_outlined,
        title: isEn ? 'Week 2 questions' : '第 2 週問卷',
        subtitle: isEn
            ? 'A few minutes: how things feel, and the three companions.'
            : '幾分鐘：最近嘅感受，同三個夥伴嘅比較。',
        onTap: _openWeek2,
      ));
    }
    if (p.agentDiffW4) {
      tiles.add(_BannerTile(
        icon: Icons.assessment_outlined,
        title: isEn ? 'Companion assessment (Week 4)' : '夥伴評估（第 4 週）',
        subtitle: isEn
            ? 'A few minutes to compare the three companions.'
            : '請花幾分鐘比較三個夥伴。',
        onTap: () => _openAgentDiff(4),
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: tiles,
          ),
        ),
      ),
    );
  }
}

class _BannerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BannerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 30, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onTertiaryContainer,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onTertiaryContainer),
          ],
        ),
      ),
    );
  }
}

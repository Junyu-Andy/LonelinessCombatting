/// Banner shown on TodayPage when scheduled prompts are due.
///
/// Replaces FCM/scheduler integration in the client-only build:
/// when the user opens 屋企 on Sunday evening or hits a 14/28-day
/// anniversary, the banner surfaces and routes to the relevant page.

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/scheduling/pending_prompts_service.dart';
import '../../../assessment/presentation/pages/agent_diff_page.dart';
import '../../../assessment/presentation/pages/pgic_page.dart';

class PendingPromptsBanner extends StatefulWidget {
  const PendingPromptsBanner({super.key});

  @override
  State<PendingPromptsBanner> createState() => _PendingPromptsBannerState();
}

class _PendingPromptsBannerState extends State<PendingPromptsBanner> {
  PendingPrompts? _pending;
  bool _loading = false;
  final _service = PendingPromptsService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (_loading || _pending != null) return;
    final profile = AppSettingsScope.of(context).profile;
    if (profile == null) return;
    setState(() => _loading = true);
    final result = await _service.shouldShowOnHomeNow(profile.uid, profile);
    if (!mounted) return;
    setState(() {
      _pending = result;
      _loading = false;
    });
  }

  Future<void> _openPgicOnly() async {
    // Weekly PR follow-up after PGIC is deferred per product — the
    // weekly companion review surface is not currently exposed to
    // participants.  PGIC still fires on its weekly schedule.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PgicPage()),
    );
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _openAgentDiff(int wave) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgentDiffPage(wave: wave),
      ),
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

    if (p.pgic) {
      tiles.add(_BannerTile(
        icon: Icons.sentiment_satisfied_outlined,
        title: isEn ? 'A quick weekly check-in today' : '今日有個簡短嘅週評',
        subtitle: isEn
            ? 'Has your loneliness changed since last week?'
            : '同上週比較，孤單感有冇變化？',
        onTap: _openPgicOnly,
      ));
    }
    // Weekly PR tile suppressed per product — re-add the `else if
    // (p.weeklyPr)` branch + `_openWeekly` route when the weekly
    // companion review surface ships again.

    if (p.agentDiffW2) {
      tiles.add(_BannerTile(
        icon: Icons.assessment_outlined,
        title: isEn ? 'Companion assessment (Week 2)' : '夥伴評估（第 2 週）',
        subtitle: isEn
            ? 'A few minutes to compare the three companions.'
            : '請花幾分鐘比較三個夥伴。',
        onTap: () => _openAgentDiff(2),
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

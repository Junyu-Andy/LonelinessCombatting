/// P-1 — first-week "you haven't tried {agent} yet" nudge (Phase A
/// baseline 2026-09).
///
/// On enrolment days [PhaseAConfig.week1NudgeDays] (3 and 6), if any of the
/// three companions has no agent session yet, show one dismissible line on
/// the home page.  Not forced, not pushed.  Logs `week1_nudge_shown` once
/// per day with the agent named.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/config/phase_a_config.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/mood_recorder.dart';

class Week1NudgeBanner extends StatefulWidget {
  const Week1NudgeBanner({super.key});

  @override
  State<Week1NudgeBanner> createState() => _Week1NudgeBannerState();
}

class _Week1NudgeBannerState extends State<Week1NudgeBanner> {
  /// Dismissed / shown bookkeeping per local day, process-wide.
  static String? _dismissedDateIso;
  static String? _loggedDateIso;

  String? _unusedAgentId;
  bool _resolved = false;

  /// Enrolment day index (day 1 = the enrolment date).
  static int enrolmentDay(DateTime createdAt, DateTime now) {
    final c = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final n = DateTime(now.year, now.month, now.day);
    return n.difference(c).inDays + 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final profile = AppSettingsScope.read(context).profile;
    final available = AuthServiceScope.of(context).available;
    final createdAt = profile?.createdAt;
    if (profile == null || createdAt == null || !available) return;
    final today = MoodRecorder.dateIsoFor(DateTime.now());
    if (_dismissedDateIso == today) return;
    final day = enrolmentDay(createdAt, DateTime.now());
    if (!PhaseAConfig.current.week1NudgeDays.contains(day)) return;
    final used = <String>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(profile.uid)
          .collection('sessions')
          .where('kind', isEqualTo: 'agent')
          .get();
      for (final d in snap.docs) {
        final a = d.data()['agentId'];
        if (a is String) used.add(a);
      }
    } catch (_) {
      return; // fail quiet — never nag on a read error
    }
    String? unused;
    for (final a in AgentRegistry.all) {
      if (!used.contains(a.id)) {
        unused = a.id;
        break;
      }
    }
    if (unused == null || !mounted) return;
    setState(() => _unusedAgentId = unused);
    if (_loggedDateIso != today) {
      _loggedDateIso = today;
      unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.week1NudgeShown, {
        'agentId': unused,
        'enrolmentDay': day,
      }));
    }
  }

  void _dismiss() {
    _dismissedDateIso = MoodRecorder.dateIsoFor(DateTime.now());
    setState(() => _unusedAgentId = null);
  }

  @override
  Widget build(BuildContext context) {
    final agentId = _unusedAgentId;
    if (agentId == null) return const SizedBox.shrink();
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final variant = AppSettingsScope.read(context).profile?.ahJanAhBakVariant;
    final name = agentId == AgentRegistry.ahJanAhBakId
        ? AgentRegistry.ahJanAhBakName(variant, isEn: isEn)
        : AgentRegistry.byId(agentId).resolveVariant(null).let((v) => isEn ? v.displayNameEn : v.displayNameZh);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            children: [
              Icon(Icons.waving_hand_outlined,
                  size: 26, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEn
                      ? "You haven't chatted with $name yet — want to try?"
                      : '你仲未同 $name 傾過，想試下嗎？',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 18,
                    height: 1.4,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: isEn ? 'Dismiss' : '關閉',
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

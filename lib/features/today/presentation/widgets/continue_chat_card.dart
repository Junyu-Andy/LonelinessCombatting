import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../../my_story/data/my_story_progress.dart';
import '../../../reminiscence/presentation/pages/reminiscence_landing.dart';

/// Home Layout Spec §3 — single "continue chatting" suggestion bar.
///
/// Computes one suggestion client-side and renders a sand-coloured card
/// that lands the user in a clearly-named agent's surface (no unified
/// router, hard research constraint).  Hidden silently while loading or
/// when nothing can be suggested at all (extremely rare — the default
/// branch always picks Siu Yan).
class ContinueChatCard extends StatefulWidget {
  const ContinueChatCard({super.key});

  @override
  State<ContinueChatCard> createState() => _ContinueChatCardState();
}

class _ContinueChatCardState extends State<ContinueChatCard> {
  _Suggestion? _suggestion;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final profile = AppSettingsScope.read(context).profile;
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    if (profile == null) {
      if (!mounted) return;
      setState(() => _suggestion = _Suggestion.siuYanDefault(isEn));
      return;
    }
    _Suggestion? pick;

    // Priority 1: reminiscence week with unfinished current chapter.
    try {
      final reader = MyStoryProgressReader(available: true);
      final progress = await reader.read(
        uid: profile.uid,
        referenceDate: DateTime.now(),
        userCreatedAt: profile.createdAt,
      );
      final week = progress.currentWeek;
      if (week.status != MyStorySessionStatus.completed) {
        final theme = week.theme;
        final chapter = isEn
            ? 'Chapter ${theme.weekIndex} · ${theme.titleEn}'
            : '第 ${theme.weekIndex} 章 · ${theme.titleZh}';
        pick = _Suggestion(
          agentId: AgentRegistry.ahJanAhBakId,
          headline: isEn ? 'Pick up with Ah Jan' : '同阿珍講舊時',
          chapter: chapter,
        );
      }
    } catch (_) {
      // Reminiscence store unreachable — skip this priority.
    }

    // Priority 2: Siu Yan hasn't been opened today.
    if (pick == null) {
      try {
        final ctx = await core.agentContext.read(
          uid: profile.uid,
          agentId: AgentRegistry.siuYanId,
        );
        if (!_isToday(ctx.lastUpdated)) {
          pick = _Suggestion(
            agentId: AgentRegistry.siuYanId,
            headline: isEn ? 'Chat with Siu Yan' : '同小欣傾下今日',
            chapter: isEn ? 'A few words about today' : '講幾句今日',
          );
        }
      } catch (_) {}
    }

    // Priority 3: Tung Tung never used.
    if (pick == null) {
      try {
        final ctx = await core.agentContext.read(
          uid: profile.uid,
          agentId: AgentRegistry.tungTungId,
        );
        if (ctx.isEmpty) {
          pick = _Suggestion(
            agentId: AgentRegistry.tungTungId,
            headline: isEn ? 'Talk with Tung Tung' : '同通通講你鍾意嘅嘢',
            chapter:
                isEn ? 'Curious about anything?' : '有冇咩想知或者想傾？',
          );
        }
      } catch (_) {}
    }

    pick ??= _Suggestion.siuYanDefault(isEn);
    if (!mounted) return;
    setState(() => _suggestion = pick);
  }

  bool _isToday(DateTime? t) {
    if (t == null) return false;
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  void _open(_Suggestion s) {
    final Widget destination;
    switch (s.agentId) {
      case AgentRegistry.siuYanId:
        destination = const CheckInPage();
        break;
      case AgentRegistry.ahJanAhBakId:
        destination = const ReminiscenceLandingPage();
        break;
      case AgentRegistry.tungTungId:
        destination = const TungTungPage();
        break;
      default:
        destination = const CheckInPage();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _suggestion;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    if (s == null) {
      // Reserve the height while loading so the layout doesn't pop.
      return const Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 4),
        child: SizedBox(height: 72),
      );
    }
    final palette = _paletteFor(s.agentId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      child: Material(
        color: const Color(0xFFF0E7DC),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.halo,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.ring, width: 2),
                  ),
                  child: Text(
                    palette.initial,
                    style: TextStyle(
                      color: palette.initialColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn ? 'Pick up' : '接著傾',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFA8845F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.headline,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3A3330),
                        ),
                      ),
                      Text(
                        s.chapter,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF968A7D),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFC2703F),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Suggestion {
  final String agentId;
  final String headline;
  final String chapter;
  const _Suggestion({
    required this.agentId,
    required this.headline,
    required this.chapter,
  });
  factory _Suggestion.siuYanDefault(bool isEn) => _Suggestion(
        agentId: AgentRegistry.siuYanId,
        headline: isEn ? 'Chat with Siu Yan' : '同小欣傾下今日',
        chapter: isEn ? 'A few words about today' : '講幾句今日',
      );
}

class _AgentPalette {
  final String initial;
  final Color initialColor;
  final Color halo;
  final Color ring;
  const _AgentPalette({
    required this.initial,
    required this.initialColor,
    required this.halo,
    required this.ring,
  });
}

_AgentPalette _paletteFor(String agentId) {
  switch (agentId) {
    case AgentRegistry.siuYanId:
      return const _AgentPalette(
        initial: '小',
        initialColor: Color(0xFF993C1D),
        halo: Color(0xFFFAECE7),
        ring: Color(0xFFE0A98E),
      );
    case AgentRegistry.ahJanAhBakId:
      return const _AgentPalette(
        initial: '珍',
        initialColor: Color(0xFF3C3489),
        halo: Color(0xFFEEEDFE),
        ring: Color(0xFFB3ACDE),
      );
    case AgentRegistry.tungTungId:
      return const _AgentPalette(
        initial: '通',
        initialColor: Color(0xFF0F6E56),
        halo: Color(0xFFE1F5EE),
        ring: Color(0xFF7FCBAE),
      );
  }
  return const _AgentPalette(
    initial: '·',
    initialColor: Color(0xFF2E251D),
    halo: Color(0xFFF1ECE6),
    ring: Color(0xFFBDB1A4),
  );
}

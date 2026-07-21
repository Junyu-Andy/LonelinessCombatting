/// Weekly PR page (Sprint 1 §4 + change C2, 2026-06; redesign 2026-07).
///
/// C2: anchored to a SINGLE companion — the one the participant used most
/// that week (WeeklyPrTrigger.mostUsedAgentThisWeek). One weekly PR per
/// participant-week; cross-agent comparison lives in Agent Differentiation.
///
/// 2026-07 redesign: 12 items paginated 4-per-page (3 pages) instead of one
/// item per screen; each page carries an agent header (avatar + name +
/// session count); items use a compact horizontal 1–7 selector with the key
/// phrase bolded. Stores one doc per week to `users/{uid}/weekly_pr/{auto}`.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/survey/likert_scale.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/weekly_pr_response.dart';
import '../../data/weekly_pr_trigger.dart';

class WeeklyPrPage extends StatefulWidget {
  /// The single most-used companion this week (C2).
  final WeeklyPrAgentUsage agent;

  const WeeklyPrPage({super.key, required this.agent});

  @override
  State<WeeklyPrPage> createState() => _WeeklyPrPageState();
}

class _WeeklyPrPageState extends State<WeeklyPrPage> {
  static const _perPage = 4;

  int _pageIndex = 0;
  late List<({String id, String text})> _items;
  final Map<String, int> _ratings = {};
  late DateTime _promptedAt;
  bool _saving = false;

  /// Key phrase(s) bolded in each item so elderly readers catch the point
  /// quickly. The agent name is bolded too (added at render time).
  static const Map<String, List<String>> _keywords = {
    'u1': ['明白', '感受'],
    'u2': ['明白', '想法'],
    'u3': ['聽到'],
    'v1': ['尊重'],
    'v2': ['認可'],
    'v3': ['判斷'],
    'c1': ['關心'],
    'c2': ['著想'],
    'c3': ['舒服'],
    'i1': ['搞錯重點'],
    'i2': ['唔在乎'],
    'i3': ['唔舒服'],
  };

  @override
  void initState() {
    super.initState();
    _promptedAt = DateTime.now();
    _items = _shuffledItems();
  }

  List<({String id, String text})> _shuffledItems() {
    final base = List<({String id, String text})>.from(WeeklyPrItems.items);
    base.shuffle(Random());
    return base;
  }

  WeeklyPrAgentUsage get _currentAgent => widget.agent;

  int get _pageCount => (_items.length + _perPage - 1) ~/ _perPage;

  List<({String id, String text})> get _pageItems {
    final start = _pageIndex * _perPage;
    final end = (start + _perPage) > _items.length ? _items.length : start + _perPage;
    return _items.sublist(start, end);
  }

  bool get _pageComplete =>
      _pageItems.every((it) => _ratings.containsKey(it.id));

  bool get _isLastPage => _pageIndex >= _pageCount - 1;

  Future<void> _persist(String status) async {
    final profile = AppSettingsScope.read(context).profile;
    final armCode = Arm.of(context)?.code ?? 'B';
    final resp = WeeklyPrResponse(
      weekIso: WeeklyPrResponse.currentWeekIso(),
      agentId: _currentAgent.agentId,
      agentDisplayName: _currentAgent.displayName,
      sessionCountThisWeek: _currentAgent.sessionCount,
      items: status == 'completed' ? Map<String, int>.from(_ratings) : const {},
      status: status,
      promptedAt: _promptedAt,
      respondedAt: DateTime.now(),
      arm: armCode,
    );
    if (profile != null) {
      // Fire-and-forget: offline, add() waits for server ack — awaiting it
      // froze the questionnaire on a permanent spinner.
      unawaited(() async {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(profile.uid)
              .collection('weekly_pr')
              .add(resp.toFirestore());
        } catch (_) {}
      }());
    }
    if (!mounted) return;
    if (status == 'completed') {
      await AnalyticsScope.of(context).logWeeklyPrSubmitted(
        weekIso: resp.weekIso,
        agentId: _currentAgent.agentId,
      );
    } else {
      await AnalyticsScope.of(context).logWeeklyPrSkipped(
        weekIso: resp.weekIso,
        agentId: _currentAgent.agentId,
      );
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _prev() {
    if (_pageIndex > 0) setState(() => _pageIndex -= 1);
  }

  Future<void> _next() async {
    if (!_isLastPage) {
      setState(() => _pageIndex += 1);
      return;
    }
    setState(() => _saving = true);
    await _persist('completed');
    if (!mounted) return;
    setState(() => _saving = false);
    await _finish();
  }

  Future<void> _skip() async {
    setState(() => _saving = true);
    await _persist('skipped');
    if (!mounted) return;
    setState(() => _saving = false);
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final agent = _currentAgent;
    final variant = AppSettingsScope.read(context).profile?.ahJanAhBakVariant;
    // Resolve Ah Jan / Ah Bak to the user's chosen gender variant so a 阿伯
    // user never sees 阿珍 (others keep their own name).
    final displayName = agent.agentId == AgentRegistry.ahJanAhBakId
        ? AgentRegistry.ahJanAhBakName(variant, isEn: isEn)
        : agent.displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Weekly companion check-in' : '每週夥伴評估'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                children: [
                  _AgentHeader(
                    agent: AgentRegistry.byId(agent.agentId),
                    variant: variant,
                    displayName: displayName,
                    sessionCount: agent.sessionCount,
                    isEn: isEn,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isEn
                        ? 'Page ${_pageIndex + 1} / $_pageCount'
                        : '第 ${_pageIndex + 1} / $_pageCount 頁',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final it in _pageItems) ...[
                    _WeeklyItemCard(
                      text: WeeklyPrItems.render(it.text, displayName),
                      keywords: [displayName, ...?_keywords[it.id]],
                      value: _ratings[it.id],
                      onChanged: (v) => setState(() => _ratings[it.id] = v),
                      isEn: isEn,
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            _NavBar(
              isEn: isEn,
              canPrev: _pageIndex > 0,
              canNext: _pageComplete && !_saving,
              isLast: _isLastPage,
              onPrev: _prev,
              onNext: _next,
              onSkip: _saving ? null : _skip,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentHeader extends StatelessWidget {
  final AgentDefinition agent;
  final AgentGenderVariant? variant;
  final String displayName;
  final int sessionCount;
  final bool isEn;

  const _AgentHeader({
    required this.agent,
    required this.variant,
    required this.displayName,
    required this.sessionCount,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgentAvatar(agent: agent, selectedVariant: variant, size: 54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEn
                      ? 'You chatted $sessionCount time${sessionCount == 1 ? '' : 's'} this week. Think back on those chats, then rate the statements below.'
                      : '呢個禮拜你同佢傾咗 $sessionCount 次。回想吓你哋傾過嘅嘢，再評下面幾句。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyItemCard extends StatelessWidget {
  final String text;
  final List<String> keywords;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool isEn;

  const _WeeklyItemCard({
    required this.text,
    required this.keywords,
    required this.value,
    required this.onChanged,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BoldedText(
            text: text,
            bold: keywords,
            base: TextStyle(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          LikertScale(
            points: 7,
            value: value,
            onChanged: onChanged,
            lowLabel: isEn ? 'Disagree' : '唔同意',
            highLabel: isEn ? 'Agree' : '同意',
          ),
        ],
      ),
    );
  }
}

/// Renders [text], bolding any occurrence of the strings in [bold]
/// (earliest-match-first, non-overlapping).
class _BoldedText extends StatelessWidget {
  final String text;
  final List<String> bold;
  final TextStyle base;

  const _BoldedText({
    required this.text,
    required this.bold,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      int bestIdx = -1;
      String bestKw = '';
      for (final kw in bold) {
        if (kw.isEmpty) continue;
        final idx = remaining.indexOf(kw);
        if (idx >= 0 && (bestIdx < 0 || idx < bestIdx)) {
          bestIdx = idx;
          bestKw = kw;
        }
      }
      if (bestIdx < 0) {
        spans.add(TextSpan(text: remaining));
        break;
      }
      if (bestIdx > 0) {
        spans.add(TextSpan(text: remaining.substring(0, bestIdx)));
      }
      spans.add(TextSpan(
        text: bestKw,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ));
      remaining = remaining.substring(bestIdx + bestKw.length);
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

class _NavBar extends StatelessWidget {
  final bool isEn;
  final bool canPrev;
  final bool canNext;
  final bool isLast;
  final VoidCallback onPrev;
  final Future<void> Function() onNext;
  final VoidCallback? onSkip;

  const _NavBar({
    required this.isEn,
    required this.canPrev,
    required this.canNext,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (canPrev) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPrev,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(isEn ? 'Back' : '上一頁'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: canNext ? () => onNext() : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      isLast
                          ? (isEn ? 'Submit' : '提交')
                          : (isEn ? 'Next' : '下一頁'),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onSkip,
            child: Text(
              isEn ? 'Skip this week' : '今個禮拜跳過',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Weekly PR page (Sprint 1 §4).
///
/// Sequences through each agent the user used this week (descending
/// session count). For each agent, presents 12 items in a randomised
/// order with 「問題 X / 12」 progress and a 7-point Likert.
///
/// Stores one doc per agent per week to `users/{uid}/weekly_pr/{auto}`.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/weekly_pr_response.dart';
import '../../data/weekly_pr_trigger.dart';

class WeeklyPrPage extends StatefulWidget {
  final List<WeeklyPrAgentUsage> agents;

  const WeeklyPrPage({super.key, required this.agents});

  @override
  State<WeeklyPrPage> createState() => _WeeklyPrPageState();
}

class _WeeklyPrPageState extends State<WeeklyPrPage> {
  int _agentIndex = 0;
  int _itemIndex = 0;
  late List<({String id, String text})> _items;
  final Map<String, int> _ratings = {};
  late DateTime _promptedAt;
  bool _saving = false;

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

  WeeklyPrAgentUsage get _currentAgent => widget.agents[_agentIndex];

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
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('weekly_pr')
            .add(resp.toFirestore());
      } catch (_) {}
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

  Future<void> _nextAgentOrFinish() async {
    if (_agentIndex + 1 >= widget.agents.length) {
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _agentIndex += 1;
      _itemIndex = 0;
      _ratings.clear();
      _items = _shuffledItems();
      _promptedAt = DateTime.now();
    });
  }

  Future<void> _onRate(int value) async {
    final item = _items[_itemIndex];
    _ratings[item.id] = value;
    if (_itemIndex + 1 < _items.length) {
      setState(() => _itemIndex += 1);
      return;
    }
    setState(() => _saving = true);
    await _persist('completed');
    setState(() => _saving = false);
    await _nextAgentOrFinish();
  }

  Future<void> _skipAgent() async {
    setState(() => _saving = true);
    await _persist('skipped');
    setState(() => _saving = false);
    await _nextAgentOrFinish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.agents.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('每週夥伴評估')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '呢個禮拜冇用過任何 companion。',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }
    final agent = _currentAgent;
    final item = _items[_itemIndex];
    final text = WeeklyPrItems.render(item.text, agent.displayName);
    final isLastItem = _itemIndex + 1 == _items.length;
    final isLastAgent = _agentIndex + 1 == widget.agents.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('每週夥伴評估'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              'Companion ${_agentIndex + 1} / ${widget.agents.length}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '回想過去呢一個禮拜你同 ${agent.displayName} 嘅對話：',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '問題 ${_itemIndex + 1} / ${_items.length}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ...List.generate(7, (i) {
              final rating = i + 1;
              const labels = {
                1: '1 — 非常唔同意',
                2: '2 — 唔同意',
                3: '3 — 少少唔同意',
                4: '4 — 中間',
                5: '5 — 少少同意',
                6: '6 — 同意',
                7: '7 — 非常同意',
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _onRate(rating),
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      foregroundColor: theme.colorScheme.onSurface,
                      side: BorderSide(
                        color: theme.colorScheme.outline,
                        width: 1.5,
                      ),
                    ),
                    child: Text(labels[rating]!),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _saving ? null : _skipAgent,
                child: Text(
                  isLastAgent && isLastItem ? '跳過呢個夥伴' : '跳過呢個夥伴',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

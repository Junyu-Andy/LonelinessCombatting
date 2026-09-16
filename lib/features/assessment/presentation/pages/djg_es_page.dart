/// M-4 — Week 2 DJG-ES (6 items, 是 / 多少 / 否) page.  Large tap targets;
/// one item per card; whole battery skippable.  Stores to
/// `users/{uid}/djg_es/{auto}` with `timepoint: week2`.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/survey/survey_item_card.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/djg_es_response.dart';

class DjgEsPage extends StatefulWidget {
  final String timepoint;
  const DjgEsPage({super.key, this.timepoint = 'week2'});

  @override
  State<DjgEsPage> createState() => _DjgEsPageState();
}

class _DjgEsPageState extends State<DjgEsPage> {
  final Map<String, int> _answers = {};
  bool _saving = false;

  bool get _complete => _answers.length == DjgEsItems.items.length;

  Future<void> _persist(String status) async {
    final profile = AppSettingsScope.read(context).profile;
    final resp = DjgEsResponse(
      timepoint: widget.timepoint,
      answers: status == 'completed' ? Map<String, int>.from(_answers) : const {},
      score: status == 'completed' ? DjgEsItems.score(_answers) : -1,
      answeredAt: DateTime.now(),
      status: status,
    );
    if (profile != null) {
      // Fire-and-forget (offline queue) — never block the participant.
      unawaited(() async {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(profile.uid)
              .collection('djg_es')
              .add(resp.toFirestore());
        } catch (_) {}
      }());
    }
    if (!mounted) return;
    unawaited(AnalyticsScope.of(context).logEvent('djg_es_$status', {
      'timepoint': widget.timepoint,
      if (status == 'completed') 'score': resp.score,
    }));
  }

  Future<void> _finish(String status) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _persist(status);
    if (!mounted) return;
    Navigator.of(context).pop(status == 'completed');
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'How things feel lately' : '最近嘅感受'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'Six short statements. For each, tap the answer closest to how it has been for you lately.'
                  : '六句短句。每句撳一個最似你最近情況嘅答案。',
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 18),
            for (final it in DjgEsItems.items) ...[
              SurveyItemCard(
                title: isEn ? it.promptEn : it.promptZh,
                child: Row(
                  children: [
                    for (final opt in DjgEsItems.options) ...[
                      Expanded(
                        child: _OptionButton(
                          label: isEn ? opt.$3 : opt.$2,
                          selected: _answers[it.id] == opt.$1,
                          onTap: () => setState(() => _answers[it.id] = opt.$1),
                        ),
                      ),
                      if (opt != DjgEsItems.options.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _complete && !_saving ? () => _finish('completed') : null,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: Text(isEn ? 'Done' : '完成', style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _saving ? null : () => _finish('skipped'),
                child: Text(isEn ? 'Skip' : '跳過', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Brief PR (Perceived Partner Responsiveness) modal page.
///
/// Sprint 1 §3 — 4 vertical sliders 0–100, no numeric label visible
/// beside thumb, all start centred at 50. Submit enabled once all 4
/// sliders touched. Skip suppressed for anchor prompt.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/brief_pr_response.dart';

class BriefPrPage extends StatefulWidget {
  final String agentId;
  final String agentDisplayName;
  final String? sessionRef;
  final bool isAnchorPrompt;

  const BriefPrPage({
    super.key,
    required this.agentId,
    required this.agentDisplayName,
    this.sessionRef,
    required this.isAnchorPrompt,
  });

  @override
  State<BriefPrPage> createState() => _BriefPrPageState();
}

class _BriefPrPageState extends State<BriefPrPage> {
  double _understanding = 50;
  double _validation = 50;
  double _caring = 50;
  double _insensitivity = 50;

  final Set<int> _touched = {};
  late final DateTime _promptedAt;
  bool _skipVisible = false;
  bool _saving = false;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _promptedAt = DateTime.now();
    if (!widget.isAnchorPrompt) {
      _skipTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _skipVisible = true);
      });
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    super.dispose();
  }

  bool get _canSubmit => _touched.length >= 4 && !_saving;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    final armCode = Arm.of(context)?.code ?? 'B';
    final response = BriefPrResponse(
      agentId: widget.agentId,
      agentDisplayName: widget.agentDisplayName,
      sessionRef: widget.sessionRef,
      understanding: _understanding.round(),
      validation: _validation.round(),
      caring: _caring.round(),
      insensitivity: _insensitivity.round(),
      isAnchorPrompt: widget.isAnchorPrompt,
      status: 'completed',
      promptedAt: _promptedAt,
      respondedAt: DateTime.now(),
      arm: armCode,
    );
    if (profile != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('brief_pr')
            .add(response.toFirestore());
      } catch (_) {
        // Graceful degradation.
      }
    }
    if (mounted) {
      await AnalyticsScope.of(context).logBriefPrSubmitted(
        agentId: widget.agentId,
        moduleId: 'brief_pr',
        items: {
          'understanding': response.understanding,
          'validation': response.validation,
          'caring': response.caring,
          'insensitivity': response.insensitivity,
        },
        isAnchorPrompt: widget.isAnchorPrompt,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    final armCode = Arm.of(context)?.code ?? 'B';
    final response = BriefPrResponse(
      agentId: widget.agentId,
      agentDisplayName: widget.agentDisplayName,
      sessionRef: widget.sessionRef,
      isAnchorPrompt: widget.isAnchorPrompt,
      status: 'skipped',
      promptedAt: _promptedAt,
      respondedAt: DateTime.now(),
      arm: armCode,
    );
    if (profile != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('brief_pr')
            .add(response.toFirestore());
      } catch (_) {}
    }
    if (mounted) {
      await AnalyticsScope.of(context).logBriefPrSkipped(
        agentId: widget.agentId,
        isAnchorPrompt: widget.isAnchorPrompt,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.agentDisplayName;
    return Scaffold(
      appBar: AppBar(
        title: const Text('一啲簡短回饋'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              '頭先同 $name 嘅對話：',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '揀一個位置最似你嘅感受。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            _SliderRow(
              label: '$name 明白我。',
              leftAnchor: '完全唔係咁',
              rightAnchor: '完全係咁',
              value: _understanding,
              onChanged: (v) => setState(() {
                _understanding = v;
                _touched.add(0);
              }),
            ),
            const SizedBox(height: 28),
            _SliderRow(
              label: '$name 尊重我。',
              leftAnchor: '完全唔係咁',
              rightAnchor: '完全係咁',
              value: _validation,
              onChanged: (v) => setState(() {
                _validation = v;
                _touched.add(1);
              }),
            ),
            const SizedBox(height: 28),
            _SliderRow(
              label: '$name 關心我。',
              leftAnchor: '完全唔係咁',
              rightAnchor: '完全係咁',
              value: _caring,
              onChanged: (v) => setState(() {
                _caring = v;
                _touched.add(2);
              }),
            ),
            const SizedBox(height: 32),
            Divider(color: theme.colorScheme.outlineVariant, thickness: 1),
            const SizedBox(height: 24),
            _SliderRow(
              label: '$name 嘅回應好似搞錯重點，或者唔在乎。',
              leftAnchor: '完全唔係咁',
              rightAnchor: '好係咁',
              value: _insensitivity,
              onChanged: (v) => setState(() {
                _insensitivity = v;
                _touched.add(3);
              }),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('完成'),
              ),
            ),
            if (_skipVisible && !widget.isAnchorPrompt) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _skip,
                  child: const Text('跳過', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String leftAnchor;
  final String rightAnchor;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.leftAnchor,
    required this.rightAnchor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            showValueIndicator: ShowValueIndicator.never,
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 100,
            onChanged: onChanged,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                leftAnchor,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              rightAnchor,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

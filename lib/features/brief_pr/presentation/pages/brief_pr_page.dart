/// Brief PR (Perceived Partner Responsiveness) modal page.
///
/// Sprint 1 §3 + scale change C1 (2026-06): 4 items, each a 1–7 DISCRETE
/// labelled scale (was a 0–100 continuous slider). No continuous track, no
/// pre-selected default — the participant must actively tap a number 1–7.
/// Endpoints + midpoint are labelled and the numbers are visible. Submit is
/// blocked until all four items are answered (or the battery is skipped).
/// Skip is suppressed for the anchor prompt. Values are stored RAW (S4 is
/// not reverse-scored here).

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
  // null = not yet answered (no pre-selected default, per spec §4).
  int? _understanding;
  int? _validation;
  int? _caring;
  int? _insensitivity;

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

  bool get _canSubmit =>
      _understanding != null &&
      _validation != null &&
      _caring != null &&
      _insensitivity != null &&
      !_saving;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    final armCode = Arm.of(context)?.code ?? 'B';
    final response = BriefPrResponse(
      agentId: widget.agentId,
      agentDisplayName: widget.agentDisplayName,
      sessionRef: widget.sessionRef,
      understanding: _understanding,
      validation: _validation,
      caring: _caring,
      insensitivity: _insensitivity,
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
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final name = widget.agentDisplayName;
    // Endpoint + midpoint anchors. Kept generic so they fit the existing
    // Sprint 1 stems verbatim; the coupled wording proposed in the C1 ticket
    // (完全唔〔明白/認同/關心〕 · 一半半 · 非常〔…〕) is pending PI / cognitive
    // interview sign-off (protocol §6.4) before it can replace these.
    final posLeft = isEn ? 'Not at all' : '完全唔係咁';
    final posMid = isEn ? 'Halfway' : '一半半';
    final posRight = isEn ? 'Very much' : '完全係咁';
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'A quick check-in' : '一啲簡短回饋'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              isEn ? 'Your conversation with $name just now:' : '頭先同 $name 嘅對話：',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'Tap the number (1–7) that best matches how you felt.'
                  : '撳一個數字（1–7），最似你嘅感受。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            _LikertRow(
              label: isEn ? '$name understood me.' : '$name 明白我。',
              leftAnchor: posLeft,
              midAnchor: posMid,
              rightAnchor: posRight,
              value: _understanding,
              onChanged: (v) => setState(() => _understanding = v),
            ),
            const SizedBox(height: 28),
            _LikertRow(
              label: isEn ? '$name respected me.' : '$name 尊重我。',
              leftAnchor: posLeft,
              midAnchor: posMid,
              rightAnchor: posRight,
              value: _validation,
              onChanged: (v) => setState(() => _validation = v),
            ),
            const SizedBox(height: 28),
            _LikertRow(
              label: isEn ? '$name cared about me.' : '$name 關心我。',
              leftAnchor: posLeft,
              midAnchor: posMid,
              rightAnchor: posRight,
              value: _caring,
              onChanged: (v) => setState(() => _caring = v),
            ),
            const SizedBox(height: 32),
            Divider(color: theme.colorScheme.outlineVariant, thickness: 1),
            const SizedBox(height: 24),
            _LikertRow(
              label: isEn
                  ? '$name\'s response seemed to miss the point or feel indifferent.'
                  : '$name 嘅回應好似搞錯重點，或者唔在乎。',
              // S4 is negatively worded; anchors run none → very much.
              leftAnchor: isEn ? 'Not at all' : '完全唔係咁',
              midAnchor: isEn ? 'A little' : '有少少',
              rightAnchor: isEn ? 'Very much' : '好係咁',
              value: _insensitivity,
              onChanged: (v) => setState(() => _insensitivity = v),
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
                    : Text(isEn ? 'Done' : '完成'),
              ),
            ),
            if (_skipVisible && !widget.isAnchorPrompt) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _skip,
                  child: Text(isEn ? 'Skip' : '跳過', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One Brief-PR item: a stem followed by a 1–7 discrete control with the
/// numbers shown and endpoint/midpoint labels beneath. No default selection.
class _LikertRow extends StatelessWidget {
  final String label;
  final String leftAnchor;
  final String midAnchor;
  final String rightAnchor;
  final int? value;
  final ValueChanged<int> onChanged;

  const _LikertRow({
    required this.label,
    required this.leftAnchor,
    required this.midAnchor,
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
        const SizedBox(height: 12),
        Row(
          children: [
            for (var n = 1; n <= 7; n++) ...[
              Expanded(
                child: _NumberStop(
                  number: n,
                  selected: value == n,
                  onTap: () => onChanged(n),
                ),
              ),
              if (n < 7) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                leftAnchor,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                midAnchor,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                rightAnchor,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberStop extends StatelessWidget {
  final int number;
  final bool selected;
  final VoidCallback onTap;

  const _NumberStop({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: selected ? 2 : 1.4,
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

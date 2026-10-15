/// T25 (C14) — Brief PR v2 questionnaire: one question per screen.
///
/// Opened only from the invitation card's 「好呀」.  Shows "N/4", the stem
/// 今次傾偈, the same four items and 1–7 scale as the popup
/// [BriefPrPage] (items copied from there, raw scores, insensitivity not
/// reversed), each point as a full-width row, separate next / submit
/// buttons, back (previous question) and abandon.  Button labels that
/// exist in the App are kept (完成); labels not in docs/spec/copy/ are
/// `【占位】` drafts.
///
/// The answers go through [BriefPrScheduler.submit]: all four →
/// `completed`; abandoned with some answers → `partially_completed`; with
/// none → `skipped`.  The record is keyed by session id, so a second
/// submission is impossible.  Nothing here touches memory or the chat.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/brief_pr_record.dart';
import '../../data/brief_pr_scheduler.dart';
import '../../data/brief_pr_v2.dart';

class BriefPrItem {
  const BriefPrItem(this.key, this.stem, this.low, this.mid, this.high);
  final String key;
  final String Function(String name) stem;
  final String low;
  final String mid;
  final String high;
}

/// The four items, wording identical to the popup page.
const briefPrItems = <BriefPrItem>[
  BriefPrItem('understanding', _understood, '完全唔係咁', '一半半', '完全係咁'),
  BriefPrItem('validation', _respected, '完全唔係咁', '一半半', '完全係咁'),
  BriefPrItem('caring', _cared, '完全唔係咁', '一半半', '完全係咁'),
  BriefPrItem('insensitivity', _missed, '完全唔係咁', '有少少', '好係咁'),
];

String _understood(String n) => '$n 明白我。';
String _respected(String n) => '$n 尊重我。';
String _cared(String n) => '$n 關心我。';
String _missed(String n) => '$n 嘅回應好似搞錯重點，或者唔在乎。';

class BriefPrFlowPage extends StatefulWidget {
  const BriefPrFlowPage({
    super.key,
    required this.record,
    this.scheduler,
  });

  final BriefPrRecord record;

  /// Defaults to [BriefPrV2.scheduler].
  final BriefPrScheduler? scheduler;

  static const stem = '今次傾偈';
  static const nextLabel = '下一題';
  static const submitLabel = '完成';
  static const backLabel = '上一題';
  static const abandonLabel = '唔評住';
  static const pickHint = '撳一個數字（1–7），最似你嘅感受。';

  @override
  State<BriefPrFlowPage> createState() => _BriefPrFlowPageState();
}

class _BriefPrFlowPageState extends State<BriefPrFlowPage> {
  int _index = 0;
  final Map<String, int?> _answers = {};
  bool _saving = false;

  BriefPrScheduler get _scheduler => widget.scheduler ?? BriefPrV2.scheduler();

  bool get _isLast => _index == briefPrItems.length - 1;
  BriefPrItem get _item => briefPrItems[_index];
  int? get _value => _answers[_item.key];

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    try {
      await _scheduler.submit(widget.record, _answers);
    } catch (e) {
      // The Firestore SDK keeps the write queued offline and the record is
      // keyed by session id, so a later retry cannot duplicate it.
      if (kDebugMode) debugPrint('[BriefPrFlowPage] submit failed: $e');
    } finally {
      BriefPrV2.notifyChanged();
    }
    if (mounted && nav.canPop()) nav.pop();
  }

  void _next() {
    if (_value == null) return;
    if (_isLast) {
      _finish();
    } else {
      setState(() => _index++);
    }
  }

  void _back() {
    if (_index == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.record.agentDisplayName;
    final item = _item;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back key / gesture: previous question, or abandon on the first.
        if (_index > 0) {
          setState(() => _index--);
        } else {
          _finish();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('brief_pr_back'),
            tooltip: BriefPrFlowPage.backLabel,
            icon: const Icon(Icons.arrow_back),
            onPressed: _saving ? null : _back,
          ),
          title: Text(
            '${_index + 1}/${briefPrItems.length}',
            key: const Key('brief_pr_progress'),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: ListView(
            // 10/15: a new key per question so 下一題 starts at the top.
            key: ValueKey('brief_pr_question_$_index'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Text(
                BriefPrFlowPage.stem,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.stem(name),
                key: const Key('brief_pr_item_text'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                BriefPrFlowPage.pickHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              for (var v = 1; v <= 7; v++) ...[
                _OptionRow(
                  value: v,
                  label: v == 1
                      ? item.low
                      : v == 4
                          ? item.mid
                          : v == 7
                              ? item.high
                              : null,
                  selected: _value == v,
                  onTap: _saving
                      ? null
                      : () => setState(() => _answers[item.key] = v),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('brief_pr_next'),
                  onPressed: _value == null || _saving ? null : _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  child: Text(_isLast
                      ? BriefPrFlowPage.submitLabel
                      : BriefPrFlowPage.nextLabel),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  key: const Key('brief_pr_abandon'),
                  onPressed: _saving ? null : _finish,
                  style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48)),
                  child: const Text(BriefPrFlowPage.abandonLabel,
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('brief_pr_option_$value'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '$value',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    label ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: cs.primary, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

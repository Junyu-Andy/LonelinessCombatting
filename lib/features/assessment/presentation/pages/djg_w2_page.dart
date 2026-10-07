/// T18 — Week 2 DJG, 6 items, one item per screen (decision 0027).
///
/// Tap an answer → saved and on to the next item.  「上一題」 goes back,
/// 「跳過呢題」 records `skipped`.  After item 6 a last screen submits.
/// Every step is saved, so leaving half-way keeps the answers and the
/// home card resumes at the first unanswered item.  No arm check: both
/// arms get exactly this page.
///
/// Screen text other than the items and the three answers is a draft for
/// the research team to sign off (docs/dev-reports/T18-djg-w2-20261007.md).
library;

import 'package:flutter/material.dart';

import '../../data/djg_w2.dart';

class DjgW2Page extends StatefulWidget {
  final DjgW2Store store;
  const DjgW2Page({super.key, required this.store});

  @override
  State<DjgW2Page> createState() => _DjgW2PageState();
}

class _DjgW2PageState extends State<DjgW2Page> {
  final Map<String, String> _answers = {};
  int _index = 0;
  bool _loading = true;
  bool _closed = false;
  bool _started = false;
  bool _submitting = false;

  static const _items = DjgW2Items.items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _answers.addAll(saved.answers);
      _started = saved.hasStarted;
      _closed = saved.isClosed;
      final next = _items.indexWhere((it) => !_answers.containsKey(it.id));
      _index = next < 0 ? _items.length : next;
      _loading = false;
    });
  }

  void _record(String value) {
    final it = _items[_index];
    _answers[it.id] = value;
    widget.store.save(_answers, submit: false, first: !_started);
    _started = true;
    setState(() => _index++);
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // Items never reached count as skipped.
    for (final it in _items) {
      _answers.putIfAbsent(it.id, () => DjgW2Items.skipped);
    }
    await widget.store.save(_answers, submit: true, first: !_started);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_closed) {
      body = _Message(text: '呢份問卷已經完成或者已經截止，唔使再答。', theme: theme);
    } else if (_index >= _items.length) {
      body = _SubmitScreen(
        submitting: _submitting,
        onSubmit: _submit,
        onBack: _back,
      );
    } else {
      body = _ItemScreen(
        key: ValueKey(_items[_index].id),
        index: _index,
        total: _items.length,
        item: _items[_index],
        selected: _answers[_items[_index].id],
        onAnswer: _record,
        onSkip: () => _record(DjgW2Items.skipped),
        onBack: _index > 0 ? _back : null,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('第 2 週問卷')),
      body: SafeArea(child: body),
    );
  }
}

class _ItemScreen extends StatelessWidget {
  final int index;
  final int total;
  final DjgW2Item item;
  final String? selected;
  final ValueChanged<String> onAnswer;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  const _ItemScreen({
    super.key,
    required this.index,
    required this.total,
    required this.item,
    required this.selected,
    required this.onAnswer,
    required this.onSkip,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('第 ${index + 1} 題（共 $total 題）',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: (index + 1) / total, minHeight: 6),
        const SizedBox(height: 20),
        if (index == 0) ...[
          Text('每句揀一個最啱你最近情況嘅答案。',
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5)),
          const SizedBox(height: 16),
        ],
        Text(item.text,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.4)),
        const SizedBox(height: 28),
        for (final opt in DjgW2Items.options) ...[
          _OptionButton(
            label: opt.$2,
            selected: selected == opt.$1,
            onTap: () => onAnswer(opt.$1),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                child: const Text('上一題', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
                child: const Text('跳過呢題', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubmitScreen extends StatelessWidget {
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  const _SubmitScreen({required this.submitting, required this.onSubmit, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Text('答完喇，多謝你！撳「提交」就完成。',
            style: theme.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1.4)),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
          child: const Text('提交', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: submitting ? null : onBack,
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
          child: const Text('上一題', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final ThemeData theme;
  const _Message({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 20, height: 1.5)),
        ),
      );
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
          height: 64,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

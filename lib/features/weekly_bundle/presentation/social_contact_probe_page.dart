/// T24 — weekly social-contact probe (S12), the last part of the weekly
/// bundle when `app_config/phase_b.socialContactProbeEnabled` is on.
///
/// Two items, one per screen, four options each, raw value 0–3; the item
/// text, options and footnote are copied verbatim from
/// docs/spec/copy/short-texts.md S12.  Every answer is saved; leaving
/// half-way resumes at the first unanswered item.  No arm check.  Screen
/// text is final since 10/15 (docs/spec/copy S14).
library;

import 'package:flutter/material.dart';

import '../data/weekly_bundle.dart';
import 'weekly_part_header.dart';

class SocialContactProbePage extends StatefulWidget {
  const SocialContactProbePage({
    super.key,
    required this.store,
    this.part,
    this.title = '過去 7 日同人見面、聯絡',
  });

  final SocialContactStore store;
  final WeeklyPartPosition? part;
  final String title;

  @override
  State<SocialContactProbePage> createState() => _SocialContactProbePageState();
}

class _SocialContactProbePageState extends State<SocialContactProbePage> {
  final Map<String, int> _answers = {};
  int _index = 0;
  bool _loading = true;
  bool _closed = false;
  bool _started = false;
  bool _submitting = false;

  static const _items = SocialContactItems.items;

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

  Future<void> _record(int value) async {
    final it = _items[_index];
    _answers[it.id] = value;
    final last = _index >= _items.length - 1;
    if (last) {
      if (_submitting) return;
      setState(() => _submitting = true);
      await widget.store.save(_answers, submit: true, first: !_started);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    widget.store.save(_answers, submit: false, first: !_started);
    _started = true;
    setState(() => _index++);
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_closed) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('呢份問卷已經完成或者已經截止，唔使再答。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontSize: 20, height: 1.5)),
        ),
      );
    } else {
      final i = _index.clamp(0, _items.length - 1);
      final item = _items[i];
      body = ListView(
        key: ValueKey(item.id),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('第 ${i + 1} 題（共 ${_items.length} 題）',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: (i + 1) / _items.length, minHeight: 6),
          const SizedBox(height: 20),
          Text(item.text,
              key: const ValueKey('s12_item'),
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 24, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 10),
          Text(SocialContactItems.footnote,
              key: const ValueKey('s12_footnote'),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          for (final opt in SocialContactItems.options) ...[
            _OptionButton(
              label: opt.$2,
              selected: _answers[item.id] == opt.$1,
              onTap: _submitting ? null : () => _record(opt.$1),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: i > 0 ? _back : null,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
            child: const Text('上一題', style: TextStyle(fontSize: 18)),
          ),
        ],
      );
    }
    final part = widget.part;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            if (part != null) WeeklyPartHeader(part: part),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _OptionButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
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

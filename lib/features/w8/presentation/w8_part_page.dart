/// T35 — one part of the W8 questionnaire, one question per screen
/// (handover 1021-W8 二 (2)).  The frame, buttons and words around the
/// questions are those of the W1–W3 weekly questionnaire's DJG-ES page
/// (lib/features/assessment/presentation/pages/djg_w2_page.dart): 「第 i 題
/// （共 n 題）」, a progress bar, big answer buttons, 「上一題」「跳過呢題」,
/// then 「答完喇，多謝你！撳「提交」就完成。」 and 「提交」.  The W1–W3 page itself
/// is not touched.
///
/// Tap an answer → saved at once (with its time) and on to the next one;
/// 「跳過呢題」 stores `skipped`; questions never reached are stored as
/// skipped on 「提交」.  Leaving half-way keeps every answer; the part
/// reopens at the first unanswered question.  The instruction sits above
/// the first question; a lead line (DJG-ES q4, LSNS-6 q1 and q4) above
/// its question; PGIC's hint under it.  Both arms get exactly this page;
/// nothing here reads the arm or calls a model.
library;

import 'package:flutter/material.dart';

import '../../../core/survey/direction_cue.dart';
import '../../weekly_bundle/presentation/weekly_part_header.dart';
import '../data/w8_items.dart';
import '../data/w8_store.dart';

class W8PartPage extends StatefulWidget {
  const W8PartPage({
    super.key,
    required this.spec,
    required this.store,
    this.part,
  });

  final W8PartSpec spec;
  final W8Store store;

  /// 「第 n 部分，共 5 部分」; null for the optional AIMHS.
  final WeeklyPartPosition? part;

  @override
  State<W8PartPage> createState() => _W8PartPageState();
}

class _W8PartPageState extends State<W8PartPage> {
  final Map<String, Object> _answers = {};
  int _index = 0;
  bool _loading = true;
  bool _closed = false;
  bool _started = false;
  bool _submitting = false;

  List<W8Item> get _items => widget.spec.items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.store.load(widget.spec.part);
    if (!mounted) return;
    setState(() {
      _answers.addAll(saved.answers);
      _started = saved.hasStarted || saved.status != null;
      _closed = saved.isClosed;
      final next = _items.indexWhere((it) => !_answers.containsKey(it.id));
      _index = next < 0 ? _items.length : next;
      _loading = false;
    });
  }

  void _record(Object value) {
    final it = _items[_index];
    _answers[it.id] = value;
    widget.store.saveAnswer(widget.spec.part, Map.of(_answers), it.id,
        first: !_started);
    _started = true;
    setState(() => _index++);
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // Questions never reached count as skipped.
    final newlySkipped = <String>[];
    for (final it in _items) {
      if (!_answers.containsKey(it.id)) {
        _answers[it.id] = W8Items.skipped;
        newlySkipped.add(it.id);
      }
    }
    await widget.store.submit(widget.spec.part, Map.of(_answers),
        first: !_started, newlySkipped: newlySkipped);
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
      final it = _items[_index];
      body = _ItemScreen(
        key: ValueKey('w8_${widget.spec.part.name}_${it.id}'),
        index: _index,
        total: _items.length,
        spec: widget.spec,
        item: it,
        selected: _answers[it.id],
        onAnswer: _record,
        onSkip: () => _record(W8Items.skipped),
        onBack: _index > 0 ? _back : null,
      );
    }
    final part = widget.part;
    return Scaffold(
      appBar: AppBar(title: Text(widget.spec.title)),
      body: SafeArea(
        child: part == null
            ? body
            : Column(children: [
                WeeklyPartHeader(part: part),
                Expanded(child: body),
              ]),
      ),
    );
  }
}

class _ItemScreen extends StatelessWidget {
  const _ItemScreen({
    super.key,
    required this.index,
    required this.total,
    required this.spec,
    required this.item,
    required this.selected,
    required this.onAnswer,
    required this.onSkip,
    required this.onBack,
  });

  final int index;
  final int total;
  final W8PartSpec spec;
  final W8Item item;
  final Object? selected;
  final ValueChanged<Object> onAnswer;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instruction = spec.instruction;
    final lead = item.lead;
    final hint = spec.hint;
    return ListView(
      key: const ValueKey('w8_item_list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('第 ${index + 1} 題（共 $total 題）',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: (index + 1) / total, minHeight: 6),
        const SizedBox(height: 20),
        if (index == 0 && instruction != null) ...[
          Text(instruction,
              key: const ValueKey('w8_instruction'),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontSize: 18, height: 1.5)),
          const SizedBox(height: 16),
        ],
        // Handover 二 (4): the line before DJG-ES q4 and LSNS-6 q1 / q4,
        // plain, the same style as the W1–W3 DJG q4 line.
        if (lead != null) ...[
          DirectionCue(key: const ValueKey('w8_lead'), text: lead),
          const SizedBox(height: 10),
        ],
        Text(item.text,
            key: const ValueKey('w8_question'),
            style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 26, fontWeight: FontWeight.w700, height: 1.4)),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint,
              key: const ValueKey('w8_hint'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              )),
        ],
        const SizedBox(height: 28),
        for (final opt in spec.options) ...[
          _OptionButton(
            key: ValueKey('w8_option_${opt.value}'),
            label: opt.label,
            selected: selected == opt.value,
            onTap: () => onAnswer(opt.value),
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
                key: const ValueKey('w8_skip'),
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
  const _SubmitScreen(
      {required this.submitting, required this.onSubmit, required this.onBack});

  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Text('答完喇，多謝你！撳「提交」就完成。',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontSize: 24, height: 1.4)),
        const SizedBox(height: 32),
        FilledButton(
          key: const ValueKey('w8_submit'),
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 60)),
          child: const Text('提交', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: submitting ? null : onBack,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56)),
          child: const Text('上一題', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontSize: 20, height: 1.5)),
        ),
      );
}

/// The W1–W3 answer button: full width, 64 high.  At the largest App text
/// a long label (LSNS-6 「九個或以上」, CI 「1 非常不同意」) still fits on
/// one line on a 360-wide phone; a longer one grows the button instead of
/// being cut.
class _OptionButton extends StatelessWidget {
  const _OptionButton(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
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

/// T30 — paper DJG-ES (W4) entry by the assessor: one item per screen,
/// the three approved answers plus 缺答, assessment date and mode, then a
/// summary and TWO confirmations before `submitOutcomeEntry`.  The server
/// scores; this page never shows a score.  Items and answers come from
/// `DjgW2Items` (questionnaire package §3, verbatim — the same constants
/// the in-App W2 uses; `docs/spec/instruments/djg_es.md`).
library;

import 'package:flutter/material.dart';

import '../../assessment/data/djg_w2.dart';
import '../data/assessor_service.dart';

/// Mode of administration (stored value → label).
const assessmentModes = <(String, String)>[
  ('in_person', '當面'),
  ('phone', '電話'),
  ('video', '視像'),
];

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class OutcomeEntryPage extends StatefulWidget {
  final String researchId;
  final AssessorBackend backend;
  final DateTime Function()? today;

  const OutcomeEntryPage({
    super.key,
    required this.researchId,
    required this.backend,
    this.today,
  });

  @override
  State<OutcomeEntryPage> createState() => _OutcomeEntryPageState();
}

class _OutcomeEntryPageState extends State<OutcomeEntryPage> {
  // Step 0 = date + mode; 1..6 = items; 7 = summary.
  int _step = 0;
  late DateTime _date = (widget.today ?? DateTime.now)();
  String? _mode;
  final Map<String, String> _answers = {};
  bool _busy = false;
  String? _error;

  static const _items = DjgW2Items.items;

  bool get _onSummary => _step == _items.length + 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.researchId}　W4 DJG-ES'),
        leading: _step > 0
            ? IconButton(
                key: const Key('entry_back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _step == 0
            ? _dateAndMode(context)
            : _onSummary
                ? _summary(context)
                : _item(context, _items[_step - 1]),
      ),
    );
  }

  Widget _dateAndMode(BuildContext context) {
    return ListView(
      children: [
        Text('施測日期', style: Theme.of(context).textTheme.titleMedium),
        OutlinedButton.icon(
          key: const Key('entry_date'),
          icon: const Icon(Icons.event),
          label: Text(_dateKey(_date)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2026, 1, 1),
              lastDate: (widget.today ?? DateTime.now)(),
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
        const SizedBox(height: 20),
        Text('施測方式', style: Theme.of(context).textTheme.titleMedium),
        for (final (code, label) in assessmentModes)
          _Choice(
            key: Key('entry_mode_$code'),
            label: label,
            selected: _mode == code,
            onTap: () => setState(() => _mode = code),
          ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('entry_next'),
          onPressed: _mode == null ? null : () => setState(() => _step = 1),
          child: const Text('下一題'),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, DjgW2Item item) {
    final n = _step;
    final current = _answers[item.id];
    return ListView(
      children: [
        Text('第 $n 題，共 ${_items.length} 題',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(item.text,
            key: Key('entry_item_${item.id}'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        for (final (value, label) in DjgW2Items.options)
          _Choice(
            key: Key('entry_${item.id}_$value'),
            label: label,
            selected: current == value,
            onTap: () => _answer(item.id, value),
          ),
        _Choice(
          key: Key('entry_${item.id}_skipped'),
          label: '缺答（紙本冇填）',
          selected: current == DjgW2Items.skipped,
          onTap: () => _answer(item.id, DjgW2Items.skipped),
        ),
      ],
    );
  }

  void _answer(String id, String value) {
    setState(() {
      _answers[id] = value;
      _step++;
    });
  }

  Widget _summary(BuildContext context) {
    String label(String id) {
      final v = _answers[id];
      if (v == null || v == DjgW2Items.skipped) return '缺答';
      return DjgW2Items.options.firstWhere((o) => o.$1 == v).$2;
    }

    final modeLabel =
        assessmentModes.firstWhere((m) => m.$1 == _mode).$2;
    return ListView(
      children: [
        Text('請核對後提交', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('研究編號 ${widget.researchId}　施測日期 ${_dateKey(_date)}　'
            '方式 $modeLabel'),
        const Divider(),
        for (final item in _items)
          ListTile(
            dense: true,
            title: Text(item.text),
            trailing: Text(label(item.id),
                key: Key('summary_${item.id}'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!,
                key: const Key('entry_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('entry_submit'),
          onPressed: _busy ? null : _confirmAndSubmit,
          child: Text(_busy ? '提交中…' : '提交'),
        ),
      ],
    );
  }

  /// Two confirmations (task §3.3): a dialog, then a second dialog that
  /// repeats the research ID and the count of missing items.
  Future<void> _confirmAndSubmit() async {
    final missing = _answers.values.where((v) => v == DjgW2Items.skipped).length;
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認提交？'),
        content: Text('${widget.researchId} 的 W4 DJG-ES，共 ${_items.length} 題'
            '${missing > 0 ? '，$missing 題缺答' : ''}。提交後唔可以再改。'),
        actions: [
          TextButton(
              key: const Key('confirm1_cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回檢查')),
          FilledButton(
              key: const Key('confirm1_ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認')),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再確認一次'),
        content: Text('研究編號 ${widget.researchId}，施測日期 ${_dateKey(_date)}。'
            '確定係呢位參加者嘅紙本？'),
        actions: [
          TextButton(
              key: const Key('confirm2_cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('唔係，返回')),
          FilledButton(
              key: const Key('confirm2_ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('係，提交')),
        ],
      ),
    );
    if (second != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.backend.submit(OutcomeEntryInput(
        researchId: widget.researchId,
        instrument: 'DJG-ES',
        timepoint: 'W4',
        assessmentDate: _dateKey(_date),
        mode: _mode!,
        answers: {for (final it in _items) it.id: _answers[it.id] ?? 'skipped'},
      ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已錄入'),
          content: Text(r.outOfWindow
              ? '已記錄（施測日期在窗口之外，已標「超窗」）。'
              : '已記錄。'),
          actions: [
            FilledButton(
                key: const Key('entry_done'),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('返回名單')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AssessorError catch (e) {
      setState(() => _error = assessorErrorText(e.code));
    } catch (_) {
      setState(() => _error = assessorErrorText('submit_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// One selectable answer row (large tap target; no deprecated radio API).
class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Choice(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off),
      title: Text(label),
      minTileHeight: 56,
      onTap: onTap,
    );
  }
}

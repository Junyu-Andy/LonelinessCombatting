/// T35 — the W8 questionnaire as one flow (handover 1021-W8 二; decision
/// 0036).  Same frame, buttons and status words as the W1–W3 weekly
/// questionnaire (weekly_bundle_flow_page.dart):
///
///   最後一份問卷 (title) → 開頭 (5 parts, about 8 minutes) and the five parts
///   with 未開始 / 未做完 / 已完成 → 「開始」 / 「繼續」 → part 1 … part 5, each
///   with 「第 N 部分，共 5 部分」 → 完成 「全部做完喇，多謝你！仲有一份可以選擇
///   唔填嘅短問卷。」 with 「填呢份」 (AIMHS) and 「唔填喇」.
///
/// Each part saves on its own; opening again jumps to the first part not
/// done, at its first unanswered question.  Five parts done = W8 done;
/// AIMHS is optional (「唔填喇」 records `declined`; leaving it does not make
/// W8 incomplete).  After AIMHS is filled or declined the page shows the
/// W1–W3 done state 「全部做完喇，多謝你！」 / 「完成」.  No PHQ-9, no GAD-7, no
/// alert entry (handover 二 (5)), and none of the phase_b_probes.  Both
/// arms get exactly this page; no arm check, no model.
library;

import 'package:flutter/material.dart';

import '../../weekly_bundle/presentation/weekly_part_header.dart';
import '../data/w8_items.dart';
import '../data/w8_store.dart';
import 'w8_part_page.dart';

class W8FlowPage extends StatefulWidget {
  const W8FlowPage({
    super.key,
    required this.store,
    this.initialStatus,
  });

  final W8Store store;

  /// Statuses the home card already read (saves one round trip).
  final Map<W8Part, String?>? initialStatus;

  /// Tester preview (測試員工具): the real pages in the real order, kept
  /// in memory only — nothing is saved, so it can be repeated.
  static W8FlowPage preview({Key? key}) =>
      W8FlowPage(key: key, store: MemoryW8Store());

  /// A signed-in participant.
  static W8FlowPage forUser(String uid,
          {Key? key, Map<W8Part, String?>? initialStatus}) =>
      W8FlowPage(
          key: key,
          store: FirestoreW8Store(uid),
          initialStatus: initialStatus);

  @override
  State<W8FlowPage> createState() => _W8FlowPageState();
}

class _W8FlowPageState extends State<W8FlowPage> {
  final Map<W8Part, String?> _status = {};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialStatus;
    if (init != null) {
      _status.addAll(init);
      _loading = false;
    }
    _reload();
  }

  Future<void> _reload() async {
    try {
      final s = await widget.store.statuses();
      for (final p in W8Part.values) {
        // A part done here stays done until the store catches up
        // (offline queue).
        if (W8Status.isFinal(_status[p])) continue;
        _status[p] = s[p];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<W8PartSpec> get _parts => W8Items.parts;

  bool _isFinal(W8Part p) => W8Status.isFinal(_status[p]);

  int? get _nextIndex {
    for (var i = 0; i < _parts.length; i++) {
      if (!_isFinal(_parts[i].part)) return i;
    }
    return null;
  }

  bool get _started => _parts.any((p) => _status[p.part] != null);

  Future<bool?> _open(W8PartSpec spec, WeeklyPartPosition? pos) =>
      Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => W8PartPage(spec: spec, store: widget.store, part: pos),
      ));

  Future<void> _run() async {
    var i = _nextIndex;
    while (i != null) {
      if (!mounted) return;
      final spec = _parts[i];
      final done = await _open(spec, (i + 1, _parts.length));
      if (!mounted) return;
      if (done == true) {
        _status[spec.part] = W8Status.submitted;
      } else {
        _status[spec.part] ??= W8Status.inProgress;
      }
      setState(() {});
      await _reload();
      // Back out of a part (not finished) = stop here; resume later.
      if (done != true) return;
      i = _nextIndex;
    }
  }

  Future<void> _fillAimhs() async {
    final done = await _open(W8Items.aimhs, null);
    if (!mounted) return;
    if (done == true) {
      _status[W8Part.aimhs] = W8Status.submitted;
    } else {
      _status[W8Part.aimhs] ??= W8Status.inProgress;
    }
    setState(() {});
    await _reload();
  }

  Future<void> _declineAimhs() async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await widget.store.load(W8Part.aimhs);
    await widget.store.decline(W8Part.aimhs, Map.of(saved.answers));
    _status[W8Part.aimhs] = W8Status.declined;
    if (!mounted) return;
    Navigator.of(context).maybePop(true);
  }

  String _statusLabel(W8Part p) {
    final s = _status[p];
    // The W1–W3 words (10/15 item 6 C(6)).
    if (s == null) return '未開始';
    if (s == W8Status.inProgress) return '未做完';
    if (s == W8Status.missed) return '已過時間';
    return '已完成';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _nextIndex;
    final partsDone = next == null;
    final aimhsOpen = partsDone && !_isFinal(W8Part.aimhs);
    final String heading;
    if (!partsDone) {
      heading = W8Texts.intro;
    } else if (aimhsOpen) {
      heading = W8Texts.done;
    } else {
      // The W1–W3 done words.
      heading = '全部做完喇，多謝你！';
    }
    return Scaffold(
      appBar: AppBar(title: const Text(W8Texts.title)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          heading,
                          key: const ValueKey('w8_heading'),
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              height: 1.5,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 18),
                        for (var i = 0; i < _parts.length; i++)
                          Card(
                            child: ListTile(
                              key: ValueKey('w8_part_$i'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Icon(
                                _isFinal(_parts[i].part)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: theme.colorScheme.primary,
                                size: 30,
                              ),
                              title: Text(
                                '第 ${i + 1} 部分：${_parts[i].title}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(_statusLabel(_parts[i].part),
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: _buttons(next, aimhsOpen),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buttons(int? next, bool aimhsOpen) {
    Widget big(String key, String label, VoidCallback? onTap,
            {bool filled = true}) =>
        filled
            ? FilledButton(
                key: ValueKey(key),
                onPressed: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(label, style: const TextStyle(fontSize: 18)),
                ),
              )
            : OutlinedButton(
                key: ValueKey(key),
                onPressed: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(label, style: const TextStyle(fontSize: 18)),
                ),
              );
    if (next != null) {
      return big('w8_start', _started ? '繼續' : '開始', _run);
    }
    if (aimhsOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          big('w8_fill', W8Texts.fill, _busy ? null : _fillAimhs),
          const SizedBox(height: 10),
          big('w8_decline', W8Texts.decline, _busy ? null : _declineAimhs,
              filled: false),
        ],
      );
    }
    return big('w8_done', '完成', () => Navigator.of(context).maybePop(true));
  }
}

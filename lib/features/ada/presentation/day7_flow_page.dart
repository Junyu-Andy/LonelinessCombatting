/// T17b (SPEC:C22, decision 0030) — the day-7 flow (ada.md §6.2–6.3).
///
/// One entry for everything the participant does on day 7.  This task
/// carries two parts — the ADA full form and the open questions — and
/// leaves room for Weekly PR and the usability items (EA260417).
///
///   intro (estimated time, list of parts) → part 1 → part 2 → done
///
/// Each part saves on its own (its own document, every screen).  Opening
/// the flow again jumps to the first part not yet submitted, and that
/// part reopens on the screen where it stopped.  Each part shows
/// 「第 N 部分，共 M 部分」 at the top.
///
/// [channel] `phone_by_staff` is the researcher's phone completion
/// (`ada_staff_page.dart`): same screens, written through the staff
/// callables.
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/agents/agent_registry.dart' show AgentGenderVariant;
import '../../../core/config/phase_a_schedule_config.dart';
import '../data/ada_gate.dart';
import '../data/ada_items.dart';
import '../data/survey_draft_store.dart';
import 'ada_page.dart';
import 'ada_widgets.dart';
import 'day7_open_page.dart';

class Day7FlowPage extends StatefulWidget {
  const Day7FlowPage({
    super.key,
    required this.parts,
    required this.adaTimepoint,
    this.enrolmentDay,
    this.store,
    this.uid,
    this.variant,
    this.voiceEnabled,
    this.channel = AdaChannel.app,
    this.adaAllowSkip,
    this.openAllowSkip,
  });

  /// From [AdaGate.day7Parts]; never empty.
  final List<Day7Part> parts;
  final AdaTimepoint adaTimepoint;
  final int? enrolmentDay;
  final SurveyDraftStore? store;
  final String? uid;
  final AgentGenderVariant? variant;
  final bool? voiceEnabled;
  final String channel;
  final bool? adaAllowSkip;
  final bool? openAllowSkip;

  @override
  State<Day7FlowPage> createState() => _Day7FlowPageState();
}

class _Day7FlowPageState extends State<Day7FlowPage> {
  late final SurveyDraftStore _store =
      widget.store ?? FirestoreSurveyDraftStore();
  final Map<Day7Part, String?> _status = {}; // null | in_progress | submitted
  bool _loading = true;
  String? _uid;
  AgentGenderVariant? _variant;

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uid != null || !_loading) return;
    final profile = context
        .getInheritedWidgetOfExactType<AppSettingsScope>()
        ?.notifier
        ?.profile;
    _uid = widget.uid ?? profile?.uid;
    _variant = widget.variant ?? profile?.ahJanAhBakVariant;
    _reload();
  }

  (String, String) _docOf(Day7Part p) => p == Day7Part.ada
      ? (kAdaCollection, widget.adaTimepoint.id)
      : (kDay7OpenCollection, kDay7OpenDocId);

  Future<void> _reload() async {
    final uid = _uid;
    for (final p in widget.parts) {
      String? status;
      if (uid != null) {
        try {
          final (c, d) = _docOf(p);
          final doc = await _store.load(uid, c, d);
          status = doc?['status'] as String?;
        } catch (_) {
          status = null;
        }
      }
      _status[p] = status;
    }
    if (mounted) setState(() => _loading = false);
  }

  int? get _nextIndex {
    for (var i = 0; i < widget.parts.length; i++) {
      if (_status[widget.parts[i]] != 'submitted') return i;
    }
    return null;
  }

  bool get _started => _status.values.any((s) => s != null);

  Future<void> _run() async {
    var i = _nextIndex;
    while (i != null) {
      if (!mounted) return;
      final part = widget.parts[i];
      final pos = (i + 1, widget.parts.length);
      final route = MaterialPageRoute<bool>(
        builder: (_) => part == Day7Part.ada
            ? AdaPage(
                timepoint: widget.adaTimepoint,
                allowSkip: widget.adaAllowSkip ??
                    PhaseAScheduleConfig.current.adaAllowSkip,
                enrolmentDay: widget.enrolmentDay,
                store: _store,
                uid: _uid,
                variant: _variant,
                voiceEnabled: widget.voiceEnabled,
                channel: widget.channel,
                part: pos,
              )
            : Day7OpenPage(
                allowSkip: widget.openAllowSkip ??
                    PhaseAScheduleConfig.current.day7OpenEndedAllowSkip,
                enrolmentDay: widget.enrolmentDay,
                store: _store,
                uid: _uid,
                voiceEnabled: widget.voiceEnabled,
                channel: widget.channel,
                part: pos,
              ),
      );
      final done = await Navigator.of(context).push(route);
      await _reload();
      // Back out of a part (not submitted) = stop here; resume later.
      if (done != true) return;
      i = _nextIndex;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'submitted':
        return _isEn ? 'Done' : '已完成';
      case 'in_progress':
        return _isEn ? 'Started' : '做咗一半';
      default:
        return _isEn ? 'Not started' : '未開始';
    }
  }

  String _partTitle(Day7Part p) => p == Day7Part.ada
      ? (_isEn ? 'The three companions' : '三位陪伴者')
      : (_isEn ? 'A few open questions' : '幾條開放問題');

  @override
  Widget build(BuildContext context) {
    final isEn = _isEn;
    final theme = Theme.of(context);
    final minutes = PhaseAScheduleConfig.current.day7FlowMinutes;
    final next = _nextIndex;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel == AdaChannel.phoneByStaff
            ? (isEn ? 'Day 7 — phone (staff)' : '第 7 日問卷（電話代填）')
            : (isEn ? 'Day 7 questions' : '第 7 日問卷')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SurveyHelpButton(isEn: isEn),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          next == null
                              ? (isEn
                                  ? 'All done. Thank you!'
                                  : '全部做完喇，多謝你！')
                              : (isEn
                                  ? 'There are ${widget.parts.length} parts. '
                                      'You can stop any time; next time you '
                                      'carry on where you left off.'
                                  : '一共有 ${widget.parts.length} 部分。'
                                      '可以隨時停，下次會由停低嗰度繼續。'),
                          key: const ValueKey('day7_intro'),
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              height: 1.5,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          // ada.md §6.2: the number comes from the pilot run.
                          minutes == null
                              ? (isEn
                                  ? '[Placeholder] Estimated time: to be set '
                                      'after the pilot run'
                                  : '【占位】預計時間：試跑後再定')
                              : (isEn
                                  ? 'About $minutes minutes in total.'
                                  : '大約要 $minutes 分鐘。'),
                          key: const ValueKey('day7_estimate'),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 18),
                        for (var i = 0; i < widget.parts.length; i++)
                          Card(
                            child: ListTile(
                              key: ValueKey('day7_part_$i'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Icon(
                                _status[widget.parts[i]] == 'submitted'
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: theme.colorScheme.primary,
                                size: 30,
                              ),
                              title: Text(
                                isEn
                                    ? 'Part ${i + 1}: '
                                        '${_partTitle(widget.parts[i])}'
                                    : '第 ${i + 1} 部分：'
                                        '${_partTitle(widget.parts[i])}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                  _statusLabel(_status[widget.parts[i]]),
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
                      child: next == null
                          ? FilledButton(
                              key: const ValueKey('day7_done'),
                              onPressed: () =>
                                  Navigator.of(context).maybePop(true),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(isEn ? 'Finish' : '完成',
                                    style: const TextStyle(fontSize: 18)),
                              ),
                            )
                          : FilledButton(
                              key: const ValueKey('day7_start'),
                              onPressed: _run,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                    _started
                                        ? (isEn ? 'Continue' : '繼續')
                                        : (isEn ? 'Start' : '開始'),
                                    style: const TextStyle(fontSize: 18)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// T17 (SPEC:C22, decision 0026) — ADA, Phase A only.
///
/// One item per screen: intro → A (usage, 3 agents) → B (one screen per
/// trait) → C (one screen per scenario, full form only) → D (long text).
/// Back is always allowed.  Every screen change saves the draft to
/// `users/{uid}/ada_responses/{timepoint}`; submit sets
/// `status: "submitted"`, after which the rules freeze the document.
/// When [allowSkip] is on, 跳過 stores `"skipped"` for every item on the
/// screen that was not answered.
///
/// The old W2/W4 page (`agent_diff_page.dart`, `users/{uid}/agent_diff`)
/// is untouched.
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/agents/agent_registry.dart';
import '../../../core/config/phase_a_schedule_config.dart';
import '../../../core/safety/safety_check.dart';
import '../../../core/survey/likert_scale.dart';
import '../../../core/survey/long_text_answer.dart';
import '../../../core/survey/survey_item_card.dart';
import '../../../core/voice/voice_input_button.dart';
import '../data/ada_items.dart';
import '../data/survey_draft_store.dart';
import 'survey_nav_bar.dart';

enum _Kind { intro, usage, trait, scenario, free }

class _Screen {
  const _Screen(this.kind, [this.id = '']);
  final _Kind kind;
  final String id;
}

class AdaPage extends StatefulWidget {
  const AdaPage({
    super.key,
    required this.timepoint,
    this.allowSkip = true,
    this.enrolmentDay,
    this.store,
    this.uid,
    this.variant,
    this.voiceEnabled,
  });

  final AdaTimepoint timepoint;
  final bool allowSkip;
  final int? enrolmentDay;

  /// Defaults to Firestore.
  final SurveyDraftStore? store;

  /// Test / screenshot hooks; default to the signed-in profile.
  final String? uid;
  final AgentGenderVariant? variant;
  final bool? voiceEnabled;

  @override
  State<AdaPage> createState() => _AdaPageState();
}

class _AdaPageState extends State<AdaPage> {
  late final SurveyDraftStore _store =
      widget.store ?? FirestoreSurveyDraftStore();
  late final List<_Screen> _screens = [
    const _Screen(_Kind.intro),
    const _Screen(_Kind.usage),
    for (final t in AdaTraits.all) _Screen(_Kind.trait, t),
    if (widget.timepoint.form == AdaForm.full)
      for (final s in AdaScenarios.all) _Screen(_Kind.scenario, s),
    const _Screen(_Kind.free),
  ];

  final Map<String, Object> _usage = {};
  final Map<String, Map<String, Object>> _traits = {
    for (final t in AdaTraits.all) t: <String, Object>{},
  };
  final Map<String, Object> _scenarios = {};
  final _text = TextEditingController();
  final _voice = VoiceInputController();
  String? _freeTextStatus; // answered | skipped
  bool _usedVoice = false;
  int _voiceMs = 0;
  String _lastScanned = '';

  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  DateTime? _startedAt;
  // True once a stored draft already holds startedAt (merge keeps it).
  bool _startedAtStored = false;
  String? _uid;
  AgentGenderVariant? _variant;

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
    _restore();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final uid = _uid;
    Map<String, dynamic>? doc;
    if (uid != null) {
      try {
        doc = await _store.load(uid, kAdaCollection, widget.timepoint.id);
      } catch (_) {
        doc = null; // offline: start fresh, the next save merges
      }
    }
    if (!mounted) return;
    setState(() {
      if (doc != null) {
        _submitted = doc['status'] == 'submitted';
        _startedAtStored = doc['startedAt'] != null;
        _copyInto(_usage, doc['usage']);
        final traits = doc['traits'];
        if (traits is Map) {
          for (final t in AdaTraits.all) {
            _copyInto(_traits[t]!, traits[t]);
          }
        }
        _copyInto(_scenarios, doc['scenarios']);
        if (doc['freeText'] is String) _text.text = doc['freeText'] as String;
        _lastScanned = _text.text.trim();
        if (doc['freeTextInputMode'] == 'voice') _usedVoice = true;
        final last = doc['lastScreen'];
        if (last is num && !_submitted) {
          _index = last.toInt().clamp(0, _screens.length - 1);
        }
      }
      _loading = false;
    });
  }

  static void _copyInto(Map<String, Object> into, Object? raw) {
    if (raw is! Map) return;
    for (final e in raw.entries) {
      if (e.key is String && e.value != null) {
        into[e.key as String] = e.value as Object;
      }
    }
  }

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';

  String _agentLabel(String agentId) {
    switch (agentId) {
      case AdaAgents.siuYan:
        return _isEn ? 'Siu Yan' : '小欣';
      case AdaAgents.tungTung:
        return _isEn ? 'Tung Tung' : '通通';
      case AdaAgents.ahJanAhBak:
        // Gender pairing from the participant's profile; unknown → both.
        if (_variant == null) return _isEn ? 'Ah Jan / Ah Bak' : '阿珍／阿伯';
        return AgentRegistry.ahJanAhBakName(_variant, isEn: _isEn);
    }
    return agentId;
  }

  /// Whether every item on [s] has an answer (skips count).
  bool _complete(_Screen s) {
    switch (s.kind) {
      case _Kind.intro:
        return true;
      case _Kind.usage:
        return AdaAgents.all.every(_usage.containsKey);
      case _Kind.trait:
        return AdaAgents.all.every(_traits[s.id]!.containsKey);
      case _Kind.scenario:
        return _scenarios.containsKey(s.id);
      case _Kind.free:
        return _text.text.trim().isNotEmpty;
    }
  }

  void _markSkipped(_Screen s) {
    switch (s.kind) {
      case _Kind.intro:
        break;
      case _Kind.usage:
        for (final a in AdaAgents.all) {
          _usage.putIfAbsent(a, () => kSkipped);
        }
      case _Kind.trait:
        for (final a in AdaAgents.all) {
          _traits[s.id]!.putIfAbsent(a, () => kSkipped);
        }
      case _Kind.scenario:
        _scenarios.putIfAbsent(s.id, () => kSkipped);
      case _Kind.free:
        // Text already written is kept: 跳過 then just submits it.
        if (_text.text.trim().isEmpty) _freeTextStatus = kSkipped;
    }
  }

  Map<String, dynamic> _payload(
      {required String status, required int lastScreen}) {
    final text = _text.text.trim();
    final hasText = text.isNotEmpty;
    return {
      'schemaVersion': 1,
      'instrument': 'ada',
      'studyPhase': 'A',
      // Research IDs are server-only (decision 0021); analysis maps uid →
      // research ID through research_id_map.
      'uid': _uid,
      'timepoint': widget.timepoint.id,
      'formVersion': widget.timepoint.form.code,
      'itemsVersion': adaItemsVersion,
      'recallWindowZh': widget.timepoint.recallWindowZh,
      'allowSkip': widget.allowSkip,
      'ahJanAhBakVariant': _variant?.code,
      'enrolmentDay': widget.enrolmentDay,
      'screenCount': _screens.length,
      'lastScreen': lastScreen,
      'usage': Map<String, Object>.from(_usage),
      'traits': {
        for (final e in _traits.entries) e.key: Map<String, Object>.from(e.value),
      },
      if (widget.timepoint.form == AdaForm.full)
        'scenarios': Map<String, Object>.from(_scenarios),
      'freeText': hasText ? text : null,
      'freeTextStatus': hasText ? 'answered' : _freeTextStatus,
      'freeTextInputMode': hasText ? (_usedVoice ? 'voice' : 'typed') : null,
      'freeTextVoiceMs': hasText && _usedVoice ? _voiceMs : null,
      'status': status,
      if (!_startedAtStored) 'startedAt': _startedAt,
    };
  }

  Future<void> _save(
      {String status = 'in_progress', required int lastScreen}) async {
    final uid = _uid;
    if (uid == null) return;
    _startedAt ??= DateTime.now();
    final m = _voice.takeModality();
    if (m.$1) {
      _usedVoice = true;
      _voiceMs += m.$2 ?? 0;
    }
    try {
      await _store.save(uid, kAdaCollection, widget.timepoint.id,
          _payload(status: status, lastScreen: lastScreen));
      _startedAtStored = true;
    } catch (_) {
      // Graceful degradation: Firestore queues the write offline.
    }
    await _scanFreeText(uid);
  }

  /// Part D through the shared safety check (both arms, decision 0018);
  /// once per distinct text.
  Future<void> _scanFreeText(String uid) async {
    final text = _text.text.trim();
    if (text.isEmpty || text == _lastScanned || !mounted) return;
    _lastScanned = text;
    await SafetyService.of(context).checkAndRoute(
      context,
      text,
      point: SafetyInputPoint.adaFreeText,
      uid: uid,
    );
  }

  /// Shown inline above the nav bar (a SnackBar would cover 跳過).
  String? _hintText;

  void _hint() {
    final free = _screens[_index].kind == _Kind.free;
    setState(() => _hintText = _isEn
        ? (free
            ? (widget.allowSkip
                ? 'Please write something, or tap "Skip".'
                : 'Please write something first.')
            : (widget.allowSkip
                ? 'Please answer every row, or tap "Skip".'
                : 'Please answer every row first.'))
        : (free
            ? (widget.allowSkip ? '請寫低少少嘢，或者撳「跳過」。' : '請寫低少少嘢先。')
            : (widget.allowSkip ? '請揀晒每一行，或者撳「跳過」。' : '請揀晒每一行先。')));
  }

  Future<void> _go(int delta) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _voice.stopForSend();
    final target = (_index + delta).clamp(0, _screens.length - 1);
    await _save(lastScreen: target);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _index = target;
      _hintText = null;
    });
  }

  Future<void> _next() async {
    final s = _screens[_index];
    if (!_complete(s)) {
      _hint();
      return;
    }
    if (s.kind == _Kind.free) return _submit();
    await _go(1);
  }

  Future<void> _skip() async {
    final s = _screens[_index];
    setState(() => _markSkipped(s));
    if (s.kind == _Kind.free) return _submit();
    await _go(1);
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _voice.stopForSend();
    await _save(status: 'submitted', lastScreen: _index);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _isEn;
    final theme = Theme.of(context);
    final s = _screens[_index];
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'About the companions' : '三個夥伴')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _submitted
                ? _DoneView(isEn: isEn)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isEn
                                ? '${_index + 1} / ${_screens.length}'
                                : '第 ${_index + 1} / ${_screens.length} 頁',
                            key: const ValueKey('ada_progress'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey('ada_screen_$_index'),
                          padding: const EdgeInsets.all(20),
                          child: _body(s),
                        ),
                      ),
                      if (_hintText != null) SurveyHint(text: _hintText!),
                      SurveyNavBar(
                        isEn: isEn,
                        showBack: _index > 0,
                        showSkip: widget.allowSkip && s.kind != _Kind.intro,
                        nextLabel: s.kind == _Kind.intro
                            ? (isEn ? 'Start' : '開始')
                            : s.kind == _Kind.free
                                ? (isEn ? 'Submit' : '提交')
                                : null,
                        busy: _saving,
                        onBack: () => _go(-1),
                        onSkip: _skip,
                        onNext: _next,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _body(_Screen s) {
    switch (s.kind) {
      case _Kind.intro:
        return _IntroView(isEn: _isEn);
      case _Kind.usage:
        return _usageView();
      case _Kind.trait:
        return _traitView(s.id);
      case _Kind.scenario:
        return _scenarioView(s.id);
      case _Kind.free:
        return LongTextAnswer(
          question: _isEn ? AdaFreeText.questionEn : AdaFreeText.questionZh,
          hint: _isEn ? AdaFreeText.hintEn : AdaFreeText.hintZh,
          controller: _text,
          voice: _voice,
          voiceEnabled: widget.voiceEnabled,
        );
    }
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1.45,
              ),
        ),
      );

  Widget _usageView() {
    final tp = widget.timepoint;
    final labels = _isEn ? AdaUsage.labelsEn : AdaUsage.labelsZh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(_isEn
            ? AdaUsage.questionEn(tp.recallWindowEn)
            : AdaUsage.questionZh(tp.recallWindowZh)),
        for (final a in AdaAgents.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SurveyItemCard(
              title: _agentLabel(a),
              child: _OptionList(
                keyPrefix: 'usage_${a}_',
                labels: labels,
                values: const [0, 1, 2, 3],
                selected: _usage[a],
                onSelect: (v) => setState(() => _usage[a] = v),
              ),
            ),
          ),
      ],
    );
  }

  Widget _traitView(String traitId) {
    final theme = Theme.of(context);
    final scale = _isEn ? AdaTraits.scaleEn : AdaTraits.scaleZh;
    final label =
        (_isEn ? AdaTraits.labelsEn : AdaTraits.labelsZh)[traitId] ?? traitId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isEn ? AdaTraits.promptEn : AdaTraits.promptZh,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17)),
        const SizedBox(height: 8),
        _title('「$label」'),
        Text(
          [for (var i = 0; i < scale.length; i++) '${i + 1} = ${scale[i]}']
              .join('　'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        for (final a in AdaAgents.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SurveyItemCard(
              title: _agentLabel(a),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: ValueKey('trait_${traitId}_$a'),
                    child: LikertScale(
                      points: 5,
                      value: _traits[traitId]![a] is int
                          ? _traits[traitId]![a] as int
                          : null,
                      lowLabel: scale.first,
                      midLabel: scale[2],
                      highLabel: scale.last,
                      onChanged: (v) =>
                          setState(() => _traits[traitId]![a] = v),
                    ),
                  ),
                  if (_traits[traitId]![a] == kSkipped)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_isEn ? 'Skipped' : '已跳過',
                          style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _scenarioView(String scenarioId) {
    final theme = Theme.of(context);
    final label = (_isEn ? AdaScenarios.labelsEn : AdaScenarios.labelsZh)[
            scenarioId] ??
        scenarioId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isEn ? AdaScenarios.promptEn : AdaScenarios.promptZh,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17)),
        const SizedBox(height: 8),
        _title('「$label」'),
        _OptionList(
          keyPrefix: 'scenario_${scenarioId}_',
          labels: [
            for (final o in AdaScenarios.options)
              o == AdaScenarios.any
                  ? (_isEn ? AdaScenarios.anyEn : AdaScenarios.anyZh)
                  : _agentLabel(o),
          ],
          values: AdaScenarios.options,
          selected: _scenarios[scenarioId],
          onSelect: (v) => setState(() => _scenarios[scenarioId] = v),
        ),
      ],
    );
  }
}

/// Vertical list of large single-choice buttons.  Keys:
/// `{keyPrefix}{value}`.
class _OptionList extends StatelessWidget {
  const _OptionList({
    required this.keyPrefix,
    required this.labels,
    required this.values,
    required this.selected,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<String> labels;
  final List<Object> values;
  final Object? selected;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionButton(
              key: ValueKey('$keyPrefix${values[i]}'),
              label: labels[i],
              selected: selected == values[i],
              onTap: () => onSelect(values[i]),
              theme: theme,
            ),
          ),
        if (selected == kSkipped)
          Text(
            Localizations.localeOf(context).languageCode == 'en'
                ? 'Skipped'
                : '已跳過',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? cs.onPrimary : cs.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.isEn});
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.groups_2_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          isEn
              ? 'A few questions about how you see your three companions. '
                  'There are no right or wrong answers. You can go back at '
                  'any time.'
              : '有幾條問題，想知你點睇三個夥伴。冇啱冇錯，照你嘅感覺答就得。'
                  '隨時可以返上一頁。',
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.6),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.isEn});
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              isEn ? 'Thank you! Your answers are saved.' : '多謝你！已經儲存。',
              key: const ValueKey('survey_done'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(true),
              child: Text(isEn ? 'Done' : '完成'),
            ),
          ],
        ),
      ),
    );
  }
}

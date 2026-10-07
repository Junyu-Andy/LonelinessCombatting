/// T17 (SPEC:C22) — the 3 day-7 open questions, Phase A only.  One
/// question per screen, same long-text component as ADA Part D (mic only
/// when `voiceInputEnabled`).  Saved to
/// `users/{uid}/day7_open_responses/day7` on every screen change; frozen
/// after submit.  Question text is placeholder ([Day7OpenQuestions]).
/// T17b: part 2 of the day-7 flow (`day7_flow_page.dart`); every screen
/// has 「唔識填？打俾研究員」; `channel` records app / phone_by_staff.
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/safety/safety_check.dart';
import '../../../core/survey/long_text_answer.dart';
import '../../../core/voice/voice_input_button.dart';
import '../data/ada_items.dart';
import '../data/survey_draft_store.dart';
import 'ada_widgets.dart';
import 'survey_nav_bar.dart';

class Day7OpenPage extends StatefulWidget {
  const Day7OpenPage({
    super.key,
    this.allowSkip = true,
    this.enrolmentDay,
    this.store,
    this.uid,
    this.voiceEnabled,
    this.channel = AdaChannel.app,
    this.part,
  });

  final String channel;
  final (int, int)? part;
  final bool allowSkip;
  final int? enrolmentDay;
  final SurveyDraftStore? store;
  final String? uid;
  final bool? voiceEnabled;

  @override
  State<Day7OpenPage> createState() => _Day7OpenPageState();
}

class _Answer {
  final text = TextEditingController();
  String? status; // answered | skipped
  bool usedVoice = false;
  int voiceMs = 0;
  String lastScanned = '';
}

class _Day7OpenPageState extends State<Day7OpenPage> {
  late final SurveyDraftStore _store =
      widget.store ?? FirestoreSurveyDraftStore();
  final Map<String, _Answer> _answers = {
    for (final q in Day7OpenQuestions.ids) q: _Answer(),
  };
  final _voice = VoiceInputController();
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  bool _startedAtStored = false;
  DateTime? _startedAt;
  String? _uid;

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';
  bool get _staff => widget.channel == AdaChannel.phoneByStaff;
  String get _qid => Day7OpenQuestions.ids[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uid != null || !_loading) return;
    _uid = widget.uid ??
        context
            .getInheritedWidgetOfExactType<AppSettingsScope>()
            ?.notifier
            ?.profile
            ?.uid;
    _restore();
  }

  @override
  void dispose() {
    for (final a in _answers.values) {
      a.text.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    Map<String, dynamic>? doc;
    final uid = _uid;
    if (uid != null) {
      try {
        doc = await _store.load(uid, kDay7OpenCollection, kDay7OpenDocId);
      } catch (_) {
        doc = null;
      }
    }
    if (!mounted) return;
    setState(() {
      if (doc != null) {
        _submitted = doc['status'] == 'submitted';
        _startedAtStored = doc['startedAt'] != null;
        final answers = doc['answers'];
        if (answers is Map) {
          for (final q in Day7OpenQuestions.ids) {
            final a = answers[q];
            if (a is! Map) continue;
            if (a['text'] is String) _answers[q]!.text.text = a['text'];
            _answers[q]!.lastScanned = _answers[q]!.text.text.trim();
            if (a['status'] is String) _answers[q]!.status = a['status'];
            if (a['inputMode'] == 'voice') _answers[q]!.usedVoice = true;
          }
        }
        final last = doc['lastScreen'];
        if (last is num && !_submitted) {
          _index = last.toInt().clamp(0, Day7OpenQuestions.ids.length - 1);
        }
      }
      _loading = false;
    });
  }

  Map<String, dynamic> _payload(String status, int lastScreen) => {
        'schemaVersion': 1,
        'instrument': 'day7_open',
        'studyPhase': 'A',
        'uid': _uid,
        'timepoint': kDay7OpenDocId,
        'itemsVersion': day7OpenItemsVersion,
        'channel': widget.channel,
        'allowSkip': widget.allowSkip,
        'enrolmentDay': widget.enrolmentDay,
        'lastScreen': lastScreen,
        'answers': {
          for (final e in _answers.entries)
            e.key: () {
              final t = e.value.text.text.trim();
              final has = t.isNotEmpty;
              return <String, Object?>{
                'text': has ? t : null,
                'status': has ? 'answered' : e.value.status,
                'inputMode':
                    has ? (e.value.usedVoice ? 'voice' : 'typed') : null,
                'voiceMs': has && e.value.usedVoice ? e.value.voiceMs : null,
              };
            }(),
        },
        'status': status,
        if (!_startedAtStored) 'startedAt': _startedAt,
      };

  Future<void> _save(String status, int lastScreen) async {
    final uid = _uid;
    if (uid == null) return;
    _startedAt ??= DateTime.now();
    final cur = _answers[_qid]!;
    final m = _voice.takeModality();
    if (m.$1) {
      cur.usedVoice = true;
      cur.voiceMs += m.$2 ?? 0;
    }
    try {
      await _store.save(uid, kDay7OpenCollection, kDay7OpenDocId,
          _payload(status, lastScreen));
      _startedAtStored = true;
    } catch (_) {}
    final text = cur.text.text.trim();
    if (text.isNotEmpty && text != cur.lastScanned && mounted) {
      cur.lastScanned = text;
      if (_staff) {
        // Scanned server-side on save (functions/ada.js).
        final store = _store;
        if (store is StaffSurveyDraftStore && store.takeSafetyFlag()) {
          await showStaffSafetyNotice(context, isEn: _isEn);
        }
        return;
      }
      await SafetyService.of(context).checkAndRoute(context, text,
          point: SafetyInputPoint.day7OpenEnded, uid: uid);
    }
  }

  Future<void> _move(int target, {String status = 'in_progress'}) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _voice.stopForSend();
    await _save(status, target);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _hintText = null;
      if (status == 'submitted') {
        _submitted = true;
      } else {
        _index = target;
      }
    });
  }

  bool get _last => _index == Day7OpenQuestions.ids.length - 1;

  String? _hintText;

  void _next() {
    if (_answers[_qid]!.text.text.trim().isEmpty) {
      setState(() => _hintText = _isEn
          ? (widget.allowSkip
              ? 'Please write something, or tap "Skip".'
              : 'Please write something first.')
          : (widget.allowSkip ? '請寫低少少嘢，或者撳「跳過」。' : '請寫低少少嘢先。'));
      return;
    }
    _last ? _move(_index, status: 'submitted') : _move(_index + 1);
  }

  void _skip() {
    final a = _answers[_qid]!;
    if (a.text.text.trim().isEmpty) a.status = kSkipped;
    _last ? _move(_index, status: 'submitted') : _move(_index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _isEn;
    final n = Day7OpenQuestions.ids.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_staff
            ? (isEn ? 'Phone completion (staff)' : '電話代填（研究員）')
            : (isEn ? 'A few questions' : '幾條問題')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _submitted
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          isEn ? 'Thank you! Your answers are saved.' : '多謝你！已經儲存。',
                          key: const ValueKey('survey_done'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const ValueKey('survey_done_button'),
                          onPressed: () => Navigator.of(context).maybePop(true),
                          child: Text(isEn ? 'Done' : '完成'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      SurveyTopBar(
                        isEn: isEn,
                        part: widget.part,
                        progress: isEn
                            ? '${_index + 1} / $n'
                            : '第 ${_index + 1} / $n 題',
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey('day7_screen_$_index'),
                          padding: const EdgeInsets.all(20),
                          child: LongTextAnswer(
                            key: ValueKey('day7_$_qid'),
                            question: (isEn
                                ? Day7OpenQuestions.questionsEn
                                : Day7OpenQuestions.questionsZh)[_qid]!,
                            hint: isEn ? AdaFreeText.hintEn : AdaFreeText.hintZh,
                            controller: _answers[_qid]!.text,
                            voice: _voice,
                            voiceEnabled:
                                _staff ? false : widget.voiceEnabled,
                          ),
                        ),
                      ),
                      if (_hintText != null) SurveyHint(text: _hintText!),
                      SurveyNavBar(
                        isEn: isEn,
                        showBack: _index > 0,
                        showSkip: widget.allowSkip,
                        nextLabel: _last ? (isEn ? 'Submit' : '提交') : null,
                        busy: _saving,
                        onBack: () => _move(_index - 1),
                        onSkip: _skip,
                        onNext: _next,
                      ),
                    ],
                  ),
      ),
    );
  }
}

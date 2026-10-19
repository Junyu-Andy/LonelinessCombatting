/// T47 (rev. 10/16) — 「入組資料」: the researcher records part A of the
/// intake for an elder (dev-tasks-1015-intake rev. 10/16 §1 A + C), asked
/// out loud at the W0 visit.  Part B — 重要嘅人 / 想重新聯絡嘅人 — the
/// elder types in the App (`intake_people_page.dart`).  No selection caps
/// (Junyu 10/16).  Researcher-facing copy (not the elder's), so it is not
/// in docs/spec/copy.
library;

import 'package:flutter/material.dart';

import '../../onboarding/data/intake_response.dart';
import '../../onboarding/data/interest_labels.dart';
import '../data/enrollment_service.dart';

/// The question texts the researcher reads out (§1 A, C; Cantonese).
class IntakeQuestions {
  IntakeQuestions._();
  // A
  static const q1 = '你最想呢個 app 幫到你啲乜？';
  static const q2 = '你通常幾時會覺得孤單？';
  static const q3 = '你平時朝早、下晝、夜晚通常做啲咩？';
  static const q4 = '而家有冇咩事成日喺你心入面？（可以唔講）';
  static const q56 = '你平時鍾意做啲咩、鍾意傾啲咩？';
  static const q7 = '你想傾下人生嘅邊個階段？';
  static const q8 = '有冇咩話題你唔想夥伴提起？';
  static const q9 = '你打字多定係講多？';
  static const q10 = '你通常幾時最方便用呢個 app？';
  // C
  static const q13 = '你以前做邊行？';
  static const q14 = '你喺邊度長大？';
  static const q15 = '有冇養寵物？叫咩名？';
  static const q16 = '你鍾意人直接講，定係溫和啲？';

  static const goals = <(String, String)>[
    (IntakeOptions.mainGoalCompanionship, '想有人陪下傾偈'),
    (IntakeOptions.mainGoalEmotionalOutlet, '想搵個地方抒發下心情'),
    (IntakeOptions.mainGoalReconnect, '想同人重新連繫'),
    (IntakeOptions.mainGoalLearning, '想學下新嘢'),
    (IntakeOptions.mainGoalShareMemories, '想分享下人生回憶'),
    (IntakeOptions.mainGoalCurious, '對世界仲好有好奇心'),
  ];
  static const timings = <(String, String)>[
    (IntakeOptions.timingMornings, '早上'),
    (IntakeOptions.timingAfternoons, '下晝'),
    (IntakeOptions.timingEvenings, '夜晚'),
    (IntakeOptions.timingNights, '夜深'),
    (IntakeOptions.timingWeekends, '週末'),
    (IntakeOptions.timingAfterMealsAlone, '自己食完飯之後'),
    (IntakeOptions.timingFestivals, '節日'),
    (IntakeOptions.timingVaries, '冇固定時間'),
  ];
  static const topics = <(String, String)>[
    (IntakeOptions.topicHkHistory, '香港舊時嘅嘢香港歷史'),
    (IntakeOptions.topicFood, '飲食煮餸'),
    (IntakeOptions.topicFamilyStories, '屋企人嘅故事'),
    (IntakeOptions.topicNature, '種植動植物'),
    (IntakeOptions.topicMusicFilm, '你嗰個年代嘅音樂戲曲電影'),
    (IntakeOptions.topicHealth, '健康養生'),
    (IntakeOptions.topicCurrentEvents, '時事新聞'),
    (IntakeOptions.topicReligion, '宗教信仰人生價值'),
    (IntakeOptions.topicTravel, '旅行'),
    (IntakeOptions.topicSports, '運動'),
  ];
  static const chapters = <(String, String)>[
    (IntakeOptions.chapterChildhood, '細個嘅時候'),
    (IntakeOptions.chapterSchool, '讀書嘅日子'),
    (IntakeOptions.chapterFirstJob, '出嚟做嘢返工嘅日子'),
    (IntakeOptions.chapterMarriage, '拍拖結婚'),
    (IntakeOptions.chapterRaisingKids, '湊仔女嘅日子'),
    (IntakeOptions.chapterMoves, '搬屋移民搬區'),
    (IntakeOptions.chapterHkMilestones, '香港大事'),
    (IntakeOptions.chapterHobbiesDeveloped, '呢啲年發展嘅興趣或者技能'),
    (IntakeOptions.chapterTravel, '旅行經驗'),
    (IntakeOptions.chapterPresentFocus, '我寧願講返而家唔太想再諗以前'),
  ];
  static const inputModes = <(String, String)>[
    (IntakeOptions.inputTyping, '打字'),
    (IntakeOptions.inputVoice, '講'),
    (IntakeOptions.inputBoth, '都得'),
  ];
  static const times = <(String, String)>[
    (IntakeOptions.timeMorning, '朝早'),
    (IntakeOptions.timeMidday, '晏晝'),
    (IntakeOptions.timeAfternoon, '下晝'),
    (IntakeOptions.timeEvening, '夜晚'),
    (IntakeOptions.timeBeforeBed, '瞓覺之前'),
    (IntakeOptions.timeNoRoutine, '冇固定時間'),
  ];
  static const encouragement = <(String, String)>[
    ('direct', '直接'),
    ('gentle', '溫和'),
    ('either', '冇所謂'),
  ];
}

class IntakeSection extends StatefulWidget {
  final IntakeBackend backend;

  /// Pre-filled from the registration just made on the same page.
  final String? defaultEmail;

  const IntakeSection({super.key, required this.backend, this.defaultEmail});

  @override
  State<IntakeSection> createState() => _IntakeSectionState();
}

class _IntakeSectionState extends State<IntakeSection> {
  final _who = TextEditingController();
  final _goals = <String>{};
  final _goalOther = TextEditingController();
  final _timings = <String>{};
  final _morning = TextEditingController();
  final _afternoon = TextEditingController();
  final _evening = TextEditingController();
  final _onMind = TextEditingController();
  final _interests = <String>{};
  final _interestsOther = TextEditingController();
  final _topics = <String>{};
  final _topicsOther = TextEditingController();
  final _chapters = <String>{};
  final _avoid = TextEditingController();
  String? _inputMode;
  final _times = <String>{};
  final _occupation = TextEditingController();
  final _hometown = TextEditingController();
  final _pet = TextEditingController();
  String? _encouragement;
  final _note = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _error;
  IntakeRecordResult? _done;

  List<TextEditingController> get _texts => [
        _who, _goalOther, _morning, _afternoon, _evening, _onMind,
        _interestsOther, _topicsOther, _avoid, _occupation, _hometown, _pet,
        _note,
      ];

  @override
  void didUpdateWidget(covariant IntakeSection old) {
    super.didUpdateWidget(old);
    final d = widget.defaultEmail;
    if (d != null && d != old.defaultEmail && _who.text.trim().isEmpty) {
      _who.text = d;
    }
  }

  @override
  void dispose() {
    for (final c in _texts) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  IntakeAnswers _answers() => IntakeAnswers(
        mainGoals: _goals.toList(),
        mainGoalOther: _t(_goalOther),
        lonelinessTimings: _timings.toList(),
        typicalMorning: _t(_morning),
        typicalAfternoon: _t(_afternoon),
        typicalEvening: _t(_evening),
        onMind: _t(_onMind),
        interests: _interests.toList(),
        interestsOther: _t(_interestsOther),
        topics: _topics.toList(),
        topicsOther: _t(_topicsOther),
        lifeChapters: _chapters.toList(),
        avoidTopics: _t(_avoid),
        inputMode: _inputMode ?? IntakeOptions.inputUnsure,
        preferredTimes: _times.toList(),
        formerOccupation: _t(_occupation),
        hometown: _t(_hometown),
        petName: _t(_pet),
        encouragementStyle: _encouragement,
        researcherNote: _t(_note),
      );

  Future<void> _submit() async {
    final who = _who.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = who.contains('@')
          ? await widget.backend.record(_answers(), email: who)
          : await widget.backend.record(_answers(), researchId: who);
      if (mounted) setState(() => _done = r);
    } on IntakeError catch (e) {
      if (mounted) setState(() => _error = intakeErrorText(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = intakeErrorText('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _done = null;
      _error = null;
      for (final set in [_goals, _timings, _interests, _topics, _chapters,
        _times]) {
        set.clear();
      }
      _inputMode = null;
      _encouragement = null;
      for (final c in _texts) {
        if (c != _who) c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text('入組資料（W0 面訪口頭問，由你錄入；由第 1 題問到第 14 題）',
                      style: theme.textTheme.titleMedium)),
              TextButton(
                key: const Key('intake_toggle'),
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? '收起' : '打開'),
              ),
            ]),
            if (_open) ...[
              if (_done != null)
                _DoneCard(result: _done!, onNext: _reset)
              else
                ..._form(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chips(String keyPrefix, List<(String, String)> options,
          Set<String> selected) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label) in options)
          FilterChip(
            key: Key('${keyPrefix}_$id'),
            label: Text(label),
            selected: selected.contains(id),
            onSelected: (on) => setState(() {
              if (on) {
                selected.add(id);
              } else {
                selected.remove(id);
              }
            }),
          ),
      ]);

  Widget _field(String key, TextEditingController c, String label,
          {int lines = 1, int? maxLength}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: Key(key),
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          maxLength: maxLength,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  List<Widget> _form(ThemeData theme) {
    final canSubmit = !_busy && _who.text.trim().isNotEmpty;
    return [
      const SizedBox(height: 8),
      TextField(
        key: const Key('intake_who'),
        controller: _who,
        decoration: const InputDecoration(
            labelText: '老人家登入電郵或研究編號', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 4),
      Text('每題都可以空；多選唔限數量。「重要嘅人」「想重新聯絡嘅人」由老人家喺自己 App 填，呢度唔問。',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      _block(theme, 1, IntakeQuestions.q1, [
        _chips('intake_goal', IntakeQuestions.goals, _goals),
        _field('intake_goal_other', _goalOther, '其他（可以唔填）'),
      ]),
      _block(theme, 2, IntakeQuestions.q2, [
        _chips('intake_timing', IntakeQuestions.timings, _timings),
      ]),
      _block(theme, 3, IntakeQuestions.q3, [
        _field('intake_morning', _morning, '朝早'),
        _field('intake_afternoon', _afternoon, '下晝'),
        _field('intake_evening', _evening, '夜晚'),
      ]),
      _block(theme, 4, IntakeQuestions.q4, [
        Text('敏感：只有小欣會記得，而且只喺老人家自己提起先會用。',
            style: theme.textTheme.bodySmall),
        _field('intake_on_mind', _onMind, '心事（可以留空）', lines: 2),
      ]),
      _block(theme, 5, IntakeQuestions.q56, [
        Text('鍾意做：', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in InterestLabels.ids)
            FilterChip(
              key: Key('intake_interest_$id'),
              label: Text(InterestLabels.label(id, false)),
              selected: _interests.contains(id),
              onSelected: (on) => setState(() {
                if (on) {
                  _interests.add(id);
                } else {
                  _interests.remove(id);
                }
              }),
            ),
        ]),
        _field('intake_interests_other', _interestsOther, '其他活動（可以唔填）'),
        const SizedBox(height: 14),
        Text('鍾意傾：', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        _chips('intake_topic', IntakeQuestions.topics, _topics),
        _field('intake_topics_other', _topicsOther, '其他話題（可以唔填）'),
      ]),
      _block(theme, 6, IntakeQuestions.q7, [
        _chips('intake_chapter', IntakeQuestions.chapters, _chapters),
      ]),
      _block(theme, 7, IntakeQuestions.q8, [
        _field('intake_avoid', _avoid, '一句就得，可以留空', lines: 2),
      ]),
      _block(theme, 8, IntakeQuestions.q9, [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, label) in IntakeQuestions.inputModes)
            ChoiceChip(
              key: Key('intake_input_$id'),
              label: Text(label),
              selected: _inputMode == id,
              onSelected: (_) => setState(() => _inputMode = id),
            ),
        ]),
      ]),
      _block(theme, 9, IntakeQuestions.q10, [
        _chips('intake_time', IntakeQuestions.times, _times),
      ]),
      _block(theme, 10, IntakeQuestions.q13, [
        _field('intake_occupation', _occupation, '以前嘅行業／工作（可以唔填）'),
      ]),
      _block(theme, 11, IntakeQuestions.q14, [
        _field('intake_hometown', _hometown, '地方（可以唔填）'),
      ]),
      _block(theme, 12, IntakeQuestions.q15, [
        _field('intake_pet', _pet, '寵物同名（冇就留空）'),
      ]),
      _block(theme, 13, IntakeQuestions.q16, [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, label) in IntakeQuestions.encouragement)
            ChoiceChip(
              key: Key('intake_encouragement_$id'),
              label: Text(label),
              selected: _encouragement == id,
              onSelected: (_) => setState(() => _encouragement = id),
            ),
        ]),
      ]),
      // 10/16 — the researcher's own note (not a question; the elder never
      // sees it).  Goes verbatim to all three companions as 「研究員觀察」.
      _block(theme, 14, '研究員備註（唔使問老人家；可以留空）', [
        Text('你自己嘅觀察，原句畀三位夥伴做記憶，例如「老人家健談，咩都想講」。'
            '老人家睇唔到。最多 200 字。',
            style: theme.textTheme.bodySmall),
        _field('intake_note', _note, '研究員觀察', lines: 2, maxLength: 200),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!,
            key: const Key('intake_error'),
            style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('intake_submit'),
        onPressed: canSubmit ? _submit : null,
        child: _busy
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator())
            : const Text('錄入'),
      ),
      const SizedBox(height: 4),
      Text('錄入後老人家下次完全關閉再打開 App 先會用到。再錄一次會覆蓋你錄嘅部分；老人家自己填嘅「重要嘅人」唔會郁。',
          style: theme.textTheme.bodySmall),
    ];
  }
}

/// One question: a numbered badge, the question in bold, the input, and
/// a rule underneath so the next question clearly starts afresh.
Widget _block(ThemeData theme, int n, String question, List<Widget> body) {
  return Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text('$n', style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(question, style: theme.textTheme.titleMedium),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        ...body,
        const SizedBox(height: 16),
        const Divider(height: 1),
      ],
    ),
  );
}

class _DoneCard extends StatelessWidget {
  final IntakeRecordResult result;
  final VoidCallback onNext;
  const _DoneCard({required this.result, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('已錄入：${result.researchId ?? '—'}',
            key: const Key('intake_done'),
            style: Theme.of(context).textTheme.titleMedium),
        Text('老人家自己填咗嘅重要嘅人 ${result.people} 位。老人家下次完全關閉再打開 App 先生效。'),
        const SizedBox(height: 8),
        TextButton(onPressed: onNext, child: const Text('錄下一位')),
      ],
    );
  }
}

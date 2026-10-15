/// T47 — 「入組資料」: the researcher records the five intake answers for
/// an elder (dev-tasks-1015-intake §1, §2.1).  Asked out loud at the W0
/// visit; the elder's App shows no questionnaire while
/// `researcherIntakeEnabled` is on.  Researcher-facing copy (not the
/// elder's), so it is not in docs/spec/copy.
library;

import 'package:flutter/material.dart';

import '../../onboarding/data/intake_response.dart';
import '../../onboarding/data/interest_labels.dart';
import '../data/enrollment_service.dart';

/// The question texts the researcher reads out (§1, Cantonese).
class IntakeQuestions {
  IntakeQuestions._();
  static const q1 = '你最想呢個 app 幫到你啲乜？（最多兩項）';
  static const q2 = '有冇邊幾位屋企人或者朋友，想夥伴知道？講個稱呼同關係就得。（最多三位）';
  static const q3 = '你平時鍾意做啲咩？（最多三項）';
  static const q4 = '有冇咩話題你唔想夥伴提起？（可以冇）';
  static const q5 = '你打字多定係講多？';

  static const goals = <(String, String)>[
    (IntakeOptions.mainGoalCompanionship, '想有人陪下傾偈'),
    (IntakeOptions.mainGoalEmotionalOutlet, '想搵個地方抒發下心情'),
    (IntakeOptions.mainGoalReconnect, '想同人重新連繫'),
    (IntakeOptions.mainGoalLearning, '想學下新嘢'),
    (IntakeOptions.mainGoalShareMemories, '想分享下人生回憶'),
    (IntakeOptions.mainGoalCurious, '對世界仲好有好奇心'),
  ];
  static const inputModes = <(String, String)>[
    (IntakeOptions.inputTyping, '打字'),
    (IntakeOptions.inputVoice, '講'),
    (IntakeOptions.inputBoth, '都得'),
  ];
  static const maxGoals = 2;
  static const maxPeople = 3;
  static const maxInterests = 3;
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
  final _people = List.generate(
      IntakeQuestions.maxPeople,
      (_) => (name: TextEditingController(), rel: TextEditingController()));
  final _interests = <String>{};
  final _interestsOther = TextEditingController();
  final _avoid = TextEditingController();
  String? _inputMode;
  bool _open = false;
  bool _busy = false;
  String? _error;
  IntakeRecordResult? _done;

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
    _who.dispose();
    for (final p in _people) {
      p.name.dispose();
      p.rel.dispose();
    }
    _interestsOther.dispose();
    _avoid.dispose();
    super.dispose();
  }

  IntakeAnswers _answers() => IntakeAnswers(
        mainGoals: _goals.toList(),
        importantPeople: [
          for (final p in _people)
            if (p.name.text.trim().isNotEmpty)
              IntakePerson(
                  name: p.name.text.trim(), relationship: p.rel.text.trim()),
        ],
        interests: _interests.toList(),
        interestsOther: _interestsOther.text.trim().isEmpty
            ? null
            : _interestsOther.text.trim(),
        avoidTopics: _avoid.text.trim().isEmpty ? null : _avoid.text.trim(),
        inputMode: _inputMode ?? IntakeOptions.inputUnsure,
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
      _goals.clear();
      _interests.clear();
      _inputMode = null;
      for (final p in _people) {
        p.name.clear();
        p.rel.clear();
      }
      _interestsOther.clear();
      _avoid.clear();
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
                  child: Text('入組資料（W0 面訪口頭問五題，由你錄入）',
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
      const SizedBox(height: 16),
      Text('1. ${IntakeQuestions.q1}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final (id, label) in IntakeQuestions.goals)
          FilterChip(
            key: Key('intake_goal_$id'),
            label: Text(label),
            selected: _goals.contains(id),
            onSelected: (on) => setState(() {
              if (on) {
                if (_goals.length < IntakeQuestions.maxGoals) _goals.add(id);
              } else {
                _goals.remove(id);
              }
            }),
          ),
      ]),
      const SizedBox(height: 16),
      Text('2. ${IntakeQuestions.q2}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      for (var i = 0; i < _people.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: Key('intake_person_name_$i'),
                controller: _people[i].name,
                decoration: const InputDecoration(
                    labelText: '稱呼', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: Key('intake_person_rel_$i'),
                controller: _people[i].rel,
                decoration: const InputDecoration(
                    labelText: '關係', border: OutlineInputBorder()),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 8),
      Text('3. ${IntakeQuestions.q3}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final id in InterestLabels.ids)
          FilterChip(
            key: Key('intake_interest_$id'),
            label: Text(InterestLabels.label(id, false)),
            selected: _interests.contains(id),
            onSelected: (on) => setState(() {
              if (on) {
                if (_interests.length < IntakeQuestions.maxInterests) {
                  _interests.add(id);
                }
              } else {
                _interests.remove(id);
              }
            }),
          ),
      ]),
      const SizedBox(height: 8),
      TextField(
        key: const Key('intake_interests_other'),
        controller: _interestsOther,
        decoration: const InputDecoration(
            labelText: '其他（可以唔填）', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      Text('4. ${IntakeQuestions.q4}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      TextField(
        key: const Key('intake_avoid'),
        controller: _avoid,
        maxLines: 2,
        decoration: const InputDecoration(
            labelText: '一句就得，可以留空', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      Text('5. ${IntakeQuestions.q5}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final (id, label) in IntakeQuestions.inputModes)
          ChoiceChip(
            key: Key('intake_input_$id'),
            label: Text(label),
            selected: _inputMode == id,
            onSelected: (_) => setState(() => _inputMode = id),
          ),
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
      Text('錄入後老人家下次打開 App 先會用到。再錄一次會覆蓋。',
          style: theme.textTheme.bodySmall),
    ];
  }
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
        Text('重要嘅人 ${result.people} 位。老人家下次完全關閉再打開 App 先生效。'),
        const SizedBox(height: 8),
        TextButton(onPressed: onNext, child: const Text('錄下一位')),
      ],
    );
  }
}

/// T47 — the short intake page the elder answers in the App when the
/// researcher is NOT recording it (`researcherIntakeEnabled` off;
/// dev-tasks-1015-intake §2.3).  Five questions, **one per screen**
/// (10/16: the one-page version crammed all five together and was hard
/// to read), same wording as the researcher reads out (§1; docs/spec/
/// copy S16).  Replaces the six-part IntakeFlowPage (retired 10/15).
///
/// Order (10/16, Junyu): the concrete questions first, the personal /
/// free-text ones last —
///   1 打字定講 · 2 鍾意做乜 · 3 重要嘅人 · 4 最想 app 幫到乜 · 5 唔想提起
/// The researcher's 入組資料 form (`intake_section.dart`) uses the same
/// order so both read the questions the same way.
///
/// Writes the same records the old flow did: `users/{uid}/onboarding/
/// intake` (subset of the old fields) and the profile's
/// hasCompletedIntake / interests / closeContacts / avoidTopics /
/// inputMode.  Free text goes through the shared safety check (T7).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/intake_repository.dart';
import '../../data/intake_response.dart';
import '../../data/interest_labels.dart';

/// S16 — the five questions (research-side draft of 10/15, Junyu to
/// confirm; the researcher's form reads the same words).
class IntakeShortCopy {
  IntakeShortCopy._();
  static const title = '傾偈之前，想問你五樣嘢';
  static const intro = '答唔答都得，答咗夥伴會更加了解你。';
  static const q1 = '你最想呢個 app 幫到你啲乜？';
  static const q1Hint = '最多揀兩項';
  static const q2 = '有冇邊幾位屋企人或者朋友，想夥伴知道？講個稱呼同關係就得。';
  static const q3 = '你平時鍾意做啲咩？';
  static const q3Hint = '最多揀三項';
  static const q4 = '有冇咩話題你唔想夥伴提起？';
  static const q5 = '你打字多定係講多？';
  static const done = '完成';
  static const next = '下一題';
  static const back = '上一題';
  static const nameLabel = '稱呼';
  static const relationLabel = '關係';
  static const otherLabel = '其他';
  static const optionalLabel = '可以留空';

  /// 「第 N 題，共 5 題」 (S16; dev draft, product window to check).
  static String stepLabel(int step, int total) => '第 $step 題，共 $total 題';

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

/// The five screens, in the order shown (concrete first, free text last).
enum IntakeShortStep { inputMode, interests, people, goals, avoid }

class IntakeShortPage extends StatefulWidget {
  final VoidCallback onComplete;

  /// Injectable for tests (defaults to Firestore).
  final IntakeRepository? repository;

  const IntakeShortPage({super.key, required this.onComplete, this.repository});

  @override
  State<IntakeShortPage> createState() => _IntakeShortPageState();
}

class _IntakeShortPageState extends State<IntakeShortPage> {
  late final IntakeRepository _repo = widget.repository ?? IntakeRepository();
  final _goals = <String>{};
  final _people = List.generate(
      IntakeShortCopy.maxPeople,
      (_) => (name: TextEditingController(), rel: TextEditingController()));
  final _interests = <String>{};
  final _interestsOther = TextEditingController();
  final _avoid = TextEditingController();
  String? _inputMode;
  bool _saving = false;
  int _step = 0;

  static const _steps = IntakeShortStep.values;

  @override
  void dispose() {
    for (final p in _people) {
      p.name.dispose();
      p.rel.dispose();
    }
    _interestsOther.dispose();
    _avoid.dispose();
    super.dispose();
  }

  void _go(int delta) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = (_step + delta).clamp(0, _steps.length - 1));
  }

  Future<void> _complete() async {
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      final now = DateTime.now();
      final people = [
        for (final p in _people)
          if (p.name.text.trim().isNotEmpty)
            PersonEntry(
                name: p.name.text.trim(), relationship: p.rel.text.trim()),
      ];
      final avoid = _avoid.text.trim().isEmpty ? null : _avoid.text.trim();
      final other = _interestsOther.text.trim().isEmpty
          ? null
          : _interestsOther.text.trim();
      final response = IntakeResponse(
        mainGoals: _goals.toList(),
        importantPeople: people.isEmpty ? null : people,
        activities: _interests.isEmpty ? null : _interests.toList(),
        activitiesOther: other,
        avoidTopics: avoid,
        inputMode: _inputMode ?? IntakeOptions.inputUnsure,
        createdAt: now,
        updatedAt: now,
        completedParts: const {1, 2, 3, 4, 5, 6},
        allCompleted: true,
      );
      final auth = AuthServiceScope.of(context);
      final settings = AppSettingsScope.read(context);
      final updated = profile.copyWith(
        hasCompletedIntake: true,
        interests: _interests.toList(),
        closeContacts: [
          for (final p in people)
            // T48: the elder typed them for the companions — shared.
            CloseContact(
                name: p.name,
                relation: p.relationship.isEmpty ? null : p.relationship,
                share: true),
        ],
        avoidTopics: avoid,
        inputMode: response.inputMode,
      );
      // In-memory profile first so onboarding completes immediately; the
      // Firestore writes go fire-and-forget (offline they would otherwise
      // freeze the 完成 button; the SDK queues them).
      settings.profile = updated;
      unawaited(() async {
        try {
          await _repo.save(profile.uid, response);
        } catch (_) {}
      }());
      unawaited(() async {
        try {
          await auth.updateProfile(updated);
        } catch (_) {}
      }());
      // T7 — the free text goes through the shared safety check (both
      // arms; the arm is not known yet).  The surface shows before the
      // page closes so a crisis page is never lost in the transition.
      final safety = SafetyService.of(context);
      final otherText = [
        other,
        for (final p in people) ...[p.name, p.relationship],
      ].whereType<String>().where((x) => x.isNotEmpty).join('\n');
      final List<SafetyCheckResult> results;
      if (safety.classifierActiveFor(SafetyInputPoint.intakeAvoidTopics)) {
        results = await Future.wait([
          safety.checkUserTextClassified(avoid ?? '',
              point: SafetyInputPoint.intakeAvoidTopics, uid: profile.uid),
          safety.checkUserTextClassified(otherText,
              point: SafetyInputPoint.intakeOtherText, uid: profile.uid),
        ]);
        if (!mounted) return;
      } else {
        results = [
          safety.checkUserText(avoid ?? '',
              point: SafetyInputPoint.intakeAvoidTopics, uid: profile.uid),
          safety.checkUserText(otherText,
              point: SafetyInputPoint.intakeOtherText, uid: profile.uid),
        ];
      }
      await safety.route(context, results);
      if (!mounted) return;
    }
    setState(() => _saving = false);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_step];
    final last = _step == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                // A new key per step so each question starts at the top
                // (same trick as the weekly questionnaire, 10/15).
                key: ValueKey('intake_short_step_$_step'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (_step == 0) ...[
                    Text(IntakeShortCopy.title,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(IntakeShortCopy.intro,
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    IntakeShortCopy.stepLabel(_step + 1, _steps.length),
                    key: const Key('intake_short_step_label'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (_step + 1) / _steps.length,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 20),
                  ..._question(theme, step),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('intake_short_back'),
                      onPressed: _saving ? null : () => _go(-1),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 56)),
                      child: const Text(IntakeShortCopy.back),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: Key(last ? 'intake_short_done' : 'intake_short_next'),
                    onPressed: _saving
                        ? null
                        : last
                            ? _complete
                            : () => _go(1),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    child: Text(
                        last ? IntakeShortCopy.done : IntakeShortCopy.next),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _question(ThemeData theme, IntakeShortStep step) {
    Widget q(String text, [String? hint]) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: theme.textTheme.titleLarge),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        );
    switch (step) {
      case IntakeShortStep.inputMode:
        return [
          q(IntakeShortCopy.q5),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (id, label) in IntakeShortCopy.inputModes)
              ChoiceChip(
                key: Key('intake_short_input_$id'),
                label: Text(label),
                selected: _inputMode == id,
                onSelected: (_) => setState(() => _inputMode = id),
              ),
          ]),
        ];
      case IntakeShortStep.interests:
        return [
          q(IntakeShortCopy.q3, IntakeShortCopy.q3Hint),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final id in InterestLabels.ids)
              FilterChip(
                key: Key('intake_short_interest_$id'),
                label: Text(InterestLabels.label(id, false)),
                selected: _interests.contains(id),
                onSelected: (on) => setState(() {
                  if (on) {
                    if (_interests.length < IntakeShortCopy.maxInterests) {
                      _interests.add(id);
                    }
                  } else {
                    _interests.remove(id);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            key: const Key('intake_short_interests_other'),
            controller: _interestsOther,
            scrollPadding: const EdgeInsets.only(bottom: 160),
            decoration: const InputDecoration(
                labelText: IntakeShortCopy.otherLabel,
                helperText: IntakeShortCopy.optionalLabel),
          ),
        ];
      case IntakeShortStep.people:
        return [
          q(IntakeShortCopy.q2, IntakeShortCopy.optionalLabel),
          for (var i = 0; i < _people.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: Key('intake_short_person_name_$i'),
                    controller: _people[i].name,
                    scrollPadding: const EdgeInsets.only(bottom: 160),
                    decoration: const InputDecoration(
                        labelText: IntakeShortCopy.nameLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: Key('intake_short_person_rel_$i'),
                    controller: _people[i].rel,
                    scrollPadding: const EdgeInsets.only(bottom: 160),
                    decoration: const InputDecoration(
                        labelText: IntakeShortCopy.relationLabel),
                  ),
                ),
              ]),
            ),
        ];
      case IntakeShortStep.goals:
        return [
          q(IntakeShortCopy.q1, IntakeShortCopy.q1Hint),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (id, label) in IntakeShortCopy.goals)
              FilterChip(
                key: Key('intake_short_goal_$id'),
                label: Text(label),
                selected: _goals.contains(id),
                onSelected: (on) => setState(() {
                  if (on) {
                    if (_goals.length < IntakeShortCopy.maxGoals) {
                      _goals.add(id);
                    }
                  } else {
                    _goals.remove(id);
                  }
                }),
              ),
          ]),
        ];
      case IntakeShortStep.avoid:
        return [
          q(IntakeShortCopy.q4, IntakeShortCopy.optionalLabel),
          TextField(
            key: const Key('intake_short_avoid'),
            controller: _avoid,
            minLines: 2,
            maxLines: 4,
            scrollPadding: const EdgeInsets.only(bottom: 160),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ];
    }
  }
}

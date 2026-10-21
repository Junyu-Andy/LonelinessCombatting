/// B.4 — Thought Exercise page 「望一望心入面」.
///
/// Form v2 (10/21, decisions-log 10/21 item 133 (2), PI final handoff);
/// the v1 page is gone.  Opening line, then four questions on one scroll
/// page:
///   一 心入面有冇一句說話轉嚟轉去？寫低佢。 (required) + hint line;
///      pre-filled with the elder's sentence from 小欣's invite (Hybrid)
///   二 寫低之後，你而家覺得點？ (face, required) + 有幾強烈？ 1–10
///      (required)
///   三 呢個諗法係由咩引起？（可以留空） (optional)
///   四 如果有個好朋友都咁諗，你會同佢講咩？ (optional)
/// then 繼續 saves, the safety check runs on 一/三/四, and 前後對照
/// asks the after-rating (1–10).  Words: docs/spec/copy/
/// thought-exercise.md.  Stored fields: see [ThoughtExerciseEntry].
///
/// Pixel-identical across arms.  Only difference is the entry pathway:
///   - Arm A Siu Yan offer: launches with [initialThought] auto-filled
///     into 一 and provenance fields populated
///     (entryPathway = 'siu_yan_offer').
///   - Both arms via 做啲嘢 tab: blank fields, user types 一
///     (entryPathway = 'me_tile').
///
/// No LLM dialogue, no follow-up questions, no system commentary
/// (Phase A Proposal §2.3, Product Overview §5.2).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/survey/likert_scale.dart';
import '../../analytics/presentation/analytics_scope.dart';
import '../../auth/presentation/auth_service_scope.dart';
import '../data/thought_exercise_entry.dart';
import '../../../core/safety/safety_check.dart';
import '../../../core/session/chat_session_recorder.dart';
import '../../../shared/widgets/keyboard_compact.dart';

class ThoughtExercisePage extends StatefulWidget {
  /// Pre-fill for 一 (the thought) when launched from Siu Yan's offer
  /// pathway.
  final String? initialThought;

  /// Provenance (B.5 audit).  When [agentId] is non-null, the entry is
  /// tagged as `siu_yan_offer`; otherwise `me_tile`.
  final String? agentId;
  final String? agentInvitationText;
  final String? originTurnRef;

  /// Tests only: where the entry is saved.  Null = Firestore
  /// ([ThoughtExerciseRepository]).
  @visibleForTesting
  final ThoughtExerciseRepository? repository;

  const ThoughtExercisePage({
    super.key,
    this.initialThought,
    this.agentId,
    this.agentInvitationText,
    this.originTurnRef,
    this.repository,
  });

  @override
  State<ThoughtExercisePage> createState() => _ThoughtExercisePageState();
}

class _ThoughtExercisePageState extends State<ThoughtExercisePage> {
  // 5 emoji choices for 二.  Kept few + culturally neutral.
  static const _emojis = ['😟', '😔', '😐', '🙂', '😊'];

  // 一 → thought, 三 → situation, 四 → anotherWayToLook (v1 field names).
  late final TextEditingController _thoughtCtrl;
  final _situationCtrl = TextEditingController();
  final _alternativeCtrl = TextEditingController();

  // B14 — no prefilled default.  A pre-selected midpoint emoji / midpoint
  // intensity biases responses through anchoring + satisficing, so both
  // start empty and the user must actively choose before continuing.
  // Intensity is a tappable 1–10 scale (was a slider — elders found the
  // hidden-thumb track undraggable and it had no anchor labels).
  String? _emoji;
  int? _intensityBefore;
  int? _intensityAfter;

  bool _showingExit = false;
  bool _saving = false;
  String? _entryId;

  @override
  void initState() {
    super.initState();
    _thoughtCtrl = TextEditingController(text: widget.initialThought ?? '');
    // The required text field (一) drives the "繼續" button's enabled
    // state via [_isComplete], which is recomputed during build.  Without
    // this listener the button stayed disabled forever because TextField
    // edits don't rebuild on their own.
    _thoughtCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _thoughtCtrl.removeListener(_onFieldChanged);
    _thoughtCtrl.dispose();
    _situationCtrl.dispose();
    _alternativeCtrl.dispose();
    super.dispose();
  }

  // Required: 一 (the thought) and 二 (face + 1–10).  三 and 四 may be
  // blank.
  bool get _isComplete =>
      _emoji != null &&
      _intensityBefore != null &&
      _thoughtCtrl.text.trim().isNotEmpty;

  Future<void> _saveAndAdvanceToExit() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = widget.repository ??
        ThoughtExerciseRepository(available: auth.available);
    final entry = ThoughtExerciseEntry(
      situation: _situationCtrl.text.trim(),
      emotionEmoji: _emoji!,
      intensityBefore: _intensityBefore!,
      thought: _thoughtCtrl.text.trim(),
      anotherWayToLook: _alternativeCtrl.text.trim(),
      agentId: widget.agentId,
      agentInvitationText: widget.agentInvitationText,
      originTurnRef: widget.originTurnRef,
      createdAt: DateTime.now(),
      entryPathway:
          widget.agentId != null ? 'siu_yan_offer' : 'me_tile',
    );
    final id = await repo.create(profile.uid, entry);
    // T7 — the text fields (v2: 一/三/四) go through the shared safety
    // check (both arms) after the entry is saved; acute opens the crisis
    // page.
    if (mounted) {
      await SafetyService.of(context).checkAndRoute(
        context,
        [entry.thought, entry.situation, entry.anotherWayToLook].join('\n'),
        point: SafetyInputPoint.thoughtExercise,
        uid: profile.uid,
        agentId: widget.agentId,
      );
    }
    if (mounted) {
      _entryId = id;
      await AnalyticsScope.of(context).logM5ThoughtExerciseSaved(
        totalCharLen: entry.thought.length +
            entry.situation.length +
            entry.anotherWayToLook.length,
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _showingExit = true;
      // B14 — leave the "after" rating empty so it isn't anchored to the
      // "before" value; the user must actively re-rate.
      _intensityAfter = null;
    });
  }

  Future<void> _saveExitAndClose() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null || _entryId == null || _intensityAfter == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = widget.repository ??
        ThoughtExerciseRepository(available: auth.available);
    await repo.setIntensityAfter(
      uid: profile.uid,
      entryId: _entryId!,
      intensityAfter: _intensityAfter!,
    );
    if (!mounted) return;
    // L-1 — te_module_complete (entry saved + exit re-rating done).
    unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.teModuleComplete, {
      'entryId': _entryId,
      'entryPathway': widget.agentId != null ? 'siu_yan_offer' : 'me_tile',
    }));
    Navigator.of(context).pop();
  }

  bool _openLogged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openLogged) return;
    _openLogged = true;
    // L-1 — te_module_open with provenance.
    unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.teModuleOpen, {
      'entryPathway': widget.agentId != null ? 'siu_yan_offer' : 'me_tile',
      'agentId': widget.agentId,
      'hasInvitation': widget.agentInvitationText != null,
    }));
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    // M-7 — tool session: enter = start, leave = end.
    return ToolSessionScope(
      toolId: 'thought_exercise',
      child: Scaffold(
      // 1020c 二: one-line bar while the keyboard is open (switch
      // keyboardCompactHeaderEnabled; off = the same AppBar as before).
      appBar: keyboardCompactAppBar(
        context,
        title: Text(_showingExit
            ? (isEn ? 'Before / after' : '前後對照')
            : (isEn ? 'Look at a thought' : '望一望心入面')),
      ),
      body: SafeArea(
        child: _showingExit
            ? _buildExitView(isEn)
            : _buildEntryView(isEn),
      ),
      ),
    );
  }

  Widget _buildEntryView(bool isEn) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Opening line (pixel-identical across arms, static text).
            Text(
              isEn
                  ? 'This small practice helps you look at a thought that is '
                      'stuck in your mind. Nothing special needs to have '
                      'happened — if a sentence keeps going round and round in '
                      'your mind, you can write it down. No one will comment, '
                      'and there is no right answer.'
                  : '呢個小練習幫你望一望心入面卡住嘅諗法。唔使有咩特別事發生，'
                      '有句說話喺心入面轉嚟轉去，都可以寫低。冇人會評論，'
                      '亦都冇標準答案。',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 22),
            _Label(
              text: isEn
                  ? '1. Is there a sentence going round and round in your '
                      'mind? Write it down.'
                  : '一、心入面有冇一句說話轉嚟轉去？寫低佢。',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isEn
                    ? "For example: nobody remembers me; I'm useless."
                    : '例如：冇人記得我、我冇用。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextField(
              controller: _thoughtCtrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '2. Now that you have written it, how do you feel?'
                  : '二、寫低之後，你而家覺得點？',
            ),
            _EmojiRow(
              value: _emoji,
              choices: _emojis,
              onChanged: (e) => setState(() => _emoji = e),
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'How strong is it? Tap a number (1 to 10)'
                  : '有幾強烈？撳一個數字（1 至 10）',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            LikertScale(
              points: 10,
              value: _intensityBefore,
              onChanged: (v) => setState(() => _intensityBefore = v),
              lowLabel: isEn ? 'Very mild' : '好輕微',
              highLabel: isEn ? 'Very strong' : '好強烈',
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '3. What brought this thought on? (optional)'
                  : '三、呢個諗法係由咩引起？（可以留空）',
            ),
            TextField(
              controller: _situationCtrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '4. If a good friend thought the same, what would you '
                      'say to them?'
                  : '四、如果有個好朋友都咁諗，你會同佢講咩？',
            ),
            TextField(
              controller: _alternativeCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: !_isComplete || _saving ? null : _saveAndAdvanceToExit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(isEn ? 'Continue' : '繼續',
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitView(bool isEn) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? "Now that you've written it, look again at how strong the "
                    'feeling is now. Higher, lower or the same — all fine.'
                : '寫完之後，再睇下而家嘅感覺有幾強烈。高咗、低咗、一樣都冇問題。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          // Side-by-side before/after (per spec)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BeforeAfterTile(
                label: isEn ? 'Before' : '之前',
                emoji: _emoji ?? '',
                value: _intensityBefore,
              ),
              const Icon(Icons.arrow_forward, size: 28),
              _BeforeAfterTile(
                label: isEn ? 'Now' : '而家',
                emoji: _emoji ?? '', // emoji not re-selected, only intensity
                value: _intensityAfter,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // v2: the explanation above is the only prompt (the v1 line
          // 「依家有幾強烈？…」 is gone).
          LikertScale(
            points: 10,
            value: _intensityAfter,
            onChanged: (v) => setState(() => _intensityAfter = v),
            lowLabel: isEn ? 'Very mild' : '好輕微',
            highLabel: isEn ? 'Very strong' : '好強烈',
          ),
          const Spacer(),
          FilledButton(
            onPressed: _saving || _intensityAfter == null
                ? null
                : _saveExitAndClose,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(isEn ? 'Done' : '完成',
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}


class _EmojiRow extends StatelessWidget {
  final String? value;
  final List<String> choices;
  final ValueChanged<String> onChanged;
  const _EmojiRow({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  /// Text label per face so elders don't have to decode the emoji alone.
  static const _labelsZh = {
    '😟': '擔心',
    '😔': '唔開心',
    '😐': '一般',
    '🙂': '幾好',
    '😊': '開心',
  };
  static const _labelsEn = {
    '😟': 'Worried',
    '😔': 'Sad',
    '😐': 'So-so',
    '🙂': 'Okay',
    '😊': 'Happy',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final labels = isEn ? _labelsEn : _labelsZh;
    return Row(
      children: [
        for (final e in choices)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: value == e
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                  color: value == e
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e, style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[e] ?? '',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: value == e
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BeforeAfterTile extends StatelessWidget {
  final String label;
  final String emoji;
  final int? value;
  const _BeforeAfterTile({
    required this.label,
    required this.emoji,
    required this.value,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(emoji, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 4),
        Text(value?.toString() ?? '—', style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

/// B.4 — Thought Exercise 5-field page (Phase A spec May 2026).
///
/// Pixel-identical across arms.  Only difference is the entry pathway:
///   - Arm A Siu Yan offer: launches with [initialThought] auto-filled
///     and provenance fields populated (entryPathway = 'siu_yan_offer').
///   - Both arms via 做啲嘢 tab: blank fields, user types Field 3
///     (entryPathway = 'me_tile').
///
/// No LLM dialogue, no follow-up questions, no system commentary
/// (Phase A Proposal §2.3, Product Overview §5.2).
library;

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../analytics/presentation/analytics_scope.dart';
import '../../auth/presentation/auth_service_scope.dart';
import '../data/thought_exercise_entry.dart';

class ThoughtExercisePage extends StatefulWidget {
  /// Pre-fill for Field 3 when launched from Siu Yan's offer pathway.
  final String? initialThought;

  /// Provenance (B.5 audit).  When [agentId] is non-null, the entry is
  /// tagged as `siu_yan_offer`; otherwise `me_tile`.
  final String? agentId;
  final String? agentInvitationText;
  final String? originTurnRef;

  const ThoughtExercisePage({
    super.key,
    this.initialThought,
    this.agentId,
    this.agentInvitationText,
    this.originTurnRef,
  });

  @override
  State<ThoughtExercisePage> createState() => _ThoughtExercisePageState();
}

class _ThoughtExercisePageState extends State<ThoughtExercisePage> {
  // 5 emoji choices for Field 2.  Kept few + culturally neutral.
  static const _emojis = ['😟', '😔', '😐', '🙂', '😊'];

  // Research Review v2 Item 5: first-visit hint.  In-memory flag resets
  // each app session; persistent suppression requires Firestore/prefs integration.
  static bool _firstVisitHintShown = false;
  bool _showFirstVisitHint = false;

  late final TextEditingController _situationCtrl;
  late final TextEditingController _thoughtCtrl;
  final _reasonCtrl = TextEditingController();
  final _alternativeCtrl = TextEditingController();

  String _emoji = '😐';
  double _intensityBefore = 5;
  double? _intensityAfter;

  bool _showingExit = false;
  bool _saving = false;
  String? _entryId;

  @override
  void initState() {
    super.initState();
    _situationCtrl = TextEditingController();
    _thoughtCtrl = TextEditingController(text: widget.initialThought ?? '');
    // Each required field drives the "繼續" button's enabled state via
    // [_isComplete], which is recomputed during build.  Without these
    // listeners the button stayed disabled forever because TextField
    // edits don't rebuild on their own.
    _situationCtrl.addListener(_onFieldChanged);
    _thoughtCtrl.addListener(_onFieldChanged);
    _reasonCtrl.addListener(_onFieldChanged);
    if (!_firstVisitHintShown) {
      _showFirstVisitHint = true;
      _firstVisitHintShown = true;
    }
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _situationCtrl.removeListener(_onFieldChanged);
    _thoughtCtrl.removeListener(_onFieldChanged);
    _reasonCtrl.removeListener(_onFieldChanged);
    _situationCtrl.dispose();
    _thoughtCtrl.dispose();
    _reasonCtrl.dispose();
    _alternativeCtrl.dispose();
    super.dispose();
  }

  bool get _isComplete =>
      _situationCtrl.text.trim().isNotEmpty &&
      _thoughtCtrl.text.trim().isNotEmpty &&
      _reasonCtrl.text.trim().isNotEmpty;
  // Field 5 (anotherWayToLook) is allowed to be blank per spec.

  Future<void> _saveAndAdvanceToExit() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = ThoughtExerciseRepository(available: auth.available);
    final entry = ThoughtExerciseEntry(
      situation: _situationCtrl.text.trim(),
      emotionEmoji: _emoji,
      intensityBefore: _intensityBefore.round(),
      thought: _thoughtCtrl.text.trim(),
      oneReasonTrue: _reasonCtrl.text.trim(),
      anotherWayToLook: _alternativeCtrl.text.trim(),
      agentId: widget.agentId,
      agentInvitationText: widget.agentInvitationText,
      originTurnRef: widget.originTurnRef,
      createdAt: DateTime.now(),
      entryPathway:
          widget.agentId != null ? 'siu_yan_offer' : 'me_tile',
    );
    final id = await repo.create(profile.uid, entry);
    if (mounted) {
      _entryId = id;
      await AnalyticsScope.of(context).logM5ThoughtExerciseSaved(
        totalCharLen: entry.situation.length +
            entry.thought.length +
            entry.oneReasonTrue.length +
            entry.anotherWayToLook.length,
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _showingExit = true;
      _intensityAfter = _intensityBefore; // start at before; user re-rates
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
    final repo = ThoughtExerciseRepository(available: auth.available);
    await repo.setIntensityAfter(
      uid: profile.uid,
      entryId: _entryId!,
      intensityAfter: _intensityAfter!.round(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(_showingExit
            ? (isEn ? 'Before / after' : '前後對照')
            : (isEn ? 'Look at a thought' : '望一望心入面')),
      ),
      body: SafeArea(
        child: _showingExit
            ? _buildExitView(isEn)
            : _buildEntryView(isEn),
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
            // Research Review v2 Item 5: first-visit hint banner.
            if (_showFirstVisitHint) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEn
                            ? 'Here you can look back at your recent moods and thoughts. Take it slow — no rush.'
                            : '呢度可以畀你睇返自己最近嘅心情同諗法。慢慢嚟，唔趕。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          height: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: theme.colorScheme.onPrimaryContainer,
                      onPressed: () => setState(() => _showFirstVisitHint = false),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ],
            // Intro line (pixel-identical across arms, static text)
            Text(
              isEn
                  ? 'A small practice to look at a thought you have. No one '
                      'will comment. There are no right answers. Take your time.'
                  : '呢個小練習係幫你慢慢望一望自己嘅諗法。冇人會評論，亦都冇答案。慢慢嚟。',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 22),
            _Label(text: isEn ? '1. The situation' : '一、嗰陣係咩情況？'),
            TextField(
              controller: _situationCtrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(text: isEn ? '2. How did you feel?' : '二、我嗰陣覺得點？'),
            _EmojiRow(
              value: _emoji,
              choices: _emojis,
              onChanged: (e) => setState(() => _emoji = e),
            ),
            const SizedBox(height: 8),
            Text(isEn ? 'Intensity (1–10)' : '強度（1–10）',
                style: theme.textTheme.bodyMedium),
            Slider(
              value: _intensityBefore,
              min: 1,
              max: 10,
              divisions: 9,
              label: _intensityBefore.round().toString(),
              onChanged: (v) => setState(() => _intensityBefore = v),
            ),
            const SizedBox(height: 8),
            _Label(text: isEn ? '3. The thought' : '三、嗰個諗法係：'),
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
                  ? '4. One reason this thought might be true'
                  : '四、一個令呢個諗法可能成立嘅理由',
            ),
            TextField(
              controller: _reasonCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '5. One other way to look at it (optional)'
                  : '五、一個睇呢件事嘅另一個角度（可以留空）',
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
    final after = _intensityAfter ?? _intensityBefore;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'Re-rate how you feel right now. No judgement, no escalation '
                    "— it's fine for the number to be higher, lower, or the same."
                : '依家再 rate 一下你嘅感覺。冇判斷、冇升降警示 —— 個數字高、低、一樣 都 OK。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          // Side-by-side before/after (per spec)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BeforeAfterTile(
                label: isEn ? 'Before' : '之前',
                emoji: _emoji,
                value: _intensityBefore.round(),
              ),
              const Icon(Icons.arrow_forward, size: 28),
              _BeforeAfterTile(
                label: isEn ? 'Now' : '依家',
                emoji: _emoji, // emoji not re-selected, only intensity
                value: after.round(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(isEn ? 'Intensity now (1–10)' : '依家強度（1–10）',
              style: theme.textTheme.bodyMedium),
          Slider(
            value: after,
            min: 1,
            max: 10,
            divisions: 9,
            label: after.round().toString(),
            onChanged: (v) => setState(() => _intensityAfter = v),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : _saveExitAndClose,
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
  final String value;
  final List<String> choices;
  final ValueChanged<String> onChanged;
  const _EmojiRow({
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final e in choices)
          GestureDetector(
            onTap: () => onChanged(e),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == e
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(e, style: const TextStyle(fontSize: 32)),
            ),
          ),
      ],
    );
  }
}

class _BeforeAfterTile extends StatelessWidget {
  final String label;
  final String emoji;
  final int value;
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
        Text('$value', style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

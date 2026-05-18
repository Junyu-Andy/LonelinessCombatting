/// Static three-field thought-record exercise (Walkthrough Case 5,
/// Branch A; embedded M4 minimal naming behaviour).
///
/// The page is intentionally rigid: no Socratic continuation, no
/// dialogue, no LLM. The user fills three fields, taps save, and
/// returns. Ah Jan / Ah Bak does not engage the content of the
/// thought after this hand-off — Design Rationale §5.2.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/thought_record.dart';

class ThoughtRecordExercisePage extends StatefulWidget {
  /// Optional pre-fill — when the dialogue surface routes here after
  /// naming a thought, the thought text is passed so the user doesn't
  /// retype it.
  final String? initialThought;

  /// Origin tag persisted alongside the record. `m3_reflective_dialogue`
  /// for the agent-routed flow, `me_tile` for direct entry.
  final String originSurface;

  const ThoughtRecordExercisePage({
    super.key,
    this.initialThought,
    this.originSurface = 'me_tile',
  });

  @override
  State<ThoughtRecordExercisePage> createState() =>
      _ThoughtRecordExercisePageState();
}

class _ThoughtRecordExercisePageState extends State<ThoughtRecordExercisePage> {
  late final TextEditingController _thoughtCtrl;
  final _reasonCtrl = TextEditingController();
  final _alternativeCtrl = TextEditingController();
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _thoughtCtrl = TextEditingController(text: widget.initialThought ?? '');
  }

  @override
  void dispose() {
    _thoughtCtrl.dispose();
    _reasonCtrl.dispose();
    _alternativeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = AuthServiceScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = ThoughtRecordRepository(available: auth.available);
    await repo.create(
      profile.uid,
      ThoughtRecord(
        thought: _thoughtCtrl.text.trim(),
        oneReasonTrue: _reasonCtrl.text.trim(),
        anotherWayToLook: _alternativeCtrl.text.trim(),
        createdAt: DateTime.now(),
        originSurface: widget.originSurface,
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Look at a thought' : '望吓一個諗法'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn
                      ? 'Three fields. No right or wrong answer.'
                      : '三條問題。冇所謂對錯。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _Label(text: isEn ? '1. The thought' : '一、嗰個諗法'),
                TextField(
                  controller: _thoughtCtrl,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _Label(
                  text: isEn
                      ? '2. One reason this thought might feel true'
                      : '二、呢個諗法可能感覺真嘅一個原因',
                ),
                TextField(
                  controller: _reasonCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _Label(
                  text: isEn
                      ? '3. One other way to look at the same thing'
                      : '三、可以點樣換個角度睇',
                ),
                TextField(
                  controller: _alternativeCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _saving || _saved ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _saved
                          ? (isEn ? 'Saved' : '已儲存')
                          : (isEn ? 'Save' : '儲存'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEn
                      ? 'Saved records stay in your account. There is no '
                          'analysis or score — only your own writing.'
                      : '記錄會留喺你嘅帳戶。冇分析、冇分數，淨係你自己寫嘅嘢。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
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
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

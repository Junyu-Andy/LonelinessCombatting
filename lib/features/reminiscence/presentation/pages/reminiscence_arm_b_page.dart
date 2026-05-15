import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../data/reminiscence_themes.dart';

/// M3 — Reminiscence, Arm B (rule-based).
///
/// Spec §M3 Arm B flow:
///   1. Same themed opening prompt.
///   2. User writes or speaks into a text field.
///   3. No follow-up. End-of-session: user is shown their own text and
///      asked to save it.
///   4. Past entries are accessible as a list — the system never refers
///      back to them mid-session.
class ReminiscenceArmBPage extends StatefulWidget {
  final ReminiscenceTheme theme;
  const ReminiscenceArmBPage({super.key, required this.theme});

  @override
  State<ReminiscenceArmBPage> createState() => _ReminiscenceArmBPageState();
}

class _ReminiscenceArmBPageState extends State<ReminiscenceArmBPage> {
  final _textCtrl = TextEditingController();
  bool _busy = false;
  bool _saved = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _textCtrl.text.trim();
    if (body.isEmpty) return;
    final profile = AppSettingsScope.read(context).profile;
    final core = CoreServicesScope.of(context);
    setState(() => _busy = true);
    if (profile != null) {
      await core.memory.writeSummary(
        uid: profile.uid,
        moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
        summary: body,
        armCode: 'B',
        hasTranscriptConsent: profile.consent.transcriptRetention,
        tags: ['week:${widget.theme.weekIndex}'],
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.theme.titleEn : widget.theme.titleZh;
    final opening =
        isEn ? widget.theme.openingEn : widget.theme.openingZh;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(opening, style: theme.textTheme.bodyLarge),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  maxLines: null,
                  expands: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: isEn
                        ? 'Write whatever you remember.'
                        : '記得幾多寫幾多，慢慢寫。',
                    alignLabelWithHint: true,
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _saved ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _saved
                        ? (isEn ? 'Saved' : '已儲存')
                        : (isEn ? 'Save this memory' : '儲存呢段回憶'),
                    style: const TextStyle(fontSize: 20),
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

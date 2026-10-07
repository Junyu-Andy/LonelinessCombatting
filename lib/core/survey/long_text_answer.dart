import 'package:flutter/material.dart';

import '../feature_flags/remote_feature_flags.dart';
import '../voice/voice_input_button.dart';

/// T17 — long free-text answer shared by ADA Part D and the day-7 open
/// questions: a question, a hint, a multi-line field and, only when
/// `app_config/feature_flags.voiceInputEnabled` is on, a mic button.
/// With the flag off the participant can only type (no mic, no
/// "or speak" label).
///
/// The host reads the input mode from [voice] via
/// [VoiceInputController.takeModality] when it saves.
class LongTextAnswer extends StatelessWidget {
  const LongTextAnswer({
    super.key,
    required this.question,
    required this.hint,
    required this.controller,
    required this.voice,
    this.enabled = true,
    this.voiceEnabled,
  });

  final String question;
  final String hint;
  final TextEditingController controller;
  final VoiceInputController voice;
  final bool enabled;

  /// Test hook; defaults to [RemoteFeatureFlags.voiceInputEnabled].
  final bool? voiceEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final showMic =
        enabled && (voiceEnabled ?? RemoteFeatureFlags.current.voiceInputEnabled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        if (showMic)
          Padding(
            key: const ValueKey('long_text_mic_row'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                VoiceInputButton(
                  controller: voice,
                  prefix: () => controller.text,
                  onText: (t) => controller.text = t,
                ),
                const SizedBox(width: 8),
                Text(
                  isEn ? 'or speak' : '或者用講嘅',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        TextField(
          key: const ValueKey('long_text_field'),
          controller: controller,
          enabled: enabled,
          minLines: 6,
          maxLines: 10,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}

/// `typed` or `voice` (any dictation used) for a saved answer.
String inputModeFrom((bool, int?) modality) =>
    modality.$1 ? 'voice' : 'typed';

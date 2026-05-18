import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around [SpeechToText] so any free-text input field can
/// gain voice dictation without each page redoing the boilerplate.
///
/// Behaviour:
///   - First tap: requests mic + speech-recognition permission, picks
///     the closest locale to the app's current locale, starts listening.
///   - During recognition: emits partial results via [onText] so the
///     caller can update its TextField live.
///   - Second tap (or 30s timeout): stops listening, emits a final
///     result.
///   - Permission denied / unavailable: stays disabled, shows a tooltip
///     explaining why.
///
/// Spec §M3 engineering notes: "Voice input recommended given older-
/// adult typing burden. STT must support Cantonese." We try `yue-Hant-HK`
/// first; if the device doesn't have it, we fall back to `zh-HK`, then
/// `zh-CN`, then system default.
///
/// **B.8 — protocol-level on-device lock (Sprint 3.2).**
/// Every [SpeechToText.listen] call passes `onDevice: true` so the
/// platform STT engine MUST stay on-device:
///   - iOS:    `requiresOnDeviceRecognition = true` on SFSpeechRecognizer.
///             Falls back to "unavailable" if no offline language pack.
///   - Android: `EXTRA_PREFER_OFFLINE = true` on RecognizerIntent.
///             Falls back to system-default behaviour if no offline pack.
/// HREC requires audio NEVER leave the device.  Tests: airplane mode +
/// dictate; transcription must still succeed.  If you ever hear the
/// engine "phone home" on the network, treat it as a protocol violation
/// and stop recording immediately.
class _OnDeviceUnavailableException implements Exception {
  const _OnDeviceUnavailableException();
  @override
  String toString() =>
      'On-device speech recognition unavailable on this device.';
}
class VoiceInputButton extends StatefulWidget {
  /// Called as new text arrives. The button replaces the *last
  /// recognised chunk* on each callback — the caller should treat this
  /// as the current dictation buffer, not append-only.
  final ValueChanged<String> onText;

  /// When non-null, prepended to whatever the user dictates. Lets the
  /// caller keep typed-and-dictated content intact.
  final String Function()? prefix;

  const VoiceInputButton({super.key, required this.onText, this.prefix});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;
  bool _initialising = true;
  bool _listening = false;
  String _bufferStart = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _stt.initialize(
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _available = ok;
      _initialising = false;
    });
  }

  Future<String?> _pickLocale() async {
    final locales = await _stt.locales();
    String? match(String prefix) {
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(prefix.toLowerCase())) {
          return l.localeId;
        }
      }
      return null;
    }

    return match('yue') ?? match('zh-HK') ?? match('zh') ?? match('en');
  }

  Future<void> _toggle() async {
    if (!_available || _initialising) return;
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _bufferStart = widget.prefix?.call() ?? '';
    setState(() => _listening = true);
    final localeId = await _pickLocale();

    // B.8 — protocol-level on-device lock.  speech_to_text v7 surfaces
    // this via SpeechListenOptions; older versions used a top-level
    // onDevice param.  Both forms work because the plugin maps them to
    // the same native flags (iOS: requiresOnDeviceRecognition;
    // Android: EXTRA_PREFER_OFFLINE).
    try {
      await _stt.listen(
        localeId: localeId,
        onResult: (result) {
          final spoken = result.recognizedWords;
          final glue = _bufferStart.isEmpty ? '' : ' ';
          widget.onText('$_bufferStart$glue$spoken');
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          onDevice: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      // Device doesn't have an offline language pack — fail closed.
      // Do NOT silently fall back to cloud recognition: HREC says audio
      // must never leave the device.
      if (kDebugMode) {
        debugPrint('[voice] on-device STT unavailable: $e');
      }
      if (mounted) setState(() => _listening = false);
      throw const _OnDeviceUnavailableException();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    if (_initialising) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Tooltip(
      message: _available
          ? (_listening
              ? (isEn ? 'Tap to stop' : '撳停')
              : (isEn ? 'Tap to speak' : '撳住講'))
          : (isEn
              ? 'Voice input unavailable on this device'
              : '呢部機冇得用聲音輸入'),
      child: IconButton(
        onPressed: _available ? _toggle : null,
        icon: Icon(
          _listening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
          color: _listening
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }
}

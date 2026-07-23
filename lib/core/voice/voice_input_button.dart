import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'whisper_record_button.dart';

/// Handle a host page holds so it can stop in-progress dictation at a
/// precise moment — specifically right before it snapshots the input and
/// sends a message (B03).  Without this, the recogniser keeps running
/// after send: its session-cumulative results ("abc" → "abc de") get
/// written back into the just-cleared field, polluting the next message.
///
/// Bind one controller to one [VoiceInputButton]; calling [stopForSend]
/// when idle is a safe no-op.
class VoiceInputController {
  _VoiceInputButtonState? _state;

  void _bind(_VoiceInputButtonState state) => _state = state;
  void _unbind(_VoiceInputButtonState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Cancel any active dictation and discard pending recognition so no
  /// late callback can repopulate the input after it's been cleared.
  Future<void> stopForSend() async {
    await _state?._stopForSend();
  }
}

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
class VoiceInputButton extends StatefulWidget {
  /// Called as new text arrives. The button replaces the *last
  /// recognised chunk* on each callback — the caller should treat this
  /// as the current dictation buffer, not append-only.
  final ValueChanged<String> onText;

  /// When non-null, prepended to whatever the user dictates. Lets the
  /// caller keep typed-and-dictated content intact.
  final String Function()? prefix;

  /// When non-null, lets the host page stop dictation right before it
  /// sends (B03).
  final VoiceInputController? controller;

  const VoiceInputButton({
    super.key,
    required this.onText,
    this.prefix,
    this.controller,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;
  bool _initialising = true;
  bool _listening = false;
  String _bufferStart = '';
  // Set true by [_stopForSend] so a recognition callback that lands after
  // the user hit send can't write stale text back into the cleared field.
  // Reset when a fresh dictation starts.
  bool _suppressResults = false;

  // false → allow the platform's (usually cloud) recogniser for much
  // better Cantonese (HREC relaxed). true → strict on-device only.
  static const bool _onDeviceOnly = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _init();
  }

  Future<void> _init() async {
    // On some Android devices `initialize()` never completes (STT service
    // slow to bind, or the permission dialog is still up) — without a
    // timeout the button would spin forever. Cap it and fall back to the
    // "unavailable, tap to learn why" state instead of an endless spinner.
    bool ok = false;
    try {
      ok = await _stt
          .initialize(
            onError: (_) {
              if (mounted) setState(() => _listening = false);
            },
            onStatus: (status) {
              if (status == 'notListening' || status == 'done') {
                if (mounted) setState(() => _listening = false);
              }
            },
          )
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] initialize failed/timed out: $e');
      ok = false;
    }
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
    if (_initialising) return;
    if (!_available) {
      // Retry init once — permission may have just been granted after a
      // slow/timed-out first attempt, so a tap should recover rather than
      // dead-end on the hint.
      setState(() => _initialising = true);
      await _init();
      if (!mounted) return;
      if (!_available) {
        _showUnavailableHint();
        return;
      }
    }
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _bufferStart = widget.prefix?.call() ?? '';
    _suppressResults = false;
    setState(() => _listening = true);
    final localeId = await _pickLocale();

    // Recognition mode. HREC originally required on-device only (audio
    // never leaves the device), but that made Cantonese unreliable —
    // Android on-device 粤語 packs are missing on most phones. HREC has
    // since relaxed, so we allow the platform's (usually cloud) recogniser,
    // which has far better Cantonese. Flip [_onDeviceOnly] back to true to
    // reinstate the strict on-device lock.
    try {
      await _stt.listen(
        localeId: localeId,
        onResult: (result) {
          // Dropped once the user has hit send (B03) — a trailing partial
          // must not overwrite the freshly cleared field.
          if (_suppressResults) return;
          final spoken = result.recognizedWords;
          final glue = _bufferStart.isEmpty ? '' : ' ';
          widget.onText('$_bufferStart$glue$spoken');
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          onDevice: _onDeviceOnly,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      // Device doesn't have an offline language pack — fail closed.
      // Do NOT silently fall back to cloud recognition: HREC says audio
      // must never leave the device.  Tell the user how to fix it instead
      // of leaving a dead button.
      if (kDebugMode) {
        debugPrint('[voice] on-device STT unavailable: $e');
      }
      if (mounted) setState(() => _listening = false);
      _showUnavailableHint();
    }
  }

  /// B03 — called by [VoiceInputController.stopForSend] right before the
  /// host page snapshots the input and sends.  Cancels (not just stops)
  /// the recogniser so pending results are discarded, suppresses any
  /// straggler callback, and resets the buffer so the next dictation
  /// starts clean instead of appending to the sent text.
  Future<void> _stopForSend() async {
    _suppressResults = true;
    if (_listening || _stt.isListening) {
      try {
        await _stt.cancel();
      } catch (_) {
        // Best-effort: even if cancel throws, _suppressResults already
        // guards against late callbacks.
      }
    }
    _bufferStart = '';
    if (mounted && _listening) setState(() => _listening = false);
  }

  /// Shown when voice can't run — usually no offline language pack, or the
  /// mic / speech permission was denied. Tells the user exactly where to go.
  void _showUnavailableHint() {
    if (!mounted) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final where = isIos
        ? (isEn
            ? 'Settings → General → Keyboard → turn on Dictation, and download '
                'the Chinese / Cantonese language'
            : '設定 → 一般 → 鍵盤 → 開啟「聽寫」，並下載中文／粵語語言')
        : (isEn
            ? 'Settings → System → Languages & input → Voice input → Offline '
                'speech recognition → download Chinese / Cantonese'
            : '設定 → 系統 → 語言及輸入 → 語音輸入 → 離線語音識別 → 下載中文／粵語');
    final msg = isEn
        ? "Voice input isn't ready on this phone (no offline speech pack, or "
            'mic permission is off). To use it: $where, and allow the '
            'microphone.'
        : '呢部機未準備好聲音輸入（未裝離線語音包，或者未開咪權限）。'
            '想用就：$where，並允許使用麥克風。';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 7)),
    );
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
    // No OS speech recogniser on this device (common on Chinese-ROM
    // Android) — fall back to the Whisper "hold to talk" record button
    // instead of a dead mic. iOS / devices with working STT keep the
    // native on-device path above.
    if (!_available) {
      return WhisperRecordButton(
        onText: widget.onText,
        prefix: widget.prefix,
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
        // Stay tappable even when unavailable so a tap can explain WHY
        // (missing language pack / permission) instead of being a dead icon.
        onPressed: _initialising ? null : _toggle,
        icon: Icon(
          _listening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
          color: _listening
              ? theme.colorScheme.error
              : _available
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
          size: 28,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _stt.stop();
    super.dispose();
  }
}

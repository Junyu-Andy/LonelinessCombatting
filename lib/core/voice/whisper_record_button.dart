import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'transcription_repository.dart';

/// WhatsApp-style "hold to talk" voice input, used as the fallback when the
/// device has no OS speech recogniser (e.g. Chinese-ROM Android where
/// speech_to_text's initialize() returns false).
///
/// Long-press to record; release to upload the clip to the `transcribeAudio`
/// Cloud Function (Whisper) and drop the transcript into the field. The audio
/// file is deleted right after upload; nothing is kept on device.
class WhisperRecordButton extends StatefulWidget {
  /// Called with the field's full new text (prefix + transcript).
  final ValueChanged<String> onText;

  /// Current field text, so a transcript is appended, not replaced.
  final String Function()? prefix;

  const WhisperRecordButton({super.key, required this.onText, this.prefix});

  @override
  State<WhisperRecordButton> createState() => _WhisperRecordButtonState();
}

class _WhisperRecordButtonState extends State<WhisperRecordButton> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _busy = false; // uploading / transcribing
  String? _path;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _hint(_permMsg());
        return;
      }
      final dir = await getTemporaryDirectory();
      final p =
          '${dir.path}/whisper_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: p,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _path = p;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[whisper] start failed: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_recording) return;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = true;
      });
    }
    try {
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return;
      final res = await TranscriptionRepository().transcribe(
        audioBase64: base64Encode(bytes),
      );
      if (!mounted) return;
      if (res.text.trim().isNotEmpty) {
        final prefix = widget.prefix?.call() ?? '';
        final glue = prefix.isEmpty ? '' : ' ';
        widget.onText('$prefix$glue${res.text.trim()}');
      } else {
        _hint(res.reason == 'openai_api_key_unset'
            ? _notConfiguredMsg()
            : _noSpeechMsg());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[whisper] transcribe failed: $e');
      _hint(_noSpeechMsg());
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';
  String _permMsg() => _isEn
      ? 'Please allow microphone access to use voice.'
      : '想用聲音輸入，請允許使用麥克風。';
  String _notConfiguredMsg() => _isEn
      ? 'Voice transcription is not set up on the server yet.'
      : '聲音轉文字喺伺服器嗰邊仲未設定好。';
  String _noSpeechMsg() => _isEn
      ? "Didn't catch that — hold the button and speak again."
      : '聽唔到喎 —— 按住個掣再講多次。';

  void _hint(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 5),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_busy) {
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
      message: _isEn ? 'Hold to talk' : '按住講',
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _stopAndTranscribe(),
        // A plain tap (no hold) explains how to use it.
        onTap: () => _hint(_isEn
            ? 'Hold the button and speak; release when done.'
            : '按住個掣講嘢，講完放手。'),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            _recording ? Icons.mic : Icons.mic_none_rounded,
            size: 28,
            color: _recording
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

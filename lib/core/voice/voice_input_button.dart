import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/analytics/presentation/analytics_scope.dart';
import '../../shared/widgets/top_notice_area.dart';
import '../feature_flags/remote_feature_flags.dart';
import 'transcription_repository.dart';
import 'voice_copy.dart';
import 'voice_recorder.dart';
import 'wav_encoder.dart';

/// Session-log event written when the server could not transcribe a clip
/// (T27, SPEC:C18, 10/9 item 13).  Payload: `sessionId`, `agentId`,
/// `category` (timeout | server_error | no_speech | too_long | unavailable),
/// `at` (ISO time).  Never the audio, never any text.  Both arms identical.
class VoiceTranscriptionFailedEvent {
  VoiceTranscriptionFailedEvent._();

  static const name = 'voice_transcription_failed';

  static Map<String, dynamic> payload({
    required String category,
    String? sessionId,
    String? agentId,
  }) =>
      {
        'sessionId': sessionId,
        'agentId': agentId,
        'category': category,
        'at': DateTime.now().toIso8601String(),
      };
}

/// Handle a host page holds so it can stop in-progress voice capture at a
/// precise moment — right before it snapshots the input and sends (B03) —
/// and, on chat pages, route the failure event into the session log.
///
/// Bind one controller to one [VoiceInputButton]; calling [stopForSend]
/// when idle is a safe no-op.
class VoiceInputController {
  _VoiceInputButtonState? _state;

  void _bind(_VoiceInputButtonState state) => _state = state;
  void _unbind(_VoiceInputButtonState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Set by chat pages that own a `ChatSessionRecorder` so the failure
  /// event carries the session id and companion.  When null the button
  /// logs the same event through [AnalyticsScope] without a session id.
  void Function(String category)? onTranscriptionFailed;

  // L-1 input.modality — accumulated by the button while recording and
  // drained by the host page at send time via [takeModality].
  bool _voiceUsed = false;
  int _voiceMs = 0;
  DateTime? _listenStartedAt;

  void _onListenStart() {
    _voiceUsed = true;
    _listenStartedAt = DateTime.now();
  }

  void _onListenStop() {
    final s = _listenStartedAt;
    if (s != null) _voiceMs += DateTime.now().difference(s).inMilliseconds;
    _listenStartedAt = null;
  }

  /// Returns `(usedVoice, voiceDurationMs)` for the message about to be
  /// sent and resets the accumulator for the next one.
  (bool, int?) takeModality() {
    _onListenStop();
    final r = (_voiceUsed, _voiceUsed ? _voiceMs : null);
    _voiceUsed = false;
    _voiceMs = 0;
    return r;
  }

  /// Cancel any active recording / pending transcription so no late result
  /// can repopulate the input after it has been cleared.
  Future<void> stopForSend() async {
    await _state?._stopForSend();
  }
}

/// Microphone button for every free-text field (T27, SPEC:C18).
///
/// Flow:
///   - Tap: ask mic permission, start streaming 16 kHz PCM into memory.
///   - Tap again (or the 60 s cap): stop, wrap as WAV, send to the
///     `transcribeAudio` Cloud Function (Google STT v2 `chirp_2`,
///     `asia-southeast1`), put the text into the input box via [onText].
///     The elder can edit it or type instead; sending is the host page's
///     ordinary send, so the text goes through the same safety flow as
///     typed text.
///   - Failure (server retried once): S6 appears in a small card anchored
///     to the mic, next to the input box — not a chat bubble, not written
///     to turns or memory — and a `voice_transcription_failed` event is
///     logged with the failure category only.  1020l §一 (2): on a page
///     with a top notice area (the 小欣 chat window) S6 and the
///     microphone-permission note show there, under the app bar, instead.
///
/// No file is written: the clip lives in a [BytesBuilder] until upload and
/// is dropped right after.  No on-device / platform recogniser is used.
///
/// **C18 — Phase B switch (decision 0019).** The button renders nothing
/// and never touches the microphone (no permission prompt, no audio)
/// unless `app_config/feature_flags.voiceInputEnabled` is true
/// ([RemoteFeatureFlags.voiceInputEnabled], default off).  Every page's
/// mic goes through this widget, so the one switch covers them all.
/// Important feature: switch back on once HREC approves the STT amendment.
class VoiceInputButton extends StatefulWidget {
  /// Called with the new full text for the field (prefix + transcript).
  final ValueChanged<String> onText;

  /// When non-null, prepended to the transcript so typed text is kept.
  final String Function()? prefix;

  /// When non-null, lets the host page stop capture right before it
  /// sends (B03) and route the failure event into its session log.
  final VoiceInputController? controller;

  const VoiceInputButton({
    super.key,
    required this.onText,
    this.prefix,
    this.controller,
  });

  /// Test hooks: replace the microphone and the server call.
  @visibleForTesting
  static VoiceRecorder Function()? debugRecorderFactory;
  @visibleForTesting
  static TranscriptionClient? debugTranscriptionClient;

  /// Longest clip the server accepts synchronously (Google: 60 s).
  static const Duration maxClip = Duration(seconds: 60);

  /// How long the S6 card stays if the elder does nothing.
  static const Duration noticeDuration = Duration(seconds: 12);

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

enum _Phase { idle, recording, transcribing }

class _VoiceInputButtonState extends State<VoiceInputButton> {
  // Read once per mount: a flag change applies to newly opened pages.
  final bool _enabled = RemoteFeatureFlags.current.voiceInputEnabled;

  VoiceRecorder? _recorder;
  TranscriptionClient? _client;
  _Phase _phase = _Phase.idle;
  BytesBuilder? _pcm;
  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _streamDone;
  Timer? _capTimer;
  Timer? _noticeTimer;
  bool _suppressResult = false;
  String _bufferStart = '';
  bool _showNotice = false;
  final _noticeLink = LayerLink();
  final _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    widget.controller?._bind(this);
    _recorder = (VoiceInputButton.debugRecorderFactory ?? RecordVoiceRecorder.new)();
    _client = VoiceInputButton.debugTranscriptionClient ??
        CloudTranscriptionClient();
  }

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';

  Future<void> _toggle() async {
    switch (_phase) {
      case _Phase.transcribing:
        return;
      case _Phase.recording:
        await _stopAndTranscribe();
        return;
      case _Phase.idle:
        await _startRecording();
        return;
    }
  }

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    _hideNotice();
    bool ok = false;
    try {
      ok = await recorder.hasPermission();
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] permission check failed: $e');
    }
    if (!mounted) return;
    if (!ok) {
      _showPermissionHint();
      return;
    }
    _bufferStart = widget.prefix?.call() ?? '';
    _suppressResult = false;
    final pcm = BytesBuilder(copy: false);
    final done = Completer<void>();
    try {
      final stream = await recorder.start();
      _pcm = pcm;
      _streamDone = done;
      _sub = stream.listen(
        pcm.add,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e) {
          if (kDebugMode) debugPrint('[voice] stream error: ${e.runtimeType}');
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] start failed: ${e.runtimeType}');
      if (mounted) _showPermissionHint();
      return;
    }
    if (!mounted) return;
    widget.controller?._onListenStart();
    setState(() => _phase = _Phase.recording);
    _capTimer?.cancel();
    _capTimer = Timer(VoiceInputButton.maxClip, () {
      if (mounted && _phase == _Phase.recording) _stopAndTranscribe();
    });
  }

  Future<void> _stopAndTranscribe() async {
    final recorder = _recorder;
    final client = _client;
    final pcm = _pcm;
    final done = _streamDone;
    if (recorder == null || client == null || pcm == null) return;
    _capTimer?.cancel();
    widget.controller?._onListenStop();
    if (mounted) setState(() => _phase = _Phase.transcribing);
    try {
      await recorder.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] stop failed: ${e.runtimeType}');
    }
    // Wait (briefly) for the last chunks; the platform closes the stream.
    if (done != null) {
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    // Not awaited: on an already-closed stream cancel() hands back a
    // root-zone completed future, which never resumes under fake async.
    unawaited(_sub?.cancel());
    _sub = null;
    _pcm = null;
    _streamDone = null;

    final bytes = pcm.takeBytes();
    if (_suppressResult) {
      _finish();
      return;
    }
    if (bytes.isEmpty) {
      _fail(TranscriptionFailure.noSpeech);
      return;
    }
    final wav = WavEncoder.fromPcm16(
      bytes,
      sampleRate: VoiceRecorder.sampleRate,
      channels: VoiceRecorder.channels,
    );
    final result = await client.transcribe(wav);
    if (!mounted || _suppressResult) {
      _finish();
      return;
    }
    if (result.ok) {
      final glue = _bufferStart.isEmpty ? '' : ' ';
      widget.onText('$_bufferStart$glue${result.text}');
      _finish();
    } else {
      _fail(result.failure ?? TranscriptionFailure.serverError);
    }
  }

  void _finish() {
    _bufferStart = '';
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _fail(String category) {
    _logFailure(category);
    _finish();
    _showS6Notice();
  }

  void _logFailure(String category) {
    final via = widget.controller?.onTranscriptionFailed;
    if (via != null) {
      via(category);
      return;
    }
    if (!mounted) return;
    final scope = context.getInheritedWidgetOfExactType<AnalyticsScope>();
    scope?.analytics.logEvent(
      VoiceTranscriptionFailedEvent.name,
      VoiceTranscriptionFailedEvent.payload(category: category),
    );
  }

  /// B03 — called by [VoiceInputController.stopForSend] right before the
  /// host page snapshots the input and sends.  Discards the clip and any
  /// pending transcript so nothing lands in the freshly cleared field.
  Future<void> _stopForSend() async {
    _suppressResult = true;
    _capTimer?.cancel();
    widget.controller?._onListenStop();
    if (_phase == _Phase.recording) {
      try {
        await _recorder?.cancel();
      } catch (_) {
        // Best effort; _suppressResult already guards the result path.
      }
      unawaited(_sub?.cancel());
      _sub = null;
      _pcm = null;
      _streamDone = null;
      _finish();
    }
    _bufferStart = '';
  }

  // ---------------------------------------------------------------------
  // Notices
  // ---------------------------------------------------------------------

  /// 1020l §一 (2): the S6 card's id in a page's top notice area.
  static const _s6TopId = 'voice_s6';

  void _showS6Notice() {
    if (!mounted) return;
    _noticeTimer?.cancel();
    // A page with a top notice area (the 小欣 chat window) shows S6 there,
    // under the app bar, not over the newest message; same words, same
    // time on screen.
    final top = TopNotices.maybeOf(context);
    if (top != null) {
      top.showText(
          _s6TopId,
          _isEn
              ? VoiceCopy.s6TranscriptionFailedEn
              : VoiceCopy.s6TranscriptionFailed,
          duration: VoiceInputButton.noticeDuration);
      return;
    }
    setState(() => _showNotice = true);
    _overlay.show();
    _noticeTimer = Timer(VoiceInputButton.noticeDuration, _hideNotice);
  }

  void _hideNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    if (!mounted) return;
    TopNotices.maybeOf(context)?.dismiss(_s6TopId);
    if (_overlay.isShowing) _overlay.hide();
    if (_showNotice) setState(() => _showNotice = false);
  }

  /// Mic permission missing: tell the elder where to allow it.  Not S6 —
  /// nothing was recorded, so no failure event either.
  void _showPermissionHint() {
    if (!mounted) return;
    final text = _isEn
        ? 'Please allow the microphone in Settings to use voice input.'
        : '想用聲音輸入，請喺「設定」允許使用麥克風。';
    const duration = Duration(seconds: 6);
    // 1020l §一 (2): at the top on a page with a top notice area.
    final top = TopNotices.maybeOf(context);
    if (top != null) {
      top.showText('voice_mic_permission', text, duration: duration);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: duration,
      ));
  }

  Widget _buildNotice(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return CompositedTransformFollower(
      link: _noticeLink,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -6),
      showWhenUnlinked: false,
      child: Material(
        key: const ValueKey('voice_s6_notice'),
        color: theme.colorScheme.surfaceContainerHighest,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _hideNotice,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (width - 32).clamp(200, 420)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                _isEn
                    ? VoiceCopy.s6TranscriptionFailedEn
                    : VoiceCopy.s6TranscriptionFailed,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  height: 1.4,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final Widget icon;
    final String tip;
    switch (_phase) {
      case _Phase.transcribing:
        icon = const SizedBox(
          width: 28,
          height: 28,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
        tip = _isEn ? 'Turning speech into text…' : '轉文字中…';
        break;
      case _Phase.recording:
        icon = Icon(Icons.stop_circle_rounded,
            color: theme.colorScheme.error, size: 28);
        tip = _isEn ? 'Tap to stop' : '撳停';
        break;
      case _Phase.idle:
        icon = Icon(Icons.mic_none_rounded,
            color: theme.colorScheme.primary, size: 28);
        tip = _isEn ? 'Tap to speak' : '撳住講';
        break;
    }
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildNotice,
      child: CompositedTransformTarget(
        link: _noticeLink,
        child: Tooltip(
          message: tip,
          child: IconButton(
            onPressed: _phase == _Phase.transcribing ? null : _toggle,
            icon: icon,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _capTimer?.cancel();
    _noticeTimer?.cancel();
    _sub?.cancel();
    if (_phase == _Phase.recording) {
      // ignore: discarded_futures
      _recorder?.cancel().catchError((_) {});
    }
    _recorder?.dispose();
    super.dispose();
  }
}

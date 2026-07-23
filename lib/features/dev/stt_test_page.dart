import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/voice/transcription_repository.dart';

/// Minimal Cantonese STT vertical-slice test page (TASK_stt_vertical_slice).
///
/// Tap to start, tap to stop (NO press-and-hold — older adults' fine-motor
/// control makes hold-to-talk error-prone). Records aac 16k mono, sends the
/// clip to `transcribeAudio` (Google Cloud STT v2, yue-Hant-HK), and drops the
/// transcript into an EDITABLE field. A debug line shows model / region /
/// latency for A/B engine comparison.
class SttTestPage extends StatefulWidget {
  const SttTestPage({super.key});

  @override
  State<SttTestPage> createState() => _SttTestPageState();
}

class _SttTestPageState extends State<SttTestPage>
    with SingleTickerProviderStateMixin {
  static const _maxSeconds = 55; // sync recognize caps at 60s

  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _resultCtrl = TextEditingController();
  late final AnimationController _pulse;

  bool _recording = false;
  bool _transcribing = false;
  int _elapsed = 0;
  Timer? _timer;
  String? _path;
  String? _debug;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_transcribing) return;
    if (_recording) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) setState(() => _error = '請先允許使用麥克風。');
      return;
    }
    final dir = await getTemporaryDirectory();
    final p = '${dir.path}/stt_${DateTime.now().millisecondsSinceEpoch}.m4a';
    // Tuned for older adults: 64k (not 32k) so soft/breathy voices don't drop
    // syllables; 16k mono is the STT ceiling — higher just wastes bandwidth.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: p,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _path = p;
      _elapsed = 0;
      _error = null;
      _debug = null;
    });
    // No VAD auto-stop — older adults pause between clauses far longer than
    // default thresholds; only the hard 55s cap or a manual tap ends it.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += 1);
      if (_elapsed >= _maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    try {
      if (path == null) {
        setState(() => _error = _friendlyError());
        return;
      }
      final bytes = await File(path).readAsBytes();
      final res = await TranscriptionRepository().transcribe(
        audioBase64: base64Encode(bytes),
        mimeType: 'audio/mp4',
      );
      if (!mounted) return;
      if (res.ok && res.transcript.trim().isNotEmpty) {
        setState(() {
          _resultCtrl.text = res.transcript.trim();
          _debug = 'model=${res.model}  region=${res.region}  '
              '${res.latencyMs}ms';
          _error = null;
        });
      } else {
        setState(() {
          _error = _friendlyError();
          if (res.error != null) _debug = 'error=${res.error}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = _friendlyError());
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _transcribing = false);
    }
  }

  // Never imply the user spoke wrongly.
  String _friendlyError() => '聽唔清楚，唔該再講一次。';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nearLimit = _elapsed >= 50;
    return Scaffold(
      appBar: AppBar(title: const Text('粵語語音測試')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _RecordButton(
                recording: _recording,
                transcribing: _transcribing,
                pulse: _pulse,
                onTap: _transcribing ? null : _toggle,
              )),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  _transcribing
                      ? '處理緊，請等等…'
                      : _recording
                          ? '講緊嘢… 撳一下就完成'
                          : '撳一下開始講',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              if (_recording) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '$_elapsed / $_maxSeconds 秒',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: nearLimit
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (nearLimit)
                  Center(
                    child: Text('就快夠鐘喇',
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        fontSize: 17, color: theme.colorScheme.error),
                  ),
                ),
              const Text('轉出嚟嘅文字（可以改）：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 8),
              TextField(
                controller: _resultCtrl,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(fontSize: 18, height: 1.4),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (_debug != null)
                Text(
                  _debug!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool recording;
  final bool transcribing;
  final Animation<double> pulse;
  final VoidCallback? onTap;

  const _RecordButton({
    required this.recording,
    required this.transcribing,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = recording ? theme.colorScheme.error : theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (recording)
              AnimatedBuilder(
                animation: pulse,
                builder: (_, __) => Container(
                  width: 150 + pulse.value * 28,
                  height: 150 + pulse.value * 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                  ),
                ),
              ),
            Container(
              // Well above the 88pt minimum tap target.
              width: 140,
              height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: transcribing
                  ? const Padding(
                      padding: EdgeInsets.all(46),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Icon(
                      recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 68,
                      color: Colors.white,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

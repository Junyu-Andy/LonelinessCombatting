import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart' as rec;

/// Microphone capture for server-side STT (T27).  Audio is streamed from
/// the recorder into memory as 16 kHz mono PCM16 — no file is ever written
/// (the `record` package's stream mode skips the disk entirely).  The real
/// implementation wraps `record`'s [rec.AudioRecorder]; tests inject a fake.
abstract class VoiceRecorder {
  static const int sampleRate = 16000;
  static const int channels = 1;

  /// Ask for (and if needed request) microphone permission.
  Future<bool> hasPermission();

  /// Start streaming PCM16 chunks.
  Future<Stream<Uint8List>> start();

  /// Stop; the stream from [start] closes once the last chunk is delivered.
  Future<void> stop();

  /// Stop and discard without waiting for the stream to flush.
  Future<void> cancel();

  Future<void> dispose();
}

/// `record`-backed recorder.
class RecordVoiceRecorder implements VoiceRecorder {
  final rec.AudioRecorder _recorder = rec.AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
        const rec.RecordConfig(
          encoder: rec.AudioEncoder.pcm16bits,
          sampleRate: VoiceRecorder.sampleRate,
          numChannels: VoiceRecorder.channels,
          // Elders speak softly and far from the phone; let the OS help.
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

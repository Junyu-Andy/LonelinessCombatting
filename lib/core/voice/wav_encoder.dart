import 'dart:typed_data';

/// Wrap raw 16-bit little-endian PCM in a 44-byte WAV header so the server
/// can hand it to Google STT v2 with `autoDecodingConfig` (T27).  Pure Dart,
/// no file involved: the clip stays in memory from the microphone to the
/// upload and is dropped afterwards.
class WavEncoder {
  WavEncoder._();

  static const int headerBytes = 44;

  /// Bytes of PCM per second for the given format.
  static int bytesPerSecond({required int sampleRate, required int channels}) =>
      sampleRate * channels * 2;

  /// Duration of a PCM payload in milliseconds.
  static int durationMs(
    int pcmBytes, {
    required int sampleRate,
    required int channels,
  }) {
    final bps = bytesPerSecond(sampleRate: sampleRate, channels: channels);
    if (bps <= 0) return 0;
    return (pcmBytes * 1000) ~/ bps;
  }

  /// PCM16 → WAV (RIFF) bytes.
  static Uint8List fromPcm16(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
  }) {
    final out = Uint8List(headerBytes + pcm.length);
    final b = ByteData.sublistView(out);
    const bitsPerSample = 16;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final byteRate = sampleRate * blockAlign;

    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    b.setUint16(20, 1, Endian.little); // audio format 1 = PCM
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, byteRate, Endian.little);
    b.setUint16(32, blockAlign, Endian.little);
    b.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, pcm.length, Endian.little);
    out.setRange(headerBytes, out.length, pcm);
    return out;
  }
}

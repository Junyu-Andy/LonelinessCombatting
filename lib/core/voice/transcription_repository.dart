import 'package:cloud_functions/cloud_functions.dart';

/// Result of a `transcribeAudio` (Google Cloud STT v2) round-trip.
class TranscriptionResult {
  final String transcript;
  final double? confidence;

  /// Which tier actually served the request (chirp_2 / long) — kept visible
  /// for A/B comparison.
  final String? model;
  final String? region;
  final int? latencyMs;

  /// Null on success; an error code otherwise.
  final String? error;

  const TranscriptionResult({
    required this.transcript,
    this.confidence,
    this.model,
    this.region,
    this.latencyMs,
    this.error,
  });

  bool get ok => error == null;
}

/// Client wrapper over the `transcribeAudio` Cloud Function (Google Cloud
/// Speech-to-Text v2). Cantonese-first: default language is `yue-Hant-HK`,
/// which preserves 嘅/唔/咗/佢/冇 — do not send `zh` / `zh-HK`.
class TranscriptionRepository {
  TranscriptionRepository({this.available = true});

  final bool available;

  Future<TranscriptionResult> transcribe({
    required String audioBase64,
    String mimeType = 'audio/mp4',
    String languageCode = 'yue-Hant-HK',
    String? model,
  }) async {
    if (!available || audioBase64.isEmpty) {
      return const TranscriptionResult(transcript: '', error: 'unavailable');
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('transcribeAudio')
          .call(<String, dynamic>{
            'audioBase64': audioBase64,
            'mimeType': mimeType,
            'languageCode': languageCode,
            if (model != null) 'model': model,
          })
          .timeout(const Duration(seconds: 120));
      final data = result.data;
      if (data is Map) {
        return TranscriptionResult(
          transcript: (data['transcript'] as String?) ?? '',
          confidence: (data['confidence'] as num?)?.toDouble(),
          model: data['model'] as String?,
          region: data['region'] as String?,
          latencyMs: (data['latencyMs'] as num?)?.toInt(),
        );
      }
      return const TranscriptionResult(
        transcript: '',
        error: 'malformed_response',
      );
    } on FirebaseFunctionsException catch (e) {
      return TranscriptionResult(
        transcript: '',
        error: 'function_error:${e.code}',
      );
    } catch (_) {
      return const TranscriptionResult(transcript: '', error: 'network_error');
    }
  }
}

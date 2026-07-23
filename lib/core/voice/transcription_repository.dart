import 'package:cloud_functions/cloud_functions.dart';

/// Result of a Whisper transcription round-trip.
class TranscriptionResult {
  final String text;

  /// True when the backend reports it isn't configured (OPENAI_API_KEY unset)
  /// or the call failed — the UI degrades to a hint rather than a silent
  /// empty field.
  final bool unavailable;
  final String? reason;

  const TranscriptionResult({
    required this.text,
    this.unavailable = false,
    this.reason,
  });
}

/// Client wrapper over the `transcribeAudio` Cloud Function (server-side
/// Whisper). Used as the voice-input path on devices with no OS speech
/// recogniser (e.g. Chinese-ROM Android).
class TranscriptionRepository {
  TranscriptionRepository({this.available = true});

  /// False when Firebase isn't configured (guest / offline) — transcription
  /// is impossible.
  final bool available;

  Future<TranscriptionResult> transcribe({
    required String audioBase64,
    String mimeType = 'audio/m4a',
    String language = 'zh',
  }) async {
    if (!available || audioBase64.isEmpty) {
      return const TranscriptionResult(
        text: '',
        unavailable: true,
        reason: 'unavailable',
      );
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('transcribeAudio')
          .call(<String, dynamic>{
            'audioBase64': audioBase64,
            'mimeType': mimeType,
            'language': language,
          })
          .timeout(const Duration(seconds: 60));
      final data = result.data;
      if (data is Map) {
        return TranscriptionResult(
          text: (data['text'] as String?) ?? '',
          unavailable: (data['unavailable'] as bool?) ?? false,
          reason: data['reason'] as String?,
        );
      }
      return const TranscriptionResult(
        text: '',
        unavailable: true,
        reason: 'malformed_response',
      );
    } on FirebaseFunctionsException catch (e) {
      return TranscriptionResult(
        text: '',
        unavailable: true,
        reason: 'function_error:${e.code}',
      );
    } catch (_) {
      return const TranscriptionResult(
        text: '',
        unavailable: true,
        reason: 'network_error',
      );
    }
  }
}

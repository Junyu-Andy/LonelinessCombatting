import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Failure categories of a server transcription (T27, SPEC:C18).  The
/// server (`functions/stt.js`) returns one of these in the error details;
/// the app adds nothing of its own except `timeout` for its own deadline
/// and `unavailable` when the call could not be made.  Both arms identical.
class TranscriptionFailure {
  TranscriptionFailure._();

  static const timeout = 'timeout';
  static const serverError = 'server_error';
  static const noSpeech = 'no_speech';
  static const tooLong = 'too_long';
  static const unavailable = 'unavailable';

  static const all = {timeout, serverError, noSpeech, tooLong, unavailable};

  /// Map a callable error to a category.  Prefers the server's own
  /// `details.category`; falls back on the Firebase code.
  static String fromFunctionsError(FirebaseFunctionsException e) {
    final d = e.details;
    if (d is Map && d['category'] is String && all.contains(d['category'])) {
      return d['category'] as String;
    }
    switch (e.code) {
      case 'deadline-exceeded':
        return timeout;
      case 'unavailable':
      case 'failed-precondition': // flag off on the server
      case 'unauthenticated':
      case 'permission-denied':
        return unavailable;
      case 'not-found':
        return noSpeech;
      case 'invalid-argument':
        return tooLong;
      default:
        return serverError;
    }
  }
}

/// Outcome of one `transcribeAudio` round-trip: either [text] or a
/// [failure] category.  Never both; never carries audio.
class TranscriptionResult {
  const TranscriptionResult.ok(this.text) : failure = null;
  const TranscriptionResult.failed(this.failure) : text = '';

  final String text;
  final String? failure;

  bool get ok => failure == null;
}

/// Anything that can turn a WAV clip into text.  The real one calls the
/// Cloud Function; tests inject a fake.
abstract class TranscriptionClient {
  Future<TranscriptionResult> transcribe(Uint8List wavBytes);
}

/// Calls the `transcribeAudio` Cloud Function (Google STT v2, `chirp_2`,
/// `asia-southeast1`; see functions/stt.js).  The clip is base64-encoded
/// in memory and sent inline; nothing is written to disk or Cloud Storage.
/// Language is fixed on the server (`yue-Hant-HK`); the only request field
/// is `audioBase64`.
class CloudTranscriptionClient implements TranscriptionClient {
  CloudTranscriptionClient({this.available = true, this.timeout = _deadline});

  final bool available;
  final Duration timeout;

  /// Server does up to two 30 s attempts; leave headroom for the upload.
  static const _deadline = Duration(seconds: 75);

  @override
  Future<TranscriptionResult> transcribe(Uint8List wavBytes) async {
    if (!available || wavBytes.isEmpty) {
      return const TranscriptionResult.failed(TranscriptionFailure.unavailable);
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('transcribeAudio')
          .call(<String, dynamic>{'audioBase64': base64Encode(wavBytes)})
          .timeout(timeout);
      final data = result.data;
      final text = data is Map ? (data['transcript'] as String?) ?? '' : '';
      if (text.trim().isEmpty) {
        return const TranscriptionResult.failed(TranscriptionFailure.noSpeech);
      }
      return TranscriptionResult.ok(text.trim());
    } on FirebaseFunctionsException catch (e) {
      return TranscriptionResult.failed(
          TranscriptionFailure.fromFunctionsError(e));
    } on TimeoutException {
      return const TranscriptionResult.failed(TranscriptionFailure.timeout);
    } catch (e) {
      // Network / SDK errors: never log the payload, only the type.
      if (kDebugMode) debugPrint('[voice] transcribe failed: ${e.runtimeType}');
      return const TranscriptionResult.failed(TranscriptionFailure.unavailable);
    }
  }
}

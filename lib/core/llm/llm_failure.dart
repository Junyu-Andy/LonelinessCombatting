import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../connectivity/persist_retry_queue.dart';

/// Session-wide wiring for the persistence layer, set once in main.dart.
/// Free-function `persistQuietly` can't take injected dependencies without
/// threading them through every chat page, so these two live here.
///
/// [persistRetryQueue] — replays failed research-critical writes (see
/// PersistRetryQueue for scope). [persistTelemetry] — release-visible
/// `persist_failed` events to AnalyticsService.
PersistRetryQueue? persistRetryQueue;
void Function(String event, Map<String, dynamic> params)? persistTelemetry;

/// Structured failure taxonomy for the message-send pipeline.
///
/// Motivation (TestFlight incident, 2026-07): every failure mode — expired
/// auth, App Check rejection, DeepSeek timeout, Firestore permission-denied,
/// dead network — looked identical to the user (spinner, then either a
/// generic fallback line or nothing at all), and release builds logged
/// nothing. Each failure now carries a stable code that is (a) appended to
/// the user-facing message so a screenshot from a participant is enough to
/// diagnose, and (b) written to analytics via the gateway telemetry hook.
enum LlmFailureCode {
  /// CF rejected the call: no/expired Firebase Auth token.
  authExpired('AUTH-01', retriable: false),

  /// CF rejected the call: App Check / precondition failure.
  appCheckRejected('AUTH-02', retriable: false),

  /// Client-side 50s timeout — the callable never returned.
  clientTimeout('NET-01', retriable: true),

  /// CF-side deadline-exceeded / unavailable.
  serverTimeout('NET-02', retriable: true),

  /// CF `internal` — DeepSeek upstream error.
  upstreamError('SRV-01', retriable: true),

  /// Firestore permission-denied — security rules rejected this account's
  /// read/write. Account-level problem, not a network problem.
  firestoreDenied('FS-01', retriable: false),

  /// Firestore unavailable, or a guarded Firestore op timed out ("fake
  /// online": interface up but Google unreachable).
  firestoreUnavailable('FS-02', retriable: true),

  /// Anything not classified above.
  unknown('UNK-01', retriable: true);

  const LlmFailureCode(this.code, {required this.retriable});

  /// Stable short code shown to the user and written to telemetry.
  final String code;

  /// Whether "please try again" is honest advice for this failure.
  final bool retriable;
}

class LlmFailure {
  const LlmFailure(this.code, [this.detail]);

  final LlmFailureCode code;

  /// Raw diagnostic detail (exception message, CF error body). Telemetry
  /// only — never shown to the user.
  final String? detail;

  /// User-facing message with the error code appended, so a participant
  /// screenshot alone is enough to identify the failure mode.
  String userMessage(bool isEn) {
    final base = isEn ? _en : _zh;
    return isEn ? '$base (${code.code})' : '$base（${code.code}）';
  }

  String get _zh => switch (code) {
        LlmFailureCode.authExpired => '你嘅登入已經過期，請退出再重新登入一次。',
        LlmFailureCode.appCheckRejected => '暫時連接唔到服務，請通知研究團隊幫你檢查。',
        LlmFailureCode.clientTimeout => '等咗好耐都未有回覆，可能網絡唔穩定，請試多一次。'
            '（如果你而家喺內地，要開咗 VPN 先連接到。）',
        LlmFailureCode.serverTimeout => '伺服器回應超時，請過一陣再試。',
        LlmFailureCode.upstreamError => '服務暫時出咗問題，請過一陣再試。',
        LlmFailureCode.firestoreDenied => '你嘅帳戶資料讀取唔到，請通知研究團隊幫你檢查。',
        LlmFailureCode.firestoreUnavailable => '網絡好似唔穩定，請檢查網絡之後再試。'
            '（如果你而家喺內地，要開咗 VPN 先連接到。）',
        LlmFailureCode.unknown => '出咗啲問題，請再試一次。如果一直都係咁，請通知研究團隊。',
      };

  String get _en => switch (code) {
        LlmFailureCode.authExpired =>
          'Your sign-in has expired. Please sign out and sign in again.',
        LlmFailureCode.appCheckRejected =>
          'The app could not reach the service. Please let the research team know.',
        LlmFailureCode.clientTimeout =>
          'The reply took too long — the network may be unstable. Please try '
              'again. (In mainland China the app can only connect via VPN.)',
        LlmFailureCode.serverTimeout =>
          'The server took too long to respond. Please try again shortly.',
        LlmFailureCode.upstreamError =>
          'Something went wrong on the server. Please try again shortly.',
        LlmFailureCode.firestoreDenied =>
          'Your account data could not be read. Please let the research team know.',
        LlmFailureCode.firestoreUnavailable =>
          'The network seems unstable. Please check your connection and try '
              'again. (In mainland China the app can only connect via VPN.)',
        LlmFailureCode.unknown =>
          'Something went wrong. Please try again — if it keeps happening, '
              'let the research team know.',
      };

  /// Maps a `FirebaseFunctionsException.code` (cloud_functions plugin) to
  /// the taxonomy. Kept as a pure String → LlmFailure function so it is
  /// unit-testable without the plugin.
  static LlmFailure fromFunctionsCode(String code, [String? detail]) {
    final mapped = switch (code) {
      'unauthenticated' => LlmFailureCode.authExpired,
      'permission-denied' ||
      'failed-precondition' =>
        LlmFailureCode.appCheckRejected,
      'deadline-exceeded' || 'unavailable' => LlmFailureCode.serverTimeout,
      'internal' => LlmFailureCode.upstreamError,
      _ => LlmFailureCode.unknown,
    };
    return LlmFailure(mapped, detail);
  }
}

/// Thrown by [guardFirestore] (and pages that detect a failed
/// [LlmFailure] on a response) so the page-level send wrapper can surface
/// one consistent error bubble instead of silently swallowing.
class LlmFailureException implements Exception {
  const LlmFailureException(this.failure);
  final LlmFailure failure;

  @override
  String toString() => 'LlmFailureException(${failure.code.code})';
}

/// Default cap for a single awaited Firestore op on the send path. A
/// Firestore write future only completes on server ack, so on a network
/// that is up but cannot reach Google it would otherwise hang forever —
/// which is exactly the "spinner never stops" failure users reported.
const Duration kFirestoreGuardTimeout = Duration(seconds: 10);

/// Runs one Firestore read/write with a hard timeout and maps its failure
/// modes into [LlmFailureException]. Use on every awaited Firestore op
/// that blocks the chat send path.
Future<T> guardFirestore<T>(
  Future<T> Function() op, {
  Duration timeout = kFirestoreGuardTimeout,
}) async {
  try {
    return await op().timeout(timeout);
  } on TimeoutException {
    throw const LlmFailureException(
      LlmFailure(LlmFailureCode.firestoreUnavailable, 'guard timeout'),
    );
  } on FirebaseException catch (e) {
    final code = e.code == 'permission-denied'
        ? LlmFailureCode.firestoreDenied
        : LlmFailureCode.firestoreUnavailable;
    throw LlmFailureException(LlmFailure(code, '${e.plugin}/${e.code}'));
  }
}

/// Guarded, non-fatal persistence for writes whose failure must not kill an
/// otherwise successful turn (transcript/agent-context writes after the
/// reply is already available). The op can't hang the send path (hard
/// timeout), every failure is reported to [persistTelemetry], and genuinely
/// failed ops are handed to [persistRetryQueue] for replay.
///
/// Retry policy, per failure mode:
///  - Guard timeout: the op is still in flight — for plain Firestore writes
///    the SDK keeps it queued and syncs when the network returns, so
///    replaying here would double-write. Telemetry only.
///  - permission-denied: rules rejected this account; a replay can't
///    succeed. Telemetry only.
///  - Everything else (unavailable, aborted transaction, unexpected):
///    definitely not committed → enqueue for replay.
Future<void> persistQuietly(String tag, Future<void> Function() op) async {
  void report(LlmFailure f) {
    if (kDebugMode) {
      debugPrint('[$tag] persist failed: ${f.code.code} ${f.detail ?? ''}');
    }
    persistTelemetry?.call('persist_failed', {
      'tag': tag,
      'code': f.code.code,
      if (f.detail != null) 'detail': f.detail,
    });
  }

  try {
    await op().timeout(kFirestoreGuardTimeout);
  } on TimeoutException {
    report(const LlmFailure(
        LlmFailureCode.firestoreUnavailable, 'guard timeout'));
  } on FirebaseException catch (e) {
    final denied = e.code == 'permission-denied';
    report(LlmFailure(
      denied
          ? LlmFailureCode.firestoreDenied
          : LlmFailureCode.firestoreUnavailable,
      '${e.plugin}/${e.code}',
    ));
    if (!denied) persistRetryQueue?.enqueue(tag, op);
  } catch (e) {
    report(LlmFailure(LlmFailureCode.unknown, e.toString()));
    persistRetryQueue?.enqueue(tag, op);
  }
}

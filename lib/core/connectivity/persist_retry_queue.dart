import 'dart:async';

/// Session-scoped retry queue for research-critical persistence writes that
/// failed outright (see `persistQuietly` in core/llm/llm_failure.dart).
///
/// Scope and non-goals, so the guarantees are honest:
///  - Plain Firestore `set`/`update` writes DON'T need this queue: the SDK
///    queues them locally (surviving app restarts) and syncs when the
///    network returns. This queue exists for ops the SDK does NOT queue —
///    above all `runTransaction` (agent-context appendTurn), which fails
///    immediately offline.
///  - In-memory only: jobs are closures, so the queue is lost if the app is
///    killed. Within a session — the window in which virtually all "network
///    blipped mid-chat" failures live — every enqueued write is retried on
///    each connectivity-restored event and on a periodic tick.
///  - A job is dropped (with telemetry) after [maxAttempts] failed replays.
class PersistRetryQueue {
  PersistRetryQueue({
    Stream<bool>? onStatusChange,
    Duration? retryInterval = const Duration(seconds: 60),
    this.maxAttempts = 5,
    this.opTimeout = const Duration(seconds: 10),
    this.telemetry,
  }) {
    _sub = onStatusChange?.listen((online) {
      if (online) flush();
    });
    if (retryInterval != null) {
      _timer = Timer.periodic(retryInterval, (_) => flush());
    }
  }

  final int maxAttempts;
  final Duration opTimeout;

  /// Release-visible sink (wired to AnalyticsService in main.dart).
  final void Function(String event, Map<String, dynamic> params)? telemetry;

  final List<_Job> _jobs = [];
  StreamSubscription<bool>? _sub;
  Timer? _timer;
  bool _flushing = false;

  int get pendingCount => _jobs.length;

  void enqueue(String tag, Future<void> Function() op) {
    _jobs.add(_Job(tag, op));
    telemetry?.call('persist_retry_enqueued', {
      'tag': tag,
      'queued': _jobs.length,
    });
  }

  /// Replays every queued job once, FIFO. Safe to call concurrently —
  /// overlapping calls are coalesced.
  Future<void> flush() async {
    if (_flushing || _jobs.isEmpty) return;
    _flushing = true;
    try {
      for (final job in List.of(_jobs)) {
        try {
          await job.op().timeout(opTimeout);
          _jobs.remove(job);
          telemetry?.call('persist_retry_succeeded', {
            'tag': job.tag,
            'attempts': job.attempts + 1,
          });
        } catch (_) {
          job.attempts++;
          if (job.attempts >= maxAttempts) {
            _jobs.remove(job);
            telemetry?.call('persist_retry_dropped', {
              'tag': job.tag,
              'attempts': job.attempts,
            });
          }
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
  }
}

class _Job {
  _Job(this.tag, this.op);
  final String tag;
  final Future<void> Function() op;
  int attempts = 0;
}

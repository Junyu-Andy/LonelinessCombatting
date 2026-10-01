/// Per-screen dwell time tracker (Sprint 2 §3.3).
///
/// Wraps [AnalyticsService] enter/exit events with timestamp bookkeeping.

import '../../features/analytics/data/analytics_service.dart';

class ScreenDwellTracker {
  ScreenDwellTracker._();
  static final ScreenDwellTracker instance = ScreenDwellTracker._();

  AnalyticsService? _analytics;

  final Map<String, DateTime> _enteredAt = {};
  final Map<String, Map<String, String?>> _metadata = {};

  void bind(AnalyticsService analytics) {
    _analytics = analytics;
  }

  Future<void> enter(
    String screenName, {
    String? fromScreenName,
    String? agentId,
    String? moduleId,
  }) async {
    _enteredAt[screenName] = DateTime.now();
    _metadata[screenName] = {
      'agentId': agentId,
      'moduleId': moduleId,
    };
    await _analytics?.logScreenEntered(
      screenName: screenName,
      fromScreenName: fromScreenName,
      agentId: agentId,
      moduleId: moduleId,
    );
  }

  Future<void> exit(
    String screenName, {
    String? toScreenName,
    required String exitReason,
  }) async {
    final start = _enteredAt.remove(screenName);
    final meta = _metadata.remove(screenName);
    final dwell = start == null ? Duration.zero : DateTime.now().difference(start);
    final duration = dwell.inSeconds;
    // Phase A L-1 — spec-named event with millisecond dwell, alongside the
    // legacy screen_entered / screen_exited pair.
    await _analytics?.logEvent('screen_view', {
      'screen': screenName,
      'dwellMs': dwell.inMilliseconds,
      'exitReason': exitReason,
      if (meta?['agentId'] != null) 'agentId': meta!['agentId'],
      if (meta?['moduleId'] != null) 'moduleId': meta!['moduleId'],
    });
    await _analytics?.logScreenExited(
      screenName: screenName,
      durationSeconds: duration,
      toScreenName: toScreenName,
      exitReason: exitReason,
    );
  }

  /// Fires exit('background') for every currently-tracked screen.
  Future<void> backgroundAll() async {
    final names = _enteredAt.keys.toList();
    for (final n in names) {
      await exit(n, exitReason: 'background');
    }
  }
}

import 'analytics_service.dart';

/// Maps app entry triggers to the tab the system *intended* to surface,
/// regardless of where the user actually lands. The Day-3 / Day-7
/// retention assessment compares intent vs arrival to score
/// nav-to-target accuracy and time-to-arrival.
enum NavIntent { today, myStory, me, settings, unknown }

extension NavIntentX on NavIntent {
  String get analyticsKey => name;
}

/// P5.1 — covert behavioural measurement of "did the participant
/// reach the screen the trigger meant to take them to, and how long
/// did it take?".
///
/// Lifecycle:
///   1. App opens (cold start or from push). The shell calls
///      [startNavigationSession] with the inferred [NavIntent].
///   2. Each tab switch surfaces via [onTabChanged]. If the new tab
///      matches the intent we count it as a successful arrival and
///      emit `nav_to_tab` with `success=true`.
///   3. If the user backgrounds the app before reaching the intent,
///      [onSessionEnd] emits `nav_to_tab` with `success=false` so we
///      can compute abandonment.
///
/// All durations are wall-clock milliseconds; `wrong_taps` counts how
/// many off-target tabs the user touched before arriving.
class NavigationTelemetry {
  NavigationTelemetry({required this.analytics});

  final AnalyticsService analytics;

  DateTime? _sessionStartTime;
  NavIntent? _intent;
  String? _source;
  int _wrongTapCount = 0;
  int? _onboardingDayOffset;

  /// Set once per app lifetime when the user's onboarding timestamp
  /// becomes known (typically right after the consent flow). Used
  /// to bucket events into "Day 3" / "Day 7" of the protocol.
  void setOnboardingAnchor(DateTime onboardedAt) {
    _onboardingDayOffset =
        DateTime.now().difference(onboardedAt).inDays.clamp(0, 365);
  }

  /// Start a measurement window. [source] is a short tag like
  /// `'cold_start'`, `'push_m2_reminder'`, `'push_m7_followup'`. Pass
  /// [NavIntent.unknown] when there's no specific destination
  /// (e.g. plain app-icon tap) — telemetry won't emit events but it
  /// will still close cleanly on session end.
  void startNavigationSession({
    required NavIntent intent,
    required String source,
  }) {
    _sessionStartTime = DateTime.now();
    _intent = intent;
    _source = source;
    _wrongTapCount = 0;
  }

  /// Record a tab change. If it equals the intent we emit a
  /// successful `nav_to_tab` and close the window.
  void onTabChanged(NavIntent newTab) {
    final intent = _intent;
    final start = _sessionStartTime;
    if (intent == null || intent == NavIntent.unknown || start == null) {
      return;
    }
    if (newTab == intent) {
      _emitArrival(success: true);
      _reset();
    } else {
      _wrongTapCount++;
    }
  }

  /// Call when the app is backgrounded / killed. Emits a failed
  /// arrival if a measurement window is still open.
  void onSessionEnd() {
    if (_intent == null ||
        _intent == NavIntent.unknown ||
        _sessionStartTime == null) {
      _reset();
      return;
    }
    _emitArrival(success: false);
    _reset();
  }

  void _emitArrival({required bool success}) {
    final duration =
        DateTime.now().difference(_sessionStartTime!).inMilliseconds;
    analytics.logEvent('nav_to_tab', {
      'target_tab': _intent!.analyticsKey,
      'duration_ms': duration,
      'wrong_taps': _wrongTapCount,
      'success': success,
      if (_onboardingDayOffset != null)
        'day_since_onboarding': _onboardingDayOffset,
      if (_source != null) 'source': _source,
    });
  }

  void _reset() {
    _sessionStartTime = null;
    _intent = null;
    _source = null;
    _wrongTapCount = 0;
  }

  /// Static helper that maps an incoming app trigger into a
  /// [NavIntent]. Keep this in one place so the shell and any
  /// notification handler agree on routing semantics.
  static NavIntent inferIntent({
    required String trigger,
    Map<String, dynamic>? notificationPayload,
  }) {
    switch (trigger) {
      case 'push_m2_reminder':
      case 'push_m7_plan':
      case 'push_m7_followup_review':
        return NavIntent.today;
      case 'push_m3_session_reminder':
        return NavIntent.myStory;
      case 'push_m9_weekly_summary':
        return NavIntent.me;
      case 'cold_start':
      case 'app_icon':
      default:
        return NavIntent.unknown;
    }
  }
}

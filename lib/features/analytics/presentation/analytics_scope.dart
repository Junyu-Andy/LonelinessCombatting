import 'package:flutter/widgets.dart';

import '../data/analytics_service.dart';

/// Makes the app-wide [AnalyticsService] reachable from any widget without
/// prop-drilling. Matches the convention used by `AuthServiceScope` and
/// `AppSettingsScope`.
class AnalyticsScope extends InheritedWidget {
  final AnalyticsService analytics;

  const AnalyticsScope({
    super.key,
    required this.analytics,
    required super.child,
  });

  static AnalyticsService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AnalyticsScope>();
    assert(scope != null, 'AnalyticsScope missing above this widget');
    return scope!.analytics;
  }

  @override
  bool updateShouldNotify(AnalyticsScope oldWidget) =>
      oldWidget.analytics != analytics;
}

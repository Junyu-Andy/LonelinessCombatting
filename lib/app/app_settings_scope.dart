import 'package:flutter/widgets.dart';

import 'app_settings.dart';

/// Exposes [AppSettings] to descendant widgets. Using [InheritedNotifier]
/// instead of `provider` keeps the dependency surface small.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope missing above this widget');
    return scope!.notifier!;
  }

  /// Non-listening lookup for imperative callbacks (e.g. button handlers).
  static AppSettings read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope missing above this widget');
    return scope!.notifier!;
  }
}

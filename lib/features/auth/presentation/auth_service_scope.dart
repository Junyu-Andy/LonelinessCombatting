import 'package:flutter/widgets.dart';

import '../data/auth_service.dart';

/// Exposes the app-wide [AuthService] so leaves of the tree (settings page,
/// sign-out buttons) can reach it without prop-drilling.
class AuthServiceScope extends InheritedWidget {
  final AuthService authService;

  const AuthServiceScope({
    super.key,
    required this.authService,
    required super.child,
  });

  static AuthService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AuthServiceScope>();
    assert(scope != null, 'AuthServiceScope missing above this widget');
    return scope!.authService;
  }

  @override
  bool updateShouldNotify(AuthServiceScope oldWidget) =>
      oldWidget.authService != authService;
}

import 'package:flutter/widgets.dart';

import '../../../app/app_settings_scope.dart';
import 'pages/consent_page.dart';

/// Wraps the main shell and forces the consent screen to be the first thing
/// a signed-in user with no recorded consent sees. Once they accept (with
/// at least the required functional toggle), the gate becomes transparent.
class ConsentGate extends StatelessWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    if (profile == null) {
      // Guest mode — no consent collection (no Firestore to write to).
      return child;
    }
    if (!profile.consent.functionalData) {
      return const ConsentPage();
    }
    return child;
  }
}

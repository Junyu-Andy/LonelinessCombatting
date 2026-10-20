/// 1020d — which page a reminiscence week opens.  Switch
/// `app_config/feature_flags.reminiscenceV2Enabled` on: the v2 page for
/// both arms; off: the old arm A / arm B pages, exactly as before.  Every
/// entry point (landing, My Story's current week and timeline) asks here.
library;

import 'package:flutter/widgets.dart';

import '../../../core/arm/arm_scope.dart';
import '../../../core/feature_flags/remote_feature_flags.dart';
import '../data/reminiscence_themes.dart';
import 'pages/reminiscence_arm_a_page.dart';
import 'pages/reminiscence_arm_b_page.dart';
import 'pages/reminiscence_v2_page.dart';

class ReminiscenceRouter {
  ReminiscenceRouter._();

  static bool get v2 => RemoteFeatureFlags.current.reminiscenceV2Enabled;

  static Widget pageFor(BuildContext context, ReminiscenceTheme theme) {
    if (v2) return ReminiscenceV2Page(theme: theme);
    // The canonical Arm.isA lookup (FORCE_ARM applies).
    return Arm.isA(context)
        ? ReminiscenceArmAPage(theme: theme)
        : ReminiscenceArmBPage(theme: theme);
  }
}

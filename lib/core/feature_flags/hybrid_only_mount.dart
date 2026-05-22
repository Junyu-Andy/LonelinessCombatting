/// C.3 — affordance-level gating widget (Sprint 3.4).
///
/// Wrap a hybrid-only widget in [HybridOnlyMount] so it never renders
/// for Arm B participants, even on screens that are otherwise shared
/// across arms.  Distinct from [ArmGate] in two ways:
///
///   1. **Single-branch**: ArmGate forces both branches to exist side by
///      side and renders one of them; HybridOnlyMount has a single child
///      that either mounts or doesn't.  Use ArmGate when you want
///      sanctioned-difference parity testing (different content per arm);
///      use HybridOnlyMount when the affordance simply has no Arm B
///      equivalent.
///
///   2. **Affordance audit**: every call site names the affordance via
///      the `featureKey` constant.  The set of all keys lives in
///      [FeatureFlags.hybridOnlyAffordances] and is hardcoded — adding a
///      new hybrid-only affordance requires updating that set, which
///      shows up as a code review touchpoint.
///
/// Phase A behaviour: with `forceArmA = true` on the server every
/// participant has arm == A, so this widget always mounts.  Audit
/// command: grep for `HybridOnlyMount(featureKey: ...)` to enumerate
/// every Arm-B-blocked surface.
library;

import 'package:flutter/widgets.dart';

import '../arm/arm_scope.dart';
import 'feature_flags.dart';

class HybridOnlyMount extends StatelessWidget {
  /// Stable identifier from [FeatureFlags.hybridOnlyAffordances].
  /// Triggers an assertion in debug builds if the key isn't registered.
  final String featureKey;
  final Widget child;

  /// Optional fallback shown to Arm B.  Use sparingly — most hybrid
  /// affordances should disappear entirely rather than become a stub.
  final Widget? fallback;

  const HybridOnlyMount({
    super.key,
    required this.featureKey,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    assert(
      FeatureFlags.hybridOnlyAffordances.contains(featureKey),
      'HybridOnlyMount featureKey "$featureKey" not registered in '
      'FeatureFlags.hybridOnlyAffordances — add it there first so the '
      'audit set stays exhaustive.',
    );
    final isArmA = Arm.isA(context);
    if (FeatureFlags.allowsAffordance(featureKey, isArmA: isArmA)) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}

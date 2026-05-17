import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';
import '../../features/wellbeing/presentation/pages/calm_page.dart';
import 'distress_detector.dart';
import 'distress_state.dart';

/// Centralized routing for distress detections. Replaces per-module
/// ad-hoc safety sheets so the four-level response is identical
/// everywhere (P3.4).
///
/// Routing rules:
///   - `none` / `low`: update [DistressState] so the [SafetyOverlay]
///     pill repaints, but do not interrupt the user's flow.
///   - `moderate`: pill repaints, and after the current turn settles
///     we offer a non-blocking bottom sheet with three options
///     (4-4-6 breathing / call someone / I'm OK, continue).
///   - `acute`: immediately push a full-screen crisis surface
///     ([EmergencySupportPage]) on the root navigator. Callers are
///     responsible for *not* persisting the offending turn — but
///     pushing safety information here is the priority.
///
/// Routing is fire-and-forget. Callers do not await anything except
/// when they explicitly want to suspend their flow (e.g. waiting for
/// the user to dismiss the acute crisis page before unblocking input).
class DistressRouter {
  DistressRouter({required this.state});

  final DistressState state;

  /// Update the global distress pill state and, when warranted,
  /// surface a corresponding UI affordance.
  ///
  /// [context] must be a widget mounted under the [SafetyOverlay] root
  /// (i.e. any module page). On `acute` we use [rootNavigator] so the
  /// crisis page sits above any in-flight dialogs or sheets.
  Future<void> route(
    DistressMatch match, {
    required BuildContext context,
  }) async {
    state.report(match);
    switch (match.level) {
      case DistressLevel.none:
      case DistressLevel.low:
        return;
      case DistressLevel.moderate:
        // Defer one frame so the caller's setState completes before
        // we add the bottom sheet to the route stack.
        await Future<void>.delayed(Duration.zero);
        if (!context.mounted) return;
        await DistressModerateSheet.show(context);
        return;
      case DistressLevel.acute:
        if (!context.mounted) return;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const EmergencySupportPage(),
            fullscreenDialog: true,
          ),
        );
        return;
    }
  }
}

/// Non-blocking moderate-distress bottom sheet. Offers three actions
/// in the order recommended by §Safety: settle (breathing), reach out,
/// or continue. Tapping outside dismisses (== "continue").
class DistressModerateSheet extends StatelessWidget {
  const DistressModerateSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const DistressModerateSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_border,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEn
                        ? 'Sounds like a heavy moment'
                        : '我聽到你而家可能唔多舒服',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'Want to do something to help yourself settle?'
                  : '要唔要做啲嘢，幫自己 settle 啲？',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _ActionButton(
              icon: Icons.air,
              label: isEn
                  ? 'Quiet a moment (4-4-6 breathing)'
                  : '靜一靜（4-4-6 呼吸）',
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalmPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.phone_in_talk_outlined,
              label: isEn ? 'Reach someone' : '搵人傾',
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmergencySupportPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isEn ? 'I\'m OK, keep going' : '我冇事，繼續',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
      style: FilledButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: theme.colorScheme.secondaryContainer,
      ),
    );
  }
}

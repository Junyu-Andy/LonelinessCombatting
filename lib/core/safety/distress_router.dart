import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';
import '../../features/wellbeing/presentation/pages/calm_page.dart';
import '../../features/analytics/presentation/analytics_scope.dart';
import '../session/chat_session_recorder.dart';
import 'distress_detector.dart';
import 'distress_state.dart';

/// Centralized routing for distress detections. Replaces per-module
/// ad-hoc safety sheets so the four-level response is identical
/// everywhere (P3.4).
///
/// Routing rules:
///   - `none` / `low`: update [DistressState] so the [SafetyOverlay]
///     pill repaints, but do not interrupt the user's flow.
///   - `moderateReview` (S-1, 2026-09): grief / past-hardship vocabulary
///     inside a life review.  Logged upstream; **nothing** is surfaced —
///     no sheet, no template, and the pill state is left untouched so a
///     bereaved participant is not nudged out of the memory.
///   - `moderateInterrupt`: pill repaints, and after the current turn
///     settles we offer a non-blocking bottom sheet with three options
///     (4-4-6 breathing / call someone / I'm OK, continue).  The caller
///     also shows the per-agent safety template (see SafetyAcknowledgements).
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
  /// [onModerateSheetShown] fires right before the moderate_interrupt
  /// bottom sheet is pushed so the calling page can log
  /// `moderate_sheet_shown` (L-1 events).
  ///
  /// 1020l §一 (2): [showModerateInline] — a page that shows the same
  /// moderate notice ([DistressModerateSheet] with `onClose`) at its top,
  /// under the app bar, instead of as a bottom sheet over its input bar
  /// (the 小欣 chat window, both arms alike).  When the page passes it, it
  /// is called where the sheet would be pushed, and its future (done when
  /// the notice is closed) is awaited as the sheet was.  Null: the bottom
  /// sheet, as before.  Levels, events, words and timing are the same
  /// either way; only the place (and, inline, tighter spacing) differs.
  Future<void> route(
    DistressMatch match, {
    required BuildContext context,
    void Function()? onModerateSheetShown,
    Future<void> Function()? showModerateInline,
  }) async {
    if (match.level == DistressLevel.moderateReview) {
      // S-1: review-only.  Not reported to the pill state either.
      return;
    }
    state.report(match);
    switch (match.level) {
      case DistressLevel.none:
      case DistressLevel.low:
      case DistressLevel.moderateReview:
        return;
      case DistressLevel.moderateInterrupt:
        onModerateSheetShown?.call();
        // Defer one frame so the caller's setState completes before
        // we add the bottom sheet to the route stack.
        await Future<void>.delayed(Duration.zero);
        if (!context.mounted) return;
        if (showModerateInline != null) {
          await showModerateInline();
          return;
        }
        await DistressModerateSheet.show(context);
        return;
      case DistressLevel.acute:
        if (!context.mounted) return;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const EmergencySupportPage(from: 'acute_route'),
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
  const DistressModerateSheet({super.key, this.onClose});

  /// 1020l §一 (2): shown inside a page (see `showModerateInline` on
  /// [DistressRouter.route]) — the three choices call this to close it
  /// instead of popping the sheet's route, and the spacing is tighter so
  /// the whole notice fits under the app bar on a phone at the largest
  /// text.  Same words, same three choices, same order.  Null: the bottom
  /// sheet, exactly as before.
  final VoidCallback? onClose;

  bool get _inline => onClose != null;

  void _close(BuildContext context) {
    final close = onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).pop();
    }
  }

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
    final inline = _inline;
    return SafeArea(
      child: Padding(
        padding: inline
            ? const EdgeInsets.fromLTRB(16, 12, 16, 4)
            : const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
            SizedBox(height: inline ? 6 : 10),
            Text(
              isEn
                  ? 'Want to do something to help yourself settle?'
                  : '要唔要做啲嘢，幫自己 settle 啲？',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: inline ? 12 : 20),
            _ActionButton(
              dense: inline,
              icon: Icons.air,
              label: isEn
                  ? 'Quiet a moment (4-4-6 breathing)'
                  : '靜一靜（4-4-6 呼吸）',
              onPressed: () {
                _close(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalmPage(),
                  ),
                );
              },
            ),
            SizedBox(height: inline ? 8 : 12),
            _ActionButton(
              dense: inline,
              icon: Icons.phone_in_talk_outlined,
              label: isEn ? 'Reach someone' : '搵人傾',
              onPressed: () {
                AnalyticsScope.of(context)
                    .logEvent(PhaseAEvents.moderateSheetOpenedResources);
                _close(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const EmergencySupportPage(from: 'moderate_sheet'),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _close(context),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: inline ? 4 : 10),
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

  /// 1020l: tighter inside a page (see [DistressModerateSheet.onClose]).
  final bool dense;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 8 : 14),
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

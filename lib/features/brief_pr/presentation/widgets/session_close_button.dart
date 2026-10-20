/// T25 (C16) — S9 close button at the top left of every chat page.
///
/// Label verbatim from docs/spec/copy/short-texts.md S9: 「今日傾到呢度」.
/// Tapping it ends the session (`endReason = close_button`) and pops the
/// page; the page's PopScope then runs its end-of-session flow, which
/// shows the rating card on the companion list page only when the session
/// was valid.  Both arms, same button.
///
/// The first time the button appears on a phone, a one-line explanation
/// is shown once as a snack bar.  The wording is not finalised, so it is a
/// `【占位】` draft.  T46: "already explained" is kept on the device
/// ([SessionCloseHint], `shared_preferences`), so the note shows once per
/// phone instead of once per App start; same in both arms.
///
/// 1020d 8 (3)(4) — switch `app_config/feature_flags.leaveButtonV2Enabled`
/// (default off): the label reads 「離開」 ([leaveLabel]; a page may pass
/// its own, the v2 reminiscence page 「離開（會暫存）」) and the first-use
/// note is [leaveFirstUseNote], shown once per phone under its own marker
/// so an elder who learnt the old button is told about the new one.  What
/// the button does, the session end and Brief PR do not change.  Off: the
/// old label and note.
library;

import 'package:flutter/material.dart';

import '../../../../core/feature_flags/remote_feature_flags.dart';
import 'session_close_hint.dart';

class SessionCloseButton extends StatefulWidget {
  const SessionCloseButton({super.key, required this.onPressed, this.text});

  final VoidCallback onPressed;

  /// A page's own label (leave switch on only); null = [currentLabel].
  final String? text;

  static const label = '今日傾到呢度';

  /// Final wording (10/15 item 6 B: two sentences, docs/spec/copy S10c);
  /// shown once per phone (T46).
  static const firstUseNote = '撳「今日傾到呢度」就係今次傾完。想再傾隨時返嚟。';

  /// 1020d 8 (3) — draft 【待 Junyu 确认】.
  static const leaveLabel = '離開';

  /// 1020d 8 (3) — draft 【待 Junyu 确认】.
  static const leaveFirstUseNote =
      '撳『離開』就係今次傾完。想再傾隨時返嚟，之前講過嘅都喺度。';

  static bool get leaveV2 => RemoteFeatureFlags.current.leaveButtonV2Enabled;

  /// The label shown now (switch-dependent).
  static String get currentLabel => leaveV2 ? leaveLabel : label;

  /// Width to give `AppBar.leadingWidth` so the label is not clipped.
  static const leadingWidth = 168.0;

  @override
  State<SessionCloseButton> createState() => _SessionCloseButtonState();
}

class _SessionCloseButtonState extends State<SessionCloseButton> {
  @override
  void initState() {
    super.initState();
    final v2 = SessionCloseButton.leaveV2;
    final show = v2
        ? SessionCloseHint.claimLeaveFirstUse()
        : SessionCloseHint.claimFirstUse();
    if (show) {
      final note = v2
          ? SessionCloseButton.leaveFirstUseNote
          : SessionCloseButton.firstUseNote;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(note, style: const TextStyle(fontSize: 17)),
          duration: const Duration(seconds: 6),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Center(
        child: TextButton.icon(
          key: const Key('session_close_button'),
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: theme.colorScheme.primary,
          ),
          icon: const Icon(Icons.check_circle_outline, size: 22),
          label: Text(
            SessionCloseButton.leaveV2
                ? (widget.text ?? SessionCloseButton.leaveLabel)
                : SessionCloseButton.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

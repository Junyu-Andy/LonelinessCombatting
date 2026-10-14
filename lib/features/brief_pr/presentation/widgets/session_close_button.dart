/// T25 (C16) — S9 close button at the top left of every chat page.
///
/// Label verbatim from docs/spec/copy/short-texts.md S9: 「今日傾到呢度」.
/// Tapping it ends the session (`endReason = close_button`) and pops the
/// page; the page's PopScope then runs its end-of-session flow, which
/// shows the rating card on the companion list page only when the session
/// was valid.  Both arms, same button.
///
/// The first time in a process the button appears, a one-line explanation
/// is shown once as a snack bar.  The wording is not finalised, so it is a
/// `【占位】` draft; persisting "already explained" across App starts is
/// listed in the T25 report (no local store is available in the App).
library;

import 'package:flutter/material.dart';

class SessionCloseButton extends StatefulWidget {
  const SessionCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const label = '今日傾到呢度';

  /// Draft (not finalised): shown once per process.
  static const firstUseNote = '【占位】撳「今日傾到呢度」就係今次傾完；想再傾隨時返嚟。';

  /// Width to give `AppBar.leadingWidth` so the label is not clipped.
  static const leadingWidth = 168.0;

  static bool _noteShown = false;

  @visibleForTesting
  static void resetForTest() => _noteShown = false;

  @override
  State<SessionCloseButton> createState() => _SessionCloseButtonState();
}

class _SessionCloseButtonState extends State<SessionCloseButton> {
  @override
  void initState() {
    super.initState();
    if (!SessionCloseButton._noteShown) {
      SessionCloseButton._noteShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text(SessionCloseButton.firstUseNote,
              style: TextStyle(fontSize: 17)),
          duration: Duration(seconds: 6),
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
          label: const Text(
            SessionCloseButton.label,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

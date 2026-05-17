import 'package:flutter/material.dart';

/// P4.4 — modal page scaffold for elder-friendly UX.
///
/// Every modal surface presented as a full-screen route must use this
/// wrapper so older participants always see:
///   - a leading "back" affordance (top-left), and
///   - a trailing "close" affordance (top-right).
///
/// Why both: research with the pilot cohort showed people forgot which
/// arrow returns them to the previous page versus the home tab. Having
/// "back" and "close" both available, both labeled with tooltips,
/// removes that branch in their head.
class AppModal extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  /// Where "close" should pop to. By default it pops the current route,
  /// matching "back". Set [closePopsToRoot] when you want the X to
  /// dismiss the whole modal stack (e.g. a multi-step flow whose
  /// inner pages were pushed on top).
  final bool closePopsToRoot;

  const AppModal({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.onClose,
    this.closePopsToRoot = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: isEn ? 'Back' : '返回',
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: isEn ? 'Close' : '關閉',
            onPressed: onClose ??
                () => Navigator.of(context).popUntil(
                      closePopsToRoot
                          ? (r) => r.isFirst
                          : (r) => r.isCurrent,
                    ),
          ),
        ],
      ),
      body: child,
    );
  }
}

/// 1020c item 二 (Junyu, 10/20): keyboard occlusion on small phones.
///
/// On a 360×640 phone at the App's largest font (1.30) the 72 px top bar
/// keeps its place when the keyboard (≈ 300 px) comes up, so only
/// 99–155 px of the conversation is left between the bar and the input
/// box, and a long message is cut.  Behind the remote switch
/// `app_config/feature_flags.keyboardCompactHeaderEnabled` (default off),
/// while the keyboard is open:
///
///   - [keyboardCompactAppBar]: the page's top bar becomes one line,
///     48 px high, with a smaller title.  The leading control — S9
///     「今日傾到呢度」 or the back arrow — is kept exactly as it is, so
///     ending the session or going back is still one tap.  The full bar
///     returns as soon as the keyboard closes.  `companionAppBar` (every
///     companion page, both arms) uses it.
///   - [KeyboardScrollToLatest]: a chat list (reversed, newest at the
///     bottom edge) goes back to the newest message when the keyboard
///     opens, so the last message sits right above the input box.
///
/// No crisis or support entry lives in these top bars (the safety sheet
/// and crisis page open from the detector, unchanged).  Both arms use the
/// same widgets, so both arms behave the same.  Switch off: no extra
/// MediaQuery dependency, the same AppBar as before, the list untouched.
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags/remote_feature_flags.dart';

class KeyboardCompact {
  KeyboardCompact._();

  /// Height of the one-line bar: the 48 px minimum touch target, so the
  /// S9 button (min 48 px) and the back arrow keep their full size.
  static const double toolbarHeight = 48;

  /// Title size in the one-line bar (the full bar uses 24).
  static const double titleFontSize = 18;

  /// The remote switch.
  static bool get enabled =>
      RemoteFeatureFlags.current.keyboardCompactHeaderEnabled;

  /// True while the switch is on and the soft keyboard covers the bottom
  /// of the screen (`MediaQuery.viewInsetsOf(context).bottom > 0`).
  ///
  /// Call it with the page's own build context, above its Scaffold: inside
  /// a Scaffold body the keyboard inset has already been taken out and
  /// reads 0.  With the switch off nothing is read, so the page does not
  /// rebuild on every keyboard frame.
  static bool active(BuildContext context) =>
      enabled && MediaQuery.viewInsetsOf(context).bottom > 0;
}

/// A page's top bar that turns into one line while the keyboard is open.
///
/// Keyboard closed or switch off: exactly
/// `AppBar(leading: leading, leadingWidth: leadingWidth, title: title)`.
/// Keyboard open: the same bar [KeyboardCompact.toolbarHeight] high, the
/// title ([compactTitle] if given, else [title]) on one line in a smaller
/// size, [leading] unchanged.
AppBar keyboardCompactAppBar(
  BuildContext context, {
  required Widget title,
  Widget? compactTitle,
  Widget? leading,
  double? leadingWidth,
}) {
  if (!KeyboardCompact.active(context)) {
    return AppBar(leading: leading, leadingWidth: leadingWidth, title: title);
  }
  final theme = Theme.of(context);
  final base = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
  return AppBar(
    toolbarHeight: KeyboardCompact.toolbarHeight,
    leading: leading,
    leadingWidth: leadingWidth,
    // AppBar already keeps the title on one line (no wrap, ellipsis).
    titleTextStyle:
        base?.copyWith(fontSize: KeyboardCompact.titleFontSize, height: 1.2),
    title: compactTitle ?? title,
  );
}

/// Wraps a chat page's message list: a `ListView(reverse: true)` (newest
/// message at the bottom edge) without a controller of its own.  When
/// [keyboardOpen] turns true, the list scrolls back to the newest message.
/// It does not move the list while the keyboard stays open, so the elder
/// can still scroll up to read.  Switch off: returns [child] untouched.
class KeyboardScrollToLatest extends StatefulWidget {
  const KeyboardScrollToLatest({
    super.key,
    required this.keyboardOpen,
    required this.child,
  });

  /// [KeyboardCompact.active], read with the page's context.
  final bool keyboardOpen;

  final Widget child;

  @override
  State<KeyboardScrollToLatest> createState() => _KeyboardScrollToLatestState();
}

class _KeyboardScrollToLatestState extends State<KeyboardScrollToLatest> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant KeyboardScrollToLatest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keyboardOpen && !oldWidget.keyboardOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
    }
  }

  void _toLatest() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    // Reversed list: the newest message is at the start (offset 0).
    if (position.pixels <= position.minScrollExtent) return;
    _controller.animateTo(
      position.minScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!KeyboardCompact.enabled) return widget.child;
    // The list has no controller, so it takes this one (every platform,
    // not only the mobile defaults); its own descendants do not.
    return PrimaryScrollController(
      controller: _controller,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}

/// 1020l §一 (2) — notes shown at the top of a page, under the app bar.
///
/// On the phones the snack bars and the bottom sheet of the 小欣 chat
/// window sat on top of the input bar and the newest message.  A page that
/// wants its notes at the top:
///   - wraps its Scaffold in a [TopNoticeHost], and
///   - puts a [TopNoticeArea] first in its body Column, right under the app
///     bar — part of the Column, so the message list gets shorter instead
///     of being covered.
/// Shared widgets that used to pop a snack bar ask [TopNotices.maybeOf]
/// first: the S9 first-use note ([SessionCloseButton]) and the voice notes
/// ([VoiceInputButton]).  On a page without a host nothing changes (the
/// snack bar as before).  Today only the 小欣 chat window (switch
/// `checkInChatV2Enabled`) has a host.
library;

import 'dart:async';

import 'package:flutter/material.dart';

class TopNoticeController extends ChangeNotifier {
  final Map<String, _TopNoticeEntry> _entries = {};
  bool _disposed = false;

  /// The notes now shown, oldest first.
  List<String> get ids => List.unmodifiable(_entries.keys);

  bool isShowing(String id) => _entries.containsKey(id);

  /// Show [builder] under [id] (the same id again replaces it, at the
  /// end).  [duration]: hidden by itself after that long; null = until
  /// [dismiss].
  void show(String id, WidgetBuilder builder, {Duration? duration}) {
    if (_disposed) return;
    _entries.remove(id)?.timer?.cancel();
    final entry = _TopNoticeEntry(builder);
    if (duration != null) entry.timer = Timer(duration, () => dismiss(id));
    _entries[id] = entry;
    notifyListeners();
  }

  /// A one-line (or a few lines) note; tapping it hides it.
  void showText(String id, String text, {Duration? duration}) => show(
        id,
        (_) => TopNoticeCard(text: text, onDismiss: () => dismiss(id)),
        duration: duration,
      );

  void dismiss(String id) {
    if (_disposed) return;
    final entry = _entries.remove(id);
    if (entry == null) return;
    entry.timer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final e in _entries.values) {
      e.timer?.cancel();
    }
    _entries.clear();
    super.dispose();
  }
}

class _TopNoticeEntry {
  _TopNoticeEntry(this.builder);
  final WidgetBuilder builder;
  Timer? timer;
}

/// Gives the subtree a [TopNoticeController].  Pass [controller] when the
/// page itself shows notes (it owns and disposes it then).
class TopNoticeHost extends StatefulWidget {
  const TopNoticeHost({super.key, this.controller, required this.child});

  final TopNoticeController? controller;
  final Widget child;

  @override
  State<TopNoticeHost> createState() => _TopNoticeHostState();
}

class _TopNoticeHostState extends State<TopNoticeHost> {
  TopNoticeController? _own;

  TopNoticeController get _controller =>
      widget.controller ?? (_own ??= TopNoticeController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TopNoticeScope(notifier: _controller, child: widget.child);
}

class _TopNoticeScope extends InheritedNotifier<TopNoticeController> {
  const _TopNoticeScope({required super.notifier, required super.child});
}

class TopNotices {
  TopNotices._();

  /// The page's top notes, or null when the page has none (then show the
  /// snack bar as before).  Does not subscribe [context] to changes.
  static TopNoticeController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TopNoticeScope>()?.notifier;
}

/// The notes, stacked under the app bar.  [leading]: page-owned lines shown
/// first (the 小欣 window's offline line).  At most [maxHeight] tall (and
/// never more than the parent allows); more scrolls inside the area, with
/// the scroll bar shown so it can be seen that there is more.
class TopNoticeArea extends StatefulWidget {
  const TopNoticeArea({
    super.key,
    this.leading = const [],
    this.maxHeight = double.infinity,
  });

  final List<Widget> leading;
  final double maxHeight;

  @override
  State<TopNoticeArea> createState() => _TopNoticeAreaState();
}

class _TopNoticeAreaState extends State<TopNoticeArea> {
  // Its own controller: the route's primary one belongs to the page's list.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        context.dependOnInheritedWidgetOfExactType<_TopNoticeScope>()?.notifier;
    final children = <Widget>[
      ...widget.leading,
      if (controller != null)
        for (final id in controller.ids)
          KeyedSubtree(
            key: ValueKey('top_notice_$id'),
            child: Builder(builder: controller._entries[id]!.builder),
          ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      key: const ValueKey('top_notice_area'),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A text note in the area: full width, the text and a close mark; a tap
/// anywhere on it hides it.  No new words — the text is the caller's.
class TopNoticeCard extends StatelessWidget {
  const TopNoticeCard({super.key, required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onDismiss,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 17, height: 1.4, color: fg),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.close_rounded, size: 22, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

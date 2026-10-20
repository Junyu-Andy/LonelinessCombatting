import 'package:flutter/widgets.dart';

import 'usage_event_recorder.dart';

/// Gives pages the App's [UsageEventRecorder] (1020c: the 小讀本 rows go
/// through the same recorder as foreground / background).  [MyApp] puts
/// it above the navigator; tests wrap a page in one with an in-memory
/// sink.  Without a scope, [maybeOf] is null and nothing is recorded.
class UsageEventsScope extends InheritedWidget {
  const UsageEventsScope({
    super.key,
    required this.recorder,
    required super.child,
  });

  final UsageEventRecorder recorder;

  static UsageEventRecorder? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<UsageEventsScope>()
      ?.recorder;

  @override
  bool updateShouldNotify(UsageEventsScope oldWidget) =>
      recorder != oldWidget.recorder;
}

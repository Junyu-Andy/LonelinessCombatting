import 'package:flutter/widgets.dart';

import 'llm/llm_gateway.dart';
import 'memory/memory_store.dart';
import 'safety/distress_detector.dart';
import 'safety/distress_state.dart';

/// Bundles the cross-cutting services every Arm A module needs (LLM,
/// memory, distress detection) plus the app-wide [DistressState] notifier
/// so the safety overlay can repaint when any module reports a flag.
class CoreServicesScope extends InheritedWidget {
  final LlmGateway llm;
  final MemoryStore memory;
  final DistressDetector distress;
  final DistressState distressState;

  const CoreServicesScope({
    super.key,
    required this.llm,
    required this.memory,
    required this.distress,
    required this.distressState,
    required super.child,
  });

  static CoreServicesScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<CoreServicesScope>();
    assert(s != null, 'CoreServicesScope missing above this widget');
    return s!;
  }

  @override
  bool updateShouldNotify(CoreServicesScope oldWidget) =>
      llm != oldWidget.llm ||
      memory != oldWidget.memory ||
      distress != oldWidget.distress ||
      distressState != oldWidget.distressState;
}

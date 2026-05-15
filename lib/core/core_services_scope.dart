import 'package:flutter/widgets.dart';

import 'llm/llm_gateway.dart';
import 'memory/memory_store.dart';
import 'safety/distress_detector.dart';

/// Bundles the three cross-cutting services every Arm A module needs
/// (LLM, memory, distress detection) and exposes them through one
/// InheritedWidget so modules don't each have to thread these via
/// constructors.
class CoreServicesScope extends InheritedWidget {
  final LlmGateway llm;
  final MemoryStore memory;
  final DistressDetector distress;

  const CoreServicesScope({
    super.key,
    required this.llm,
    required this.memory,
    required this.distress,
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
      distress != oldWidget.distress;
}

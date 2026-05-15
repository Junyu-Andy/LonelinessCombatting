import 'package:flutter/widgets.dart';

import 'llm/llm_gateway.dart';
import 'memory/cross_module_memory.dart';
import 'memory/memory_store.dart';
import 'safety/distress_detector.dart';
import 'safety/distress_state.dart';

/// Bundles the cross-cutting services every Arm A module needs (LLM,
/// memory, distress detection, cross-module memory) plus the app-wide
/// [DistressState] notifier so the safety overlay can repaint when any
/// module reports a flag.
class CoreServicesScope extends InheritedWidget {
  final LlmGateway llm;
  final MemoryStore memory;
  final DistressDetector distress;
  final DistressState distressState;
  final CrossModuleMemoryService crossModuleMemory;

  const CoreServicesScope({
    super.key,
    required this.llm,
    required this.memory,
    required this.distress,
    required this.distressState,
    required this.crossModuleMemory,
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
      distressState != oldWidget.distressState ||
      crossModuleMemory != oldWidget.crossModuleMemory;
}

import 'package:flutter/widgets.dart';

import 'agent_context/agent_context_service.dart';
import 'agent_context/shared_context_service.dart';
import 'agents/persona_resolver.dart';
import 'cross_referral/handoff_executor.dart';
import 'cross_referral/referral_routing_service.dart';
import 'llm/agent_greeting_service.dart';
import 'llm/llm_gateway.dart';
import 'memory/cross_module_memory.dart';
import 'memory/memory_store.dart';
import 'memory/memory_v1_service.dart';
import 'safety/distress_detector.dart';
import 'safety/distress_router.dart';
import 'safety/distress_state.dart';
import 'safety/safety_check.dart';

/// Bundles the cross-cutting services every Arm A module needs (LLM,
/// memory, distress detection, cross-module memory, per-agent context
/// store, and the persona resolver) plus the app-wide [DistressState]
/// notifier so the safety overlay can repaint when any module reports
/// a flag.
class CoreServicesScope extends InheritedWidget {
  final LlmGateway llm;
  final MemoryStore memory;
  final DistressDetector distress;
  final DistressState distressState;
  final DistressRouter distressRouter;
  final CrossModuleMemoryService crossModuleMemory;
  final AgentContextService agentContext;
  final SharedContextService sharedContext;
  final PersonaResolver personaResolver;
  final ReferralRoutingService referralRouting;
  final HandoffExecutor handoffExecutor;
  final AgentGreetingService agentGreeting;

  /// T7 — the shared safety-check entry point (both arms).  Defaults to a
  /// detect-only instance (no writes) when not supplied, e.g. in tests.
  final SafetyService safety;

  /// T49e-3 — memory v1 client (hands a finished chat session to the
  /// server).  Defaults to the real service; tests pass a fake.
  final MemoryV1Service memoryV1;

  const CoreServicesScope({
    super.key,
    required this.llm,
    required this.memory,
    required this.distress,
    required this.distressState,
    required this.distressRouter,
    required this.crossModuleMemory,
    required this.agentContext,
    required this.sharedContext,
    required this.personaResolver,
    required this.referralRouting,
    required this.handoffExecutor,
    required this.agentGreeting,
    SafetyService? safety,
    this.memoryV1 = const MemoryV1Service(),
    required super.child,
  }) : safety = safety ?? const SafetyService();

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
      distressRouter != oldWidget.distressRouter ||
      crossModuleMemory != oldWidget.crossModuleMemory ||
      agentContext != oldWidget.agentContext ||
      sharedContext != oldWidget.sharedContext ||
      personaResolver != oldWidget.personaResolver ||
      referralRouting != oldWidget.referralRouting ||
      handoffExecutor != oldWidget.handoffExecutor ||
      agentGreeting != oldWidget.agentGreeting ||
      safety != oldWidget.safety ||
      memoryV1 != oldWidget.memoryV1;
}

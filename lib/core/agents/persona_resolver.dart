/// Resolves the agent persona + context-suffix for a module's LLM call
/// (Developer Requirements §3.2, §4.4).
///
/// Modules ask the resolver "which agent owns me?" by passing the
/// agent id directly (M2 → Siu Yan, M3 → Ah Jan/Ah Bak, Tung Tung →
/// itself). The resolver then composes the context suffix from
/// per-agent rolling summary, top named entities, and (Siu Yan only)
/// the shared mood snippet, producing a single string the gateway
/// appends server-side after the persona prompt.
library;

import '../../features/auth/data/user_profile.dart';
import '../agent_context/agent_context_service.dart';
import '../agent_context/shared_context_service.dart';
import 'agent_registry.dart';

class PersonaContext {
  final AgentDefinition agent;
  final String promptKey;
  final String? variantName;
  final String? contextSuffix;

  const PersonaContext({
    required this.agent,
    required this.promptKey,
    this.variantName,
    this.contextSuffix,
  });
}

class PersonaResolver {
  PersonaResolver({
    required this.agentContext,
    required this.sharedContext,
  });

  final AgentContextService agentContext;
  final SharedContextService sharedContext;

  /// Build the persona payload for a module's next LLM call.
  ///
  /// Returns null if the agent id is unknown (defensive — callers
  /// should always pass a registered id).
  Future<PersonaContext?> resolve({
    required String agentId,
    required UserProfile? profile,
    bool includeSharedMood = false,
    int maxNamedEntities = 5,
  }) async {
    final agent = AgentRegistry.tryById(agentId);
    if (agent == null) return null;

    final variantName = _variantNameFor(agent, profile);

    if (profile == null) {
      return PersonaContext(
        agent: agent,
        promptKey: agent.systemPromptKey,
        variantName: variantName,
      );
    }

    final snapshot = await agentContext.read(
      uid: profile.uid,
      agentId: agentId,
    );

    final lines = <String>[];

    if (snapshot.rollingSummary.trim().isNotEmpty) {
      lines.add('[Rolling summary]');
      lines.add(snapshot.rollingSummary.trim());
      lines.add('');
    }

    if (snapshot.namedEntities.isNotEmpty) {
      final entries = snapshot.namedEntities.entries.toList()
        ..sort((a, b) => b.value.lastMentioned.compareTo(a.value.lastMentioned));
      final top = entries.take(maxNamedEntities);
      lines.add('[Named entities recently mentioned]');
      for (final e in top) {
        lines.add('- ${e.key} (${e.value.type}, x${e.value.mentions})');
      }
      lines.add('');
    }

    if (snapshot.themeThreads.isNotEmpty) {
      lines.add('[Theme threads]');
      snapshot.themeThreads.forEach((k, v) {
        lines.add('- $k: $v');
      });
      lines.add('');
    }

    if (includeSharedMood) {
      final shared = await sharedContext.read(profile.uid);
      if (shared.recentMood != null &&
          shared.recentMood!.summary.trim().isNotEmpty) {
        lines.add('[Recent mood snippet]');
        lines.add(shared.recentMood!.summary.trim());
        lines.add('');
      }
    }

    final suffix = lines.isEmpty ? null : lines.join('\n').trim();

    return PersonaContext(
      agent: agent,
      promptKey: agent.systemPromptKey,
      variantName: variantName,
      contextSuffix: suffix,
    );
  }

  String? _variantNameFor(AgentDefinition agent, UserProfile? profile) {
    if (!agent.hasGenderVariants) return null;
    final variant = profile?.ahJanAhBakVariant ?? AgentGenderVariant.feminine;
    return agent.resolveVariant(variant).displayNameZh;
  }
}

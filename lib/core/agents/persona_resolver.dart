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
import '../../features/onboarding/data/intake_repository.dart';
import '../agent_context/agent_context_service.dart';
import '../agent_context/intake_memory_seeder.dart';
import '../agent_context/shared_context_service.dart';
import 'agent_registry.dart';

class PersonaContext {
  final AgentDefinition agent;
  final String promptKey;
  final String? variantName;
  final String? contextSuffix;

  /// B.1 — structured snapshot of this agent's memory, passed to the CF so
  /// the mechanism-of-change flag detector can spot cross-session memory
  /// callbacks. Shape mirrors what `functions/llm_flags.js` reads:
  /// `{ rollingSummary: String, namedEntities: { name: {...} } }`.
  final Map<String, dynamic>? agentContextSnapshot;

  const PersonaContext({
    required this.agent,
    required this.promptKey,
    this.variantName,
    this.contextSuffix,
    this.agentContextSnapshot,
  });
}

class PersonaResolver {
  PersonaResolver({
    required this.agentContext,
    required this.sharedContext,
    this.intakeRepo,
  });

  final AgentContextService agentContext;
  final SharedContextService sharedContext;

  /// Optional — when provided, the very first conversation with each agent
  /// is seeded from the onboarding intake (Demo Sprint Plan §1D). Null in
  /// unit tests that don't exercise seeding.
  final IntakeRepository? intakeRepo;

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

    var summaryText = snapshot.rollingSummary.trim();

    // §1D — lazy intake seeding. The first time the summary is empty we seed
    // it from onboarding so the opening conversation already feels
    // personalised, then persist it so this only happens once.
    if (summaryText.isEmpty && intakeRepo != null) {
      final intake = await intakeRepo!.load(profile.uid);
      final seed = IntakeMemorySeeder.seedFor(
        agentId: agentId,
        intake: intake,
        interests: profile.interests,
      );
      if (seed != null && seed.trim().isNotEmpty) {
        summaryText = seed.trim();
        await agentContext.writeRollingSummary(
          uid: profile.uid,
          agentId: agentId,
          summary: summaryText,
        );
      }
    }

    final lines = <String>[];

    // Appendix A anti-fabrication guardrail — ALWAYS injected so the agent
    // never pretends to remember when there is nothing real to recall.
    lines.add('[過往摘要]');
    lines.add(summaryText.isEmpty
        ? '（暫時未有，今次係第一次同佢傾偈）'
        : summaryText);
    lines.add('[注意] 只可以引用上面真實寫咗嘅嘢；上面空嘅就當第一次傾，'
        '唔好扮記得任何嘢。');
    lines.add('');

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

    // Structured snapshot for the CF flag detector (memory_callback).
    final snapshotMap = <String, dynamic>{
      'rollingSummary': summaryText,
      if (snapshot.namedEntities.isNotEmpty)
        'namedEntities': {
          for (final e in snapshot.namedEntities.entries)
            e.key: e.value.toMap(),
        },
    };

    return PersonaContext(
      agent: agent,
      promptKey: agent.systemPromptKey,
      variantName: variantName,
      contextSuffix: suffix,
      agentContextSnapshot: snapshotMap,
    );
  }

  String? _variantNameFor(AgentDefinition agent, UserProfile? profile) {
    if (!agent.hasGenderVariants) return null;
    final variant = profile?.ahJanAhBakVariant ?? AgentGenderVariant.feminine;
    return agent.resolveVariant(variant).displayNameZh;
  }
}

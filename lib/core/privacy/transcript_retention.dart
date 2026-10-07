/// C20 / decision 0020 — the participant's 「保留對話紀錄」 switch in
/// Settings.  One switch covers all three companions: it sets the legacy
/// global flag AND every per-agent entry, because chat pages read
/// [ConsentFlags.transcriptRetentionFor] (per-agent first) and onboarding
/// writes a per-agent `true` for each companion — flipping only the
/// global flag would change nothing.
library;

import '../../features/auth/data/user_profile.dart';
import '../agents/agent_registry.dart';

class TranscriptRetention {
  const TranscriptRetention._();

  static const List<String> agentIds = [
    AgentRegistry.siuYanId,
    AgentRegistry.ahJanAhBakId,
    AgentRegistry.tungTungId,
  ];

  /// On only when the global flag and every companion retain.
  static bool isOn(UserProfile? profile) =>
      profile != null &&
      profile.consent.transcriptRetention &&
      agentIds.every(profile.consent.transcriptRetentionFor);

  /// [consent] with retention set to [on] globally and for every agent.
  static ConsentFlags set(ConsentFlags consent, bool on) => consent.copyWith(
        transcriptRetention: on,
        transcriptRetentionByAgent: {for (final id in agentIds) id: on},
      );
}

/// Lets `app_config/usage_copy` replace the profile lines that say how
/// often the companion is used (T20).  Without a signed-off value the
/// intro from [profileIntros] is returned unchanged.  The profile copy
/// is zh only, so only the `_zh` fields are read.
library;

import '../../../core/agents/agent_registry.dart';
import '../../../core/config/usage_copy.dart';
import 'agent_profile_content.dart';

/// Today's lines that the config may replace.
const String siuYanMoodCapabilityLine = '同你做每日嘅心情記錄';
const String ahJanAhBakWeeklyCapabilityLine = '同你做每星期嘅人生點滴分享（每星期一個主題）';

ProfileIntroContent withUsageCopy(String agentId, ProfileIntroContent intro) {
  final copy = UsageCopy.current;
  String zh(String key, String fallback) =>
      copy.text(key, isEn: false, fallback: fallback);
  List<String> swap(String line, String key) => [
        for (final c in intro.capabilities) c == line ? zh(key, c) : c,
      ];

  switch (agentId) {
    case AgentRegistry.siuYanId:
      return ProfileIntroContent(
        opening: zh(UsageCopy.siuYanProfileOpening, intro.opening),
        capabilitiesHeading: intro.capabilitiesHeading,
        capabilities: swap(
            siuYanMoodCapabilityLine, UsageCopy.siuYanProfileMoodCapability),
        limitationsHeading: intro.limitationsHeading,
        limitations: intro.limitations,
        closing: intro.closing,
      );
    case AgentRegistry.ahJanAhBakId:
      return ProfileIntroContent(
        opening: intro.opening,
        capabilitiesHeading: intro.capabilitiesHeading,
        capabilities: swap(ahJanAhBakWeeklyCapabilityLine,
            UsageCopy.ahJanAhBakProfileWeeklyCapability),
        limitationsHeading: intro.limitationsHeading,
        limitations: intro.limitations,
        closing: intro.closing,
      );
    default:
      return intro;
  }
}

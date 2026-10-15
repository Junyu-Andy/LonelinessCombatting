/// 10/15 pilot: the top bar of the companion pages was different on every
/// page (plain name, avatar + name, week theme, page title; the S9 close
/// button on some pages and a back arrow on others; a second end-session
/// button top-right on one page).  One widget for all of them:
///
///   top-left   S9 「今日傾到呢度」 (Brief PR v2 on) or the back arrow,
///              the same on both arms;
///   title      the companion's avatar + name (阿珍／阿伯 by the elder's
///              pairing), avatar opens the profile;
///   top-right  nothing.
///
/// Both arms must look the same (blinding), so the Arm B pages use it too.
library;

import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';
import '../../features/brief_pr/data/brief_pr_v2.dart';
import '../../features/brief_pr/presentation/widgets/session_close_button.dart';
import 'agent_avatar.dart';
import 'agent_registry.dart';

/// Avatar + name, for `AppBar.title`.
class CompanionTitle extends StatelessWidget {
  final String agentId;
  const CompanionTitle({super.key, required this.agentId});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final agent = AgentRegistry.byId(agentId);
    final pairing = agentId == AgentRegistry.ahJanAhBakId
        ? AppSettingsScope.read(context).profile?.ahJanAhBakVariant
        : null;
    final variant = agent.resolveVariant(pairing);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AgentAvatar(
          agent: agent,
          selectedVariant: pairing,
          size: 32,
          openProfileOnTap: true,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            isEn ? variant.displayNameEn : variant.displayNameZh,
            key: const Key('companion_title'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The AppBar every companion chat / form page uses.  [onClose] runs when
/// S9 is tapped (v2 on); pages that only need to leave pass a `maybePop`.
AppBar companionAppBar(BuildContext context,
    {required String agentId, required VoidCallback onClose}) {
  final v2 = BriefPrV2.enabled;
  return AppBar(
    leading: v2 ? SessionCloseButton(onPressed: onClose) : null,
    leadingWidth: v2 ? SessionCloseButton.leadingWidth : null,
    title: CompanionTitle(agentId: agentId),
  );
}

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
///
/// 1020c item 二 (switch `keyboardCompactHeaderEnabled`, default off):
/// while the keyboard is open the bar is one line (48 px, avatar 24 +
/// name), S9 / back kept as is (`keyboard_compact.dart`).
library;

import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';
import '../../features/brief_pr/data/brief_pr_v2.dart';
import '../../features/brief_pr/presentation/widgets/session_close_button.dart';
import '../../shared/widgets/keyboard_compact.dart';
import 'agent_avatar.dart';
import 'agent_registry.dart';

/// Avatar + name, for `AppBar.title`.  [compact]: the one-line bar shown
/// while the keyboard is open (smaller avatar; the name takes the bar's
/// smaller title style).
class CompanionTitle extends StatelessWidget {
  final String agentId;
  final bool compact;
  const CompanionTitle({super.key, required this.agentId, this.compact = false});

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
          size: compact ? 24 : 32,
          openProfileOnTap: true,
        ),
        SizedBox(width: compact ? 8 : 10),
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

/// Width the S9 button needs so 「今日傾到呢度」 is never cut: measured
/// with the page's real text scale (the fixed 168 clipped it at the larger
/// font sizes).  The title (avatar + name) is short, so the bar has room.
double sessionCloseLeadingWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: SessionCloseButton.label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // left padding 4 + button padding 8 + icon 22 + gap 8 + text + padding 8
  final needed = 4 + 8 + 22 + 8 + painter.width + 8 + 4;
  painter.dispose();
  return needed < SessionCloseButton.leadingWidth
      ? SessionCloseButton.leadingWidth
      : needed.ceilToDouble();
}

/// The AppBar every companion chat / form page uses.  [onClose] runs when
/// S9 is tapped (v2 on); pages that only need to leave pass a `maybePop`.
/// Keyboard open + switch on: the one-line bar ([keyboardCompactAppBar]).
AppBar companionAppBar(BuildContext context,
    {required String agentId, required VoidCallback onClose}) {
  final v2 = BriefPrV2.enabled;
  return keyboardCompactAppBar(
    context,
    leading: v2 ? SessionCloseButton(onPressed: onClose) : null,
    leadingWidth: v2 ? sessionCloseLeadingWidth(context) : null,
    title: CompanionTitle(agentId: agentId),
    compactTitle: CompanionTitle(agentId: agentId, compact: true),
  );
}

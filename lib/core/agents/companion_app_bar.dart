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
///
/// 1020d 8 (2)–(4) (switch `leaveButtonV2Enabled`, default off): S9 reads
/// 「離開」; a page may pass [leaveLabel] (the v2 reminiscence page:
/// 「離開（會暫存）」, shown there even while Brief PR v2 is off, because
/// on that page it is the way out that keeps the week).
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
double sessionCloseLeadingWidth(BuildContext context, {String? label}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label ?? SessionCloseButton.currentLabel,
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
    {required String agentId,
    required VoidCallback onClose,
    String? leaveLabel}) {
  final leaveV2 = SessionCloseButton.leaveV2;
  final pageLabel = leaveV2 ? leaveLabel : null;
  final show = BriefPrV2.enabled || pageLabel != null;
  return keyboardCompactAppBar(
    context,
    leading:
        show ? SessionCloseButton(onPressed: onClose, text: pageLabel) : null,
    leadingWidth:
        show ? sessionCloseLeadingWidth(context, label: pageLabel) : null,
    title: CompanionTitle(agentId: agentId),
    compactTitle: CompanionTitle(agentId: agentId, compact: true),
  );
}

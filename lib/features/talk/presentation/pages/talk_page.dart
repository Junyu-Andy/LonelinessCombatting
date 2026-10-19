/// 搵人傾 (Talk-with-someone) — second tab per Product Overview §3.2.
///
/// Three agent rooms: Siu Yan / Ah Jan-Ah Bak / Tung Tung.  Each tile
/// routes into the agent's primary surface via [AgentTileRow]:
///   - Siu Yan → M2 daily check-in
///   - Ah Jan / Ah Bak → reminiscence landing (M3 curriculum + reflective)
///   - Tung Tung → curious chat / article Q&A
///
/// The tab is intentionally minimal — three large, equally-weighted
/// tiles + a short header.  No nudges, no banners.  The IA pattern is:
/// 睇今日 is the snapshot; 搵人傾 is the door to people.
///
/// 1020 D (`homeLayoutV2Enabled`, both arms): page 2 is, in order, the
/// header line, the Brief PR card, the continue card and the first-week
/// nudge (both moved here from page 1), and the three companions.  Off:
/// as before.
library;

import 'package:flutter/material.dart';

import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/session/session_entry_surface.dart';
import '../../../brief_pr/presentation/widgets/brief_pr_card_host.dart';
import '../../../today/presentation/home_v2_scope.dart';
import '../../../today/presentation/widgets/agent_tile_row.dart';
import '../../../today/presentation/widgets/continue_chat_card.dart';
import '../../../today/presentation/widgets/week1_nudge_banner.dart';

class TalkPage extends StatelessWidget {
  const TalkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final v2 = RemoteFeatureFlags.current.homeLayoutV2Enabled;
    final page = SafeArea(
      child: ListView(
        key: v2 ? const ValueKey('talk_v2') : null,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              isEn
                  ? "Choose someone you'd like to talk with right now."
                  : '揀一個你想搵嘅人傾下。',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          // T25 — Brief PR invitation card (S10a / S10b); empty unless the
          // scheduler has one to show.  Never covers the tiles.
          const BriefPrCardHost(),
          if (v2) ...const [
            ContinueChatCard(),
            Week1NudgeBanner(),
          ],
          const AgentTileRow(),
        ],
      ),
    );
    // 1020e 一.(9): sessions opened from here record entrySurface `page2`.
    return v2
        ? HomeSurfaceScope(surface: SessionEntrySurface.page2, child: page)
        : page;
  }
}

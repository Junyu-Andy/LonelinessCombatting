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
library;

import 'package:flutter/material.dart';

import '../../../today/presentation/widgets/agent_tile_row.dart';

class TalkPage extends StatelessWidget {
  const TalkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
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
          const AgentTileRow(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import 'cog_restructure_arm_a_page.dart';
import 'cog_restructure_arm_b_page.dart';

/// M4 entry surface — "檢視一個諗法".
///
/// Spec §M4 trigger (b): on-demand entry. The two trigger paths (a: LLM
/// detects a negative cognition in any free-text; c: detected via daily
/// check-in) are routed to the same flow but with the thought pre-filled.
/// For the basic build we expose only the user-initiated path.
class CogRestructureLandingPage extends StatelessWidget {
  /// Optional thought seed used when invoked from another module's
  /// detection callback. Null on the home-tile path.
  final String? seedThought;
  const CogRestructureLandingPage({super.key, this.seedThought});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Examine a worry' : '檢視一個諗法')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 28, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            isEn
                                ? 'A thought is not a fact'
                                : '諗法只係一個諗法',
                            style: theme.textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isEn
                            ? 'Sometimes a worry feels true the moment we '
                                'think it. Let\'s look at it together — '
                                'gently — and see what holds up.'
                            : '有時一個擔心，諗起嗰下覺得真。'
                                '我哋慢慢一齊睇下，邊啲係事實，邊啲係諗法。',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.arrow_forward_rounded, size: 24),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    isEn ? 'Start' : '開始',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final builder = Arm.isA(context)
        ? (BuildContext _) => CogRestructureArmAPage(seedThought: seedThought)
        : (BuildContext _) => const CogRestructureArmBPage();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }
}

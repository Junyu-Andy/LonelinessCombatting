import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../analytics/presentation/analytics_scope.dart';
import '../pages/emergency_support_page.dart';

/// Two-layer crisis footer (2026-07 redesign, per team feedback):
///
///   1. PRIMARY — talk first: 情緒通 18111 one-tap dial. Leading with a
///      talking line lowers the bar versus confronting users with 999.
///   2. DANGER — visually separated, red, secondary position: 999 for
///      immediate life-threatening danger.
///   3. TERTIARY — "更多支援熱線 ▸" opens the full hotline list.
class SafetyFooterCard extends StatelessWidget {
  final String analyticsTag;
  const SafetyFooterCard({super.key, required this.analyticsTag});

  Future<void> _dial(String number) async {
    try {
      await launchUrl(Uri.parse('tel:$number'));
    } catch (_) {
      // Unsupported platform (web/desktop) — the full list page still
      // shows the numbers to copy.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Layer 1: talk-first primary action --------------------
          InkWell(
            onTap: () {
              AnalyticsScope.of(context)
                  .logEmergencyOpened(from: '$analyticsTag-18111');
              _dial('18111');
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.support_agent_rounded,
                      size: 30, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEn
                              ? 'Want to talk to someone? "Mind Space" 18111'
                              : '想搵人傾吓？　「情緒通」18111',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEn
                              ? '24-hour · Cantonese · government hotline · '
                                  'a real person listens'
                              : '24 小時・廣東話・政府熱線・有真人聽你講',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.phone_rounded,
                      size: 24, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // ---- Layer 2: danger (visually separate, red, secondary) ---
          InkWell(
            onTap: () {
              AnalyticsScope.of(context)
                  .logEmergencyOpened(from: '$analyticsTag-999');
              _dial('999');
            },
            child: Container(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Row(
                children: [
                  Icon(Icons.emergency_outlined,
                      size: 22, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEn
                          ? 'Immediate danger to you or someone else — '
                              'call 999'
                          : '如果你或身邊嘅人有即時生命危險　撥 999',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // ---- Layer 3: full list ------------------------------------
          InkWell(
            onTap: () {
              AnalyticsScope.of(context).logEmergencyOpened(from: analyticsTag);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EmergencySupportPage(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEn ? 'More support hotlines' : '更多支援熱線',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 24, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

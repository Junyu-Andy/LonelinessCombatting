import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../analytics/presentation/analytics_scope.dart';
import '../pages/emergency_support_page.dart';

/// Crisis footer on 睇今日 — a shortcut into the same 危機支援 page that
/// 自己 → 危機支援 opens.  Both arms identical.
///
/// 10/19 redesign (Junyu): two parts instead of three.
///
///   1. Talk first: 「想搵人傾吓？」 centred; 「情緒通」 and 18111 on their own
///      lines; the headset and phone icons together in one round button so
///      it is obvious where to press; 「24×7 政府熱線」 centred under
///      them.  The whole block
///      dials 18111.
///   2. 「如果唔安全，睇更多支援熱線」 opens [EmergencySupportPage], whose
///      list leads with 999 / A&E.  The separate red 「撥 999」 row is gone
///      from this card (decision draft 0048-home-safety-card-simplified);
///      the acute flow that opens the support page by itself is unchanged.
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
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Part 1: talk first ------------------------------------
          InkWell(
            key: const Key('safety_footer_call_18111'),
            onTap: () {
              AnalyticsScope.of(context)
                  .logEmergencyOpened(from: '$analyticsTag-18111');
              _dial('18111');
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                children: [
                  Text(
                    isEn ? 'Want to talk to someone?' : '想搵人傾吓？',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Headset + phone together in one round button.
                      Semantics(
                        button: true,
                        label: isEn ? 'Call 18111' : '打 18111',
                        excludeSemantics: true,
                        child: Container(
                          key: const Key('safety_footer_call_button'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: ShapeDecoration(
                            color: cs.primary,
                            shape: const StadiumBorder(),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.support_agent_rounded,
                                  size: 30, color: cs.onPrimary),
                              const SizedBox(width: 8),
                              Icon(Icons.phone_rounded,
                                  size: 28, color: cs.onPrimary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEn ? '"Mind Space"' : '「情緒通」',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            Text(
                              '18111',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Own full-width line: beside the button it broke as
                  // 「政府熱 / 線」 from 特大 up (10/19 sweep).
                  const SizedBox(height: 10),
                  Text(
                    isEn ? '24/7 government hotline' : '24×7 政府熱線',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          // ---- Part 2: not safe → the full list (999 first) ----------
          InkWell(
            key: const Key('safety_footer_more'),
            onTap: () {
              AnalyticsScope.of(context).logEmergencyOpened(from: analyticsTag);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const EmergencySupportPage(from: 'today_footer'),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    // Two fixed lines: one line broke as 「…熱 / 線」 at
                    // most sizes.
                    child: Text(
                      isEn
                          ? 'If you are not safe,\nsee more support hotlines'
                          : '如果唔安全，\n睇更多支援熱線',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 28, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

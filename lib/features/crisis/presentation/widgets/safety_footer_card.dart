import 'package:flutter/material.dart';

import '../../../analytics/presentation/analytics_scope.dart';
import '../pages/emergency_support_page.dart';

class SafetyFooterCard extends StatelessWidget {
  final String analyticsTag;
  const SafetyFooterCard({super.key, required this.analyticsTag});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AnalyticsScope.of(context).logEmergencyOpened(from: analyticsTag);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const EmergencySupportPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn ? "Can't cope? → Call 999" : '撐唔住？　→　撥 999',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn ? 'View all support hotlines' : '睇所有支援熱線',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

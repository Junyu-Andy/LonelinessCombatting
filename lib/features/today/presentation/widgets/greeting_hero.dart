import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../l10n/app_localizations.dart';

/// Top-of-Today greeting band. Time-of-day icon + greeting + a short
/// "{appTitle} 陪你" line. HKU chip is intentionally absent (P0.5
/// stripped it from Home and the new Today surface inherits that).
class GreetingHero extends StatelessWidget {
  const GreetingHero({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final now = DateTime.now();
    final profile = AppSettingsScope.of(context).profile;
    final displayName = profile?.displayName.trim();

    final hour = now.hour;
    final String greetingBase;
    final IconData icon;
    if (hour >= 5 && hour < 11) {
      greetingBase = l10n.greetingMorning;
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 11 && hour < 14) {
      greetingBase = l10n.greetingNoon;
      icon = Icons.light_mode_outlined;
    } else if (hour >= 14 && hour < 18) {
      greetingBase = l10n.greetingAfternoon;
      icon = Icons.wb_cloudy_outlined;
    } else if (hour >= 18 && hour < 22) {
      greetingBase = l10n.greetingEvening;
      icon = Icons.nights_stay_outlined;
    } else {
      greetingBase = l10n.greetingNight;
      icon = Icons.bedtime_outlined;
    }

    final greeting = displayName != null && displayName.isNotEmpty
        ? (isEn ? '$greetingBase, $displayName' : '$greetingBase，$displayName')
        : greetingBase;

    final weekdayNames = isEn
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLine = isEn
        ? '${weekdayNames[now.weekday - 1]}, ${now.month}/${now.day}'
        : '${now.month} 月 ${now.day} 日　${weekdayNames[now.weekday - 1]}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      decoration: BoxDecoration(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(36)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            Color.alphaBlend(
              theme.colorScheme.tertiary.withValues(alpha: 0.6),
              theme.colorScheme.primary.withValues(alpha: 0.78),
            ),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 108,
            height: 108,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 56, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  greeting,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEn
                      ? '${l10n.appTitle} is with you.'
                      : '${l10n.appTitle} 陪你。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

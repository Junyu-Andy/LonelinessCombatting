import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../adherence/presentation/widgets/missed_checkin_banner.dart';
import '../widgets/quick_cta_row.dart';

/// Phase 0 Home shell. Holds only the greeting hero, the missed-check-in
/// banner slot and the QuickCtaRow slot. The status cards, daily feed and
/// All-features grid have all been removed; Phase 1 will repurpose this
/// surface as the Today tab.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _GreetingHero(now: now, appTitle: l10n.appTitle),
          const MissedCheckInBanner(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: QuickCtaRow(),
          ),
        ],
      ),
    );
  }
}

class _GreetingHero extends StatelessWidget {
  final DateTime now;
  final String appTitle;

  const _GreetingHero({required this.now, required this.appTitle});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final hour = now.hour;
    final String greeting;
    final IconData icon;
    if (hour >= 5 && hour < 11) {
      greeting = isEn ? 'Good morning!' : '早晨！';
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 11 && hour < 14) {
      greeting = isEn ? 'Good noon!' : '午安！';
      icon = Icons.light_mode_outlined;
    } else if (hour >= 14 && hour < 18) {
      greeting = isEn ? 'Good afternoon' : '下午好';
      icon = Icons.wb_cloudy_outlined;
    } else if (hour >= 18 && hour < 22) {
      greeting = isEn ? 'Good evening' : '夜晚好';
      icon = Icons.nights_stay_outlined;
    } else {
      greeting = isEn ? 'It\'s late — take it easy' : '夜深喇，慢慢嚟';
      icon = Icons.bedtime_outlined;
    }

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
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
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
                      ? '$appTitle is with you.'
                      : '$appTitle 陪你。',
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

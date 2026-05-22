/// B.10 — visual indicator on the Today tab when 今日休息 is active.
///
/// Renders nothing if the flag is unset or stale (different local day).
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';

class QuietTodayBanner extends StatelessWidget {
  const QuietTodayBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    if (profile == null || !profile.isQuietToday) {
      return const SizedBox.shrink();
    }
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.bedtime_outlined,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isEn
                    ? 'Resting today. Reminders are paused — '
                        'come back when you want to.'
                    : '今日休息。提醒已經暫停 — 你想返嚟嗰時再返嚟。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

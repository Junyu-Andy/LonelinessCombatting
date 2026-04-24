import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Row(
            children: [
              Icon(
                Icons.settings,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.settingsTab,
                style: theme.textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.settingsSubtitle,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

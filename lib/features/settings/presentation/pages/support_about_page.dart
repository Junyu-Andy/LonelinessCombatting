import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import 'faq_page.dart';
import 'privacy_policy_page.dart';

/// 關於同支援 — sub-page holding the app info card, FAQ and privacy policy.
/// Nested here (2026-07 IA cleanup) so the 自己 tab stops scrolling forever.
class SupportAboutPage extends StatelessWidget {
  /// Displayed version string, passed from the settings page.
  final String version;
  const SupportAboutPage({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'About & Support' : '關於同支援'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite,
                            size: 26, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(l10n.appTitle,
                            style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isEn ? 'Version $version' : '版本 $version',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '由香港大學數據及系統工程學系開發',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FaqPage()),
                ),
                icon: const Icon(Icons.help_outline_rounded, size: 26),
                label: Text(isEn ? 'FAQ' : '常見問題'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyPage()),
                ),
                icon: const Icon(Icons.policy_outlined, size: 26),
                label: Text(isEn ? 'Privacy Policy' : '私隱政策'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

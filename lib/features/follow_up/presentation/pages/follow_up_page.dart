import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/figure_placeholder.dart';
import '../widgets/follow_up_section.dart';

/// Standalone Follow-up surface. Kept around because `home_page.dart` still
/// links to it from the quick-actions grid; the same content is also
/// embedded into the personalisation page (lib/features/personalization/).
class FollowUpPage extends StatelessWidget {
  const FollowUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.followUpTab)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(l10n.followUpSubtitle, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 14),
            const FigurePlaceholder(
              description: '插畫：日曆上幾朵小花，象徵每星期慢慢培養嘅小習慣。',
              height: 110,
              icon: Icons.calendar_today_outlined,
            ),
            const SizedBox(height: 18),
            const FollowUpSection(),
          ],
        ),
      ),
    );
  }
}

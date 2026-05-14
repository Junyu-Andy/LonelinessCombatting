import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../data/adherence_check.dart';

/// Spec §Adherence support: "Two missed check-ins trigger a soft re-
/// engagement message (identical in both arms)."
///
/// Renders nothing if the user has checked in within the last 2 days,
/// has never checked in (first-week courtesy), or is in guest mode.
class MissedCheckInBanner extends StatefulWidget {
  const MissedCheckInBanner({super.key});

  @override
  State<MissedCheckInBanner> createState() => _MissedCheckInBannerState();
}

class _MissedCheckInBannerState extends State<MissedCheckInBanner> {
  int? _daysSince;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) return;
    final check = AdherenceCheck(available: auth.available);
    final days = await check.daysSinceLastCheckIn(profile.uid);
    if (!mounted) return;
    setState(() => _daysSince = days);
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysSince;
    if (days == null || days < 2) return const SizedBox.shrink();

    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.waving_hand_outlined,
                  size: 28,
                  color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn
                          ? "Haven't seen you in a few days"
                          : '幾日冇見你',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'A quick check-in only takes a minute. No pressure.'
                          : '快速 check-in 一分鐘就完。冇壓力。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CheckInPage(),
                  ),
                ),
                child: Text(isEn ? 'Open' : '打開'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

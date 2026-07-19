import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../adherence/data/adherence_check.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../context/presentation/pages/check_in_page.dart';

/// B05 — always-visible check-in status line on the Today page.
///
/// Before this widget existed the only surfaces were the missed-check-in
/// banner (which appears after 3 quiet days) and the weekly recap count,
/// so a participant had no way to confirm "did today's check-in go
/// through?".  This renders one of two states:
///   - done:     "✓ 今日已做咗 check-in" (confirmation, not tappable)
///   - not done: "今日仲未做 check-in" + tap to open the check-in page
///
/// Hidden in guest mode / while loading so it never causes layout pop.
class CheckInStatusChip extends StatefulWidget {
  const CheckInStatusChip({super.key});

  @override
  State<CheckInStatusChip> createState() => _CheckInStatusChipState();
}

class _CheckInStatusChipState extends State<CheckInStatusChip> {
  bool? _doneToday;
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
    bool? done;
    try {
      done = await AdherenceCheck(available: auth.available)
          .hasCheckedInToday(profile.uid);
    } catch (_) {
      done = null; // Read error — stay hidden rather than mislead.
    }
    if (!mounted) return;
    setState(() => _doneToday = done);
  }

  Future<void> _openCheckIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CheckInPage()),
    );
    // Re-check on return so a just-completed check-in flips the chip
    // without needing a pull-to-refresh.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final done = _doneToday;
    if (done == null) return const SizedBox.shrink();

    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    if (done) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              isEn ? "Today's check-in is done" : '今日已做咗 check-in',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: InkWell(
        onTap: _openCheckIn,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.radio_button_unchecked,
                  size: 20, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEn
                      ? "Today's check-in — not done yet"
                      : '今日仲未做 check-in',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 22, color: theme.colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

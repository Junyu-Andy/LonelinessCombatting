/// 1020o 第三节 (decision 0066) — 自己 → 我的設定 → 「安靜時段」.
///
/// One line and two choices, 「由」 and 「到」; no on/off switch.  Each choice
/// opens a sheet with only the allowed half-hour times (QuietHoursRange).
/// A pick is saved at once, like the other settings: the profile in memory
/// (so the page shows it), `users/{uid}.quietHoursStart` / `quietHoursEnd`
/// ("HH:mm", QuietHoursStore) and one `quiet_hours_changed` usage event
/// (old value, new value; process data).  Both arms identical.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/notifications/quiet_hours_range.dart';
import '../../../../core/usage/usage_events_scope.dart';
import '../../data/quiet_hours_store.dart';

class QuietHoursCard extends StatelessWidget {
  const QuietHoursCard({
    super.key,
    this.store = const FirestoreQuietHoursStore(),
  });

  /// Where a pick is written (tests: [InMemoryQuietHoursStore]).
  final QuietHoursStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppSettingsScope.of(context);
    final isEn = settings.locale.languageCode == 'en';
    final profile = settings.profile;
    final start = QuietHoursRange.effectiveStart(profile?.quietHoursStart);
    final end = QuietHoursRange.effectiveEnd(profile?.quietHoursEnd);
    return Card(
      key: const Key('quiet_hours_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEn
                  ? 'The App won\'t show notifications during this time.'
                  // 10/21 (Junyu): 「彈通知」, final.
                  : '呢段時間 App 唔會彈通知。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _TimeRow(
              key: const Key('quiet_hours_start'),
              label: isEn ? 'From' : '由',
              value: start,
              onTap: () => _pick(context, QuietHoursField.start, start),
            ),
            const SizedBox(height: 12),
            _TimeRow(
              key: const Key('quiet_hours_end'),
              label: isEn ? 'To' : '到',
              value: end,
              onTap: () => _pick(context, QuietHoursField.end, end),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    QuietHoursField field,
    String current,
  ) async {
    final settings = AppSettingsScope.read(context);
    final isEn = settings.locale.languageCode == 'en';
    final usage = UsageEventsScope.maybeOf(context);
    final title = isEn
        ? 'Quiet hours: ${field == QuietHoursField.start ? 'from' : 'to'}'
        : '安靜時段：${field == QuietHoursField.start ? '由' : '到'}';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => QuietHoursPickerSheet(
        title: title,
        options: field == QuietHoursField.start
            ? QuietHoursRange.startOptions
            : QuietHoursRange.endOptions,
        selected: current,
      ),
    );
    if (picked == null || picked == current) return;
    final profile = settings.profile;
    if (profile == null) return;
    settings.profile = field == QuietHoursField.start
        ? profile.copyWith(quietHoursStart: picked)
        : profile.copyWith(quietHoursEnd: picked);
    usage?.recordQuietHoursChanged(
        field: field.code, from: current, to: picked);
    try {
      await store.save(profile.uid, field, picked);
    } catch (_) {
      // Offline: the SDK keeps the write and sends it later; the page
      // already shows the pick.
    }
  }
}

/// 「由」 / 「到」 and the time, the whole row one big button.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline, width: 1.5),
            ),
            child: Row(
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more_rounded, size: 30, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet: the allowed times, two per row (the hour and the half
/// hour), the current one filled.  A tap closes it with that time.
class QuietHoursPickerSheet extends StatelessWidget {
  const QuietHoursPickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <List<String>>[
      for (var i = 0; i < options.length; i += 2)
        options.sublist(i, i + 2 > options.length ? options.length : i + 2),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('quiet_hours_sheet'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            for (final row in rows) ...[
              Row(
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: i < row.length
                          ? _OptionButton(
                              value: row[i],
                              selected: row[i] == selected,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.value, required this.selected});

  final String value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: selected ? cs.onPrimary : cs.onSurface,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: value,
      excludeSemantics: true,
      child: Material(
        color: selected ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('quiet_hours_option_$value'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).pop(value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? cs.primary : cs.outline,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // Scaled down rather than cut off on the narrowest phone at the
            // largest text.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 26, color: cs.onPrimary),
                    const SizedBox(width: 6),
                  ],
                  Text(value, style: style),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

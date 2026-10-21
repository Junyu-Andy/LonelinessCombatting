/// 10/19 — tester only (測試員工具 → 每週問卷測試): the weekly questionnaire
/// (T24) on demand, without waiting for the study day.
///
/// For every bundle W1…W7 of the standard schedule:
///  1. 「直接打開（預覽，唔儲存）」 opens the real flow at once — the same
///     pages in the same order a participant gets, nothing saved, so it can
///     be repeated as often as needed ([WeeklyBundleFlowPage.previewFor]).
///  2. 「模擬到嗰日 10:30」 (the push hour + 30 min) moves the in-app
///     scheduling clock ([AppClock]) to half an hour after that bundle's
///     push and returns to 屋企, where the
///     「每週問卷」 card shows exactly as on that day.  Answers given there
///     ARE saved, to this tester account (testers are excluded from the
///     research data).  This needs the schedule to apply to the account:
///     a study period and a W0 date — 「切換組別」 adds both the first time.
///     Restarting the app returns to real time.
///
/// Only the App's own scheduling decisions read the simulated clock; the
/// server's pushes, Firestore timestamps and study-day stamps stay real.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/config/phase_b_config.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/scheduling/study_week.dart';
import '../../../../core/scheduling/w0_date.dart';
import '../../../../core/scheduling/weekly_schedule.dart';
import '../../../../core/time/app_clock.dart';
import '../../../weekly_bundle/data/weekly_bundle.dart';
import '../../../weekly_bundle/presentation/weekly_bundle_flow_page.dart';

class TesterWeeklyBundlePage extends StatefulWidget {
  const TesterWeeklyBundlePage({super.key});

  @override
  State<TesterWeeklyBundlePage> createState() => _TesterWeeklyBundlePageState();
}

class _TesterWeeklyBundlePageState extends State<TesterWeeklyBundlePage> {
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmt(DateTime t) =>
      '${t.month}月${t.day}日 ${_two(t.hour)}:${_two(t.minute)}';

  void _preview(WeeklyBundle bundle) {
    Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => WeeklyBundleFlowPage.previewFor(bundle),
    ));
  }

  /// Half an hour after the push (T24: the window opens at the push;
  /// 1020e v2: the window opens at 00:00, the push is at 10:00).
  void _simulate(WeeklyWindow window, int pushHour) {
    final o = window.open;
    AppClock.instance.simulate(DateTime(o.year, o.month, o.day, pushHour, 30));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// The push hour of [b]: 10:00 with weeklyReminderV2Enabled (W1–W7 since
  /// item 98; functions/weekly_schedule.js V2_PUSH_HOUR), else
  /// weeklyPushHour.
  static int _pushHourOf(WeeklyBundle b, PhaseBConfig cfg) =>
      WeeklySchedule.v2Default && WeeklySchedule.isV2Bundle(b)
          ? WeeklySchedule.v2PushHour
          : cfg.weeklyPushHour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final cfg = PhaseBConfig.current;
    final w0 = w0DateFor(profile);
    final bundles = WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.standard);
    final scheduled = WeeklyBundleGate.active(profile);

    // Why 「模擬到嗰日」 cannot work for this account, or null when it can.
    final String? simulateBlocked = !FeatureFlags.phaseB
        ? '呢個唔係 Phase B 包，每週問卷唔會喺主頁出現。'
        : !cfg.weeklyScheduleV2Enabled
            ? '伺服器開關 app_config/phase_b.weeklyScheduleV2Enabled 未開。'
            : (!scheduled || w0 == null)
                ? '呢個帳號未有研究期／W0 日期。喺測試員工具用「切換組別」切一次，'
                    '會自動補上（W0 = 切換當日），之後再嚟。'
                : null;

    return Scaffold(
      appBar: AppBar(title: const Text('每週問卷測試')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              w0 == null
                  ? 'W0 日期：未有'
                  : 'W0 日期：${w0.year}-${_two(w0.month)}-${_two(w0.day)}'
                      '（今日真實係第 ${studyDayOf(w0, DateTime.now())} 天）',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '「直接打開」唔會儲存任何嘢，可以重複做。'
              '「模擬到嗰日」之後喺主頁做嘅會儲存落呢個測試員帳號。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (simulateBlocked != null) ...[
              const SizedBox(height: 8),
              Text(
                simulateBlocked,
                key: const Key('tester_weekly_simulate_blocked'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (AppClock.instance.isSimulated) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  AppClock.instance.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.restore),
                label: Text('返回真實時間（而家模擬緊 ${_fmt(AppClock.now())}）'),
              ),
            ],
            const SizedBox(height: 12),
            for (final b in bundles)
              _BundleCard(
                bundle: b,
                window: w0 == null
                    ? null
                    : WeeklySchedule.windowFor(b, w0, cfg,
                        week4RecordedOn: w4RecordedOnFor(profile)),
                pushHour: _pushHourOf(b, cfg),
                onPreview: () => _preview(b),
                onSimulate: simulateBlocked != null || w0 == null
                    ? null
                    : () => _simulate(
                        WeeklySchedule.windowFor(b, w0, cfg,
                            week4RecordedOn: w4RecordedOnFor(profile)),
                        _pushHourOf(b, cfg)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.window,
    required this.pushHour,
    required this.onPreview,
    required this.onSimulate,
  });

  final WeeklyBundle bundle;
  final WeeklyWindow? window;
  final int pushHour;
  final VoidCallback onPreview;
  final VoidCallback? onSimulate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = window;
    final when = w == null
        ? 'W0 後第 ${bundle.pushDay} 天 $pushHour:00 開'
        : '第 ${bundle.pushDay} 天 · ${w.open.month}月${w.open.day}日 '
            '$pushHour:00 開';
    return Card(
      key: Key('tester_weekly_${bundle.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${bundle.id} · $when', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              bundle.parts.map(weeklyPartTitle).join(' → '),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: Key('tester_weekly_preview_${bundle.id}'),
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('直接打開（預覽，唔儲存）'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('tester_weekly_simulate_${bundle.id}'),
              onPressed: onSimulate,
              icon: const Icon(Icons.schedule),
              label: Text('模擬到嗰日 $pushHour:30，返主頁睇'),
            ),
          ],
        ),
      ),
    );
  }
}

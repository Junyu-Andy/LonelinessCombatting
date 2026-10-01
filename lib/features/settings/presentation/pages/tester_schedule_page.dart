/// Tester-only: schedule simulator + test pushes (2026-09-23).
///
/// 1. Pick an enrolment day (1–35) and a time of day → see exactly which
///    pushes the Cloud Functions would send and which surveys the home page
///    would offer ([ScheduleSimulator]).
/// 2. 「模擬到呢個時間」 moves the in-app scheduling clock ([AppClock]) there
///    and returns to 屋企, so the real banners / mood prompt / nudge appear
///    as a participant would see them.  Answers are written to THIS tester
///    account.  Restarting the app returns to real time.
/// 3. Test pushes: ask the `sendTestPush` Cloud Function to send one of the
///    real doorbells to this account's devices after a short delay.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/config/phase_a_config.dart';
import '../../../../core/scheduling/enrolment_day.dart';
import '../../../../core/scheduling/schedule_simulator.dart';
import '../../../../core/time/app_clock.dart';

class TesterSchedulePage extends StatefulWidget {
  const TesterSchedulePage({super.key});

  @override
  State<TesterSchedulePage> createState() => _TesterSchedulePageState();
}

class _TesterSchedulePageState extends State<TesterSchedulePage> {
  int _day = 1;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 30);
  bool _sending = false;
  bool _initialised = false;

  static const _quickTimes = [
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 10, minute: 30),
    TimeOfDay(hour: 19, minute: 30),
    TimeOfDay(hour: 20, minute: 30),
    TimeOfDay(hour: 23, minute: 0),
  ];

  DateTime? get _enrolledAt => AppSettingsScope.read(context).profile?.createdAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final e = _enrolledAt;
    if (e != null) _day = enrolmentDay(e, AppClock.now()).clamp(1, 35);
  }

  DateTime _targetDate(DateTime enrolled) {
    final d = dateOfEnrolmentDay(enrolled, _day);
    return DateTime(d.year, d.month, d.day, _time.hour, _time.minute);
  }

  String _fmtDate(DateTime d) =>
      '${d.month}月${d.day}日 ${ScheduleSimulator.weekdayZh(d)}';
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _simulate(DateTime target) async {
    AppClock.instance.simulate(target);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _sendTestPush(String kind) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('15 秒後發送。請即刻返回手機主畫面（安卓喺 app 前台時唔會顯示通知）。'),
      duration: Duration(seconds: 6),
    ));
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('sendTestPush',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 70)))
          .call({'kind': kind, 'delaySeconds': 15});
      final data = Map<String, dynamic>.from(res.data as Map);
      messenger.showSnackBar(SnackBar(
        content: Text('已發送：${data['delivered']}/${data['tokens']} 部機'
            '${(data['tokens'] ?? 0) == 0 ? '（呢個帳號冇登記推送 token：請確認已允許通知並重開 app）' : ''}'),
        duration: const Duration(seconds: 6),
      ));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.code == 'permission-denied'
            ? '要先喺測試員工具開啟「測試員帳號」先可以發測試推送。'
            : '發送失敗：${e.code} ${e.message ?? ''}'),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('發送失敗：$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enrolled = _enrolledAt;
    final cfg = PhaseAConfig.current;
    if (enrolled == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('日程模擬')),
        body: const Center(child: Text('要登入先可以用（需要入組日期）。')),
      );
    }
    final target = _targetDate(enrolled);
    final items = ScheduleSimulator.forDate(enrolledAt: enrolled, date: target, config: cfg);
    final realDay = enrolmentDay(enrolled, DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('日程模擬／測試推送')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text('入組日期：${enrolled.year}-${enrolled.month}-${enrolled.day}'
                '（今日真實係第 $realDay 天）',
                style: theme.textTheme.bodyLarge),
            if (AppClock.instance.isSimulated) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  AppClock.instance.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.restore),
                label: const Text('返回真實時間'),
              ),
            ],
            const SizedBox(height: 16),
            Text('第 $_day 天 · ${_fmtDate(target)} · ${_fmtTime(_time)}',
                style: theme.textTheme.titleLarge),
            Slider(
              value: _day.toDouble(),
              min: 1,
              max: 35,
              divisions: 34,
              label: '第 $_day 天',
              onChanged: (v) => setState(() => _day = v.round()),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _quickTimes)
                  ChoiceChip(
                    label: Text(_fmtTime(t)),
                    selected: t == _time,
                    onSelected: (_) => setState(() => _time = t),
                  ),
                ActionChip(
                  label: const Text('其他時間…'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('呢日會發生咩', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final it in items) _ItemTile(item: it),
            if (items.isEmpty) const Text('入組前，冇任何嘢。'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _simulate(target),
              icon: const Icon(Icons.fast_forward_rounded),
              label: Text('模擬到第 $_day 天 ${_fmtTime(_time)}，返回屋企睇'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
            const SizedBox(height: 6),
            Text(
              '只改 app 內「幾時出咩問卷」嘅判斷（週評窗口、第 2／4 週、首週提示、每日心情）。'
              'Firestore 時間戳同雲端推送照用真實時間；重開 app 自動返回真實時間。'
              '喺模擬期間答嘅問卷會寫入呢個測試帳號。',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 36),
            Text('測試推送（發去呢個帳號嘅機）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '需要「測試員帳號」已開啟，同埋手機已允許通知。iOS 未配置 APNs，暫時收唔到。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final (kind, label) in const [
              ('daily_mood_reminder', '每日心情提醒（19:00 嗰條）'),
              ('weekly_survey_reminder', '每週問卷提醒（星期日 20:00 嗰條）'),
              ('w2_push', '第 2 週問卷推送（10:00 嗰條）'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: _sending ? null : () => _sendTestPush(kind),
                  child: Align(alignment: Alignment.centerLeft, child: Text(label)),
                ),
              ),
            const Divider(height: 36),
            Text('第 1–35 天一覽', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var d = 1; d <= 35; d++) _OverviewRow(enrolled: enrolled, day: d, cfg: cfg,
                selected: d == _day, onTap: () => setState(() => _day = d)),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ScheduleItem item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.channel) {
      ScheduleChannel.push => (Icons.notifications_active_outlined, Colors.deepOrange),
      ScheduleChannel.inApp => (Icons.assignment_outlined, Colors.teal),
      ScheduleChannel.record => (Icons.edit_note_outlined, Colors.grey),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text('${item.at ?? '開 app 時'}　${item.titleZh}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(item.detailZh + (item.conditional ? '（視乎之前有冇做過）' : '')),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final DateTime enrolled;
  final int day;
  final PhaseAConfig cfg;
  final bool selected;
  final VoidCallback onTap;
  const _OverviewRow({
    required this.enrolled,
    required this.day,
    required this.cfg,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = dateOfEnrolmentDay(enrolled, day);
    final items = ScheduleSimulator.forDate(enrolledAt: enrolled, date: date, config: cfg)
        .where((i) => i.titleZh != '每日心情一問' && i.titleZh != '每日心情提醒')
        .map((i) => i.titleZh)
        .toList();
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text('第 $day 天\n${date.month}/${date.day} ${ScheduleSimulator.weekdayZh(date)}',
                  style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Text(items.isEmpty ? '（只有每日心情）' : items.join('；'),
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

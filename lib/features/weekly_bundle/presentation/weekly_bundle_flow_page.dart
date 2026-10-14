/// T24 (SPEC:C15) — the weekly questionnaire bundle as one flow.
///
/// One entry for everything due in a study week, parts in the fixed order
/// DJG-ES (djgWeeks only) → Weekly PR → PGIC → social-contact probe (only
/// when its switch is on); weeks 5–7 are PGIC only.  Modelled on T17b's
/// day-7 flow but independent of the ADA code:
///
///   intro (how many parts) → part 1 → part 2 → … → done
///
/// Each part saves on its own (its own document, id = bundle).  Opening
/// the flow again jumps to the first part not yet finished, and a part
/// reopens on the screen where it stopped (DJG, probe).  Every part shows
/// 「第 N 部分，共 M 部分」 at the top.  Both arms get exactly this page; no
/// arm check.  Screen text other than the instruments is a 【占位】 draft.
///
/// T35 (the W8 bundle) reuses this page with its own [WeeklyBundle].
library;

import 'package:flutter/material.dart';

import '../../../core/scheduling/weekly_schedule.dart';
import '../../assessment/data/djg_w2.dart';
import '../../assessment/presentation/pages/djg_w2_page.dart';
import '../../assessment/presentation/pages/pgic_page.dart';
import '../../weekly_pr/data/weekly_pr_trigger.dart';
import '../../weekly_pr/presentation/pages/weekly_pr_page.dart';
import '../data/weekly_bundle.dart';
import 'social_contact_probe_page.dart';

/// Draft (【占位】) names of the parts, for the intro list.
String weeklyPartTitle(WeeklyPart p) => switch (p) {
      WeeklyPart.djg => '【占位】最近嘅感受（6 條）',
      WeeklyPart.weeklyPr => '【占位】每週夥伴評估',
      WeeklyPart.pgic => '【占位】每週感受變化',
      WeeklyPart.socialContact => '【占位】過去 7 日嘅社交接觸',
    };

const kWeeklyBundleTitle = '【占位】每週問卷';

class WeeklyBundleFlowPage extends StatefulWidget {
  const WeeklyBundleFlowPage({
    super.key,
    required this.bundle,
    required this.store,
    required this.djgStoreFor,
    required this.socialStoreFor,
    required this.referentFor,
    required this.noReferent,
    this.initialStatus,
  });

  final WeeklyBundle bundle;
  final WeeklyBundleStore store;

  /// Stores of the per-screen parts, keyed by bundle id.
  final DjgW2Store Function(String bundleId) djgStoreFor;
  final SocialContactStore Function(String bundleId) socialStoreFor;

  /// The companion the Weekly PR is anchored to (null = no session in the
  /// range → `no_referent` record, part done).
  final Future<WeeklyPrAgentUsage?> Function(WeeklyBundle bundle) referentFor;
  final Future<void> Function(WeeklyBundle bundle) noReferent;

  /// Statuses already loaded by the home card (saves one round trip).
  final Map<WeeklyPart, String?>? initialStatus;

  /// Production wiring for a signed-in participant.
  static WeeklyBundleFlowPage forUser({
    Key? key,
    required String uid,
    required String arm,
    required WeeklyBundle bundle,
    required (DateTime, DateTime) referentRange,
    Map<WeeklyPart, String?>? initialStatus,
  }) {
    final trigger = WeeklyPrTrigger();
    return WeeklyBundleFlowPage(
      key: key,
      bundle: bundle,
      store: FirestoreWeeklyBundleStore(uid),
      djgStoreFor: (id) => FirestoreDjgW2Store(uid, timepoint: id),
      socialStoreFor: (id) => FirestoreSocialContactStore(uid, id),
      referentFor: (b) =>
          trigger.referentUsageForRange(uid, referentRange.$1, referentRange.$2),
      noReferent: (b) => trigger.writeNoReferent(uid, arm, bundle: b.id),
      initialStatus: initialStatus,
    );
  }

  @override
  State<WeeklyBundleFlowPage> createState() => _WeeklyBundleFlowPageState();
}

class _WeeklyBundleFlowPageState extends State<WeeklyBundleFlowPage> {
  final Map<WeeklyPart, String?> _status = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initialStatus;
    if (init != null) {
      _status.addAll(init);
      _loading = false;
    }
    _reload();
  }

  Future<void> _reload() async {
    try {
      final s = await widget.store.partStatus(widget.bundle);
      // Keep a local "done" the store has not caught up with yet (offline
      // queue): a part marked final here stays final.
      for (final p in widget.bundle.parts) {
        final local = _status[p];
        if (local != null && local != WeeklyPartStatus.inProgress) continue;
        _status[p] = s[p];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _isFinal(WeeklyPart p) =>
      _status[p] != null && _status[p] != WeeklyPartStatus.inProgress;

  int? get _nextIndex {
    for (var i = 0; i < widget.bundle.parts.length; i++) {
      if (!_isFinal(widget.bundle.parts[i])) return i;
    }
    return null;
  }

  bool get _started => _status.values.any((s) => s != null);

  Future<bool?> _runPart(WeeklyPart part, (int, int) pos) async {
    final b = widget.bundle;
    switch (part) {
      case WeeklyPart.djg:
        return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
          builder: (_) => DjgW2Page(
            store: widget.djgStoreFor(b.id),
            part: pos,
            title: kWeeklyBundleTitle,
          ),
        ));
      case WeeklyPart.weeklyPr:
        final agent = await widget.referentFor(b);
        if (!mounted) return null;
        if (agent == null) {
          await widget.noReferent(b);
          return true;
        }
        return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
          builder: (_) => WeeklyPrPage(agent: agent, bundle: b.id, part: pos),
        ));
      case WeeklyPart.pgic:
        return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
          builder: (_) => PgicPage(bundle: b.id, part: pos),
        ));
      case WeeklyPart.socialContact:
        return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
          builder: (_) => SocialContactProbePage(
            store: widget.socialStoreFor(b.id),
            part: pos,
            title: kWeeklyBundleTitle,
          ),
        ));
    }
  }

  Future<void> _run() async {
    var i = _nextIndex;
    while (i != null) {
      if (!mounted) return;
      final part = widget.bundle.parts[i];
      final done = await _runPart(part, (i + 1, widget.bundle.parts.length));
      if (!mounted) return;
      if (done == true) {
        _status[part] = WeeklyPartStatus.submitted;
      } else if (_status[part] == null) {
        _status[part] = WeeklyPartStatus.inProgress;
      }
      setState(() {});
      await _reload();
      // Back out of a part (not finished) = stop here; resume later.
      if (done != true) return;
      i = _nextIndex;
    }
  }

  String _statusLabel(WeeklyPart p) {
    final s = _status[p];
    if (s == null) return '【占位】未開始';
    if (s == WeeklyPartStatus.inProgress) return '【占位】做咗一半';
    if (s == WeeklyPartStatus.missed) return '【占位】已截止';
    return '【占位】已完成';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = widget.bundle.parts;
    final next = _nextIndex;
    return Scaffold(
      appBar: AppBar(title: const Text(kWeeklyBundleTitle)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          next == null
                              ? '【占位】全部做完喇，多謝你！'
                              : '【占位】一共有 ${parts.length} 部分。'
                                  '可以隨時停，下次會由停低嗰度繼續。',
                          key: const ValueKey('weekly_intro'),
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              height: 1.5,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 18),
                        for (var i = 0; i < parts.length; i++)
                          Card(
                            child: ListTile(
                              key: ValueKey('weekly_part_$i'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Icon(
                                _isFinal(parts[i])
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: theme.colorScheme.primary,
                                size: 30,
                              ),
                              title: Text(
                                '第 ${i + 1} 部分：${weeklyPartTitle(parts[i])}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(_statusLabel(parts[i]),
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: next == null
                          ? FilledButton(
                              key: const ValueKey('weekly_done'),
                              onPressed: () =>
                                  Navigator.of(context).maybePop(true),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('完成', style: TextStyle(fontSize: 18)),
                              ),
                            )
                          : FilledButton(
                              key: const ValueKey('weekly_start'),
                              onPressed: _run,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(_started ? '繼續' : '開始',
                                    style: const TextStyle(fontSize: 18)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

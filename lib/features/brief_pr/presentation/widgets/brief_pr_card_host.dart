/// T25 — puts the Brief PR invitation card (S10a / S10b) on the companion
/// list page when the scheduler has one to show, and nothing otherwise.
///
/// Reloads when the scheduler writes ([BriefPrV2.changes]) and when the
/// App comes back to the foreground, so a catch-up card appears on the
/// next open without any navigation.  Renders nothing while the v2 switch
/// is off or in guest mode.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../data/brief_pr_record.dart';
import '../../data/brief_pr_scheduler.dart';
import '../../data/brief_pr_v2.dart';
import '../pages/brief_pr_flow_page.dart';
import 'brief_pr_invite_card.dart';

class BriefPrCardHost extends StatefulWidget {
  const BriefPrCardHost({super.key, this.scheduler, this.uid, this.clock});

  /// Test seams; the App resolves both from scope / [BriefPrV2].
  final BriefPrScheduler? scheduler;
  final String? uid;
  final DateTime Function()? clock;

  @override
  State<BriefPrCardHost> createState() => _BriefPrCardHostState();
}

class _BriefPrCardHostState extends State<BriefPrCardHost>
    with WidgetsBindingObserver {
  BriefPrRecord? _card;
  String? _channel;
  String? _uid;
  bool _loading = false;

  BriefPrScheduler? get _scheduler {
    if (widget.scheduler != null) return widget.scheduler;
    if (!BriefPrV2.enabled) return null;
    return BriefPrV2.scheduler();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BriefPrV2.changes.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = widget.uid ?? AppSettingsScope.of(context).profile?.uid;
    if (uid != _uid) {
      _uid = uid;
      _reload();
    }
  }

  @override
  void dispose() {
    BriefPrV2.changes.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final uid = _uid;
    final s = _scheduler;
    if (uid == null || s == null) {
      if (_card != null && mounted) setState(() => _card = null);
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      var next = await s.nextCard(uid);
      String? channel;
      if (next != null) {
        channel = s.channelFor(next);
        next = await s.markShown(next);
      }
      if (!mounted) return;
      setState(() {
        _card = next;
        _channel = channel;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _accept() async {
    final card = _card;
    final s = _scheduler;
    if (card == null || s == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BriefPrFlowPage(record: card, scheduler: s),
    ));
    await _reload();
  }

  Future<void> _skip() async {
    final card = _card;
    final s = _scheduler;
    if (card == null || s == null) return;
    setState(() => _card = null);
    await s.skip(card);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (card == null) return const SizedBox.shrink();
    return BriefPrInviteCard(
      record: card,
      channel: _channel ?? BriefPrInviteChannel.listPage,
      now: (widget.clock ?? DateTime.now)(),
      onAccept: _accept,
      onSkip: _skip,
    );
  }
}

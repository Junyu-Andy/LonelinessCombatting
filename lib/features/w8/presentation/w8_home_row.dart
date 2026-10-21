/// T35 — the W8 card on the home page (handover 1021-W8 一 (5), 二).
///
/// 「最後一份問卷」 on page 1 (in 「今日要做嘅事」, after the weekly
/// questionnaire row; on the old one-page layout under the questionnaire
/// banner) from study day 56 to the end of day 70, until the five parts
/// are done (a started AIMHS keeps it so it can be finished or declined).
/// Tapping opens [W8FlowPage].  Nothing shows before day 56 or from day
/// 71 ([W8Schedule]), outside a Phase B build, or for an account that is
/// not registered ([W8Gate]).  The App's own clock decides ([AppClock]:
/// testers' 日程模擬 moves it); the server's stamps stay real.  Both arms
/// identical; no switch.  The title and, since 10/21 (decisions-log item
/// 131 (1)), the second line 「一共 5 部分，可以分開做。」.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/feature_flags/feature_flags.dart';
import '../../../core/scheduling/w0_date.dart';
import '../../../core/time/app_clock.dart';
import '../../analytics/presentation/analytics_scope.dart';
import '../../auth/presentation/auth_service_scope.dart';
import '../../today/presentation/home_v2_scope.dart';
import '../../today/presentation/widgets/today_todo_rows.dart';
import '../data/w8_items.dart';
import '../data/w8_schedule.dart';
import '../data/w8_store.dart';
import 'w8_flow_page.dart';

class W8TodoRow extends StatefulWidget {
  const W8TodoRow({super.key, this.storeFor, this.clock, this.phaseB});

  /// Tests and screenshots: the store (default [FirestoreW8Store]).
  final W8Store Function(String uid)? storeFor;

  /// Tests: the clock (default the scope's, else [AppClock]).
  final DateTime Function()? clock;

  /// Tests: the build (default [FeatureFlags.phaseB]).
  final bool? phaseB;

  @override
  State<W8TodoRow> createState() => _W8TodoRowState();
}

class _W8TodoRowState extends State<W8TodoRow> with WidgetsBindingObserver {
  bool _visible = false;
  Map<W8Part, String?> _status = const {};
  W8Store? _store;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeV2Refresh.changes.addListener(_load);
    AppClock.instance.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeV2Refresh.changes.removeListener(_load);
    AppClock.instance.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  DateTime _now() =>
      widget.clock?.call() ??
      HomeV2Scope.maybeOf(context)?.clock?.call() ??
      AppClock.now();

  W8Store? _storeFor(String uid) {
    final custom = widget.storeFor;
    if (custom != null) return custom(uid);
    if (!AuthServiceScope.of(context).available) return null;
    try {
      return FirestoreW8Store(uid);
    } catch (_) {
      return null; // Firebase not set up (guest mode): no card.
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final profile = AppSettingsScope.read(context).profile;
    final w0 = w0DateFor(profile);
    final on = W8Gate.activeFor(profile,
            phaseB: widget.phaseB ?? FeatureFlags.phaseB) &&
        w0 != null &&
        W8Schedule.cardShows(w0, _now());
    final store = on ? _storeFor(profile!.uid) : null;
    if (store == null) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    Map<W8Part, String?> status;
    try {
      status = await store.statuses();
    } catch (_) {
      status = const {};
    }
    if (!mounted) return;
    setState(() {
      _store = store;
      _status = status;
      _visible = status.isNotEmpty && !w8CardDone(status);
    });
  }

  Future<void> _open() async {
    final store = _store;
    if (store == null) return;
    unawaited(AnalyticsScope.maybeOf(context)
        ?.logEvent('w8_opened', {'bundle': W8Items.bundleId}));
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => W8FlowPage(store: store, initialStatus: _status),
    ));
    await _load();
    HomeV2Refresh.bump();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return TodoRowTile(
      key: const ValueKey('today_todo_w8'),
      leading: Icons.assignment_outlined,
      title: W8Texts.title,
      subtitle: W8Texts.homeSubtitle,
      onTap: _open,
    );
  }
}

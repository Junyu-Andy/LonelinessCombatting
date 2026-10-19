/// 1020 E — the mood row on page 1 (`app_config/feature_flags.moodRowV2Enabled`).
///
/// No pop-ups (E (1)): no daily mood sheet, no snackbar, no dialog — every
/// line sits in the row.  States for the day (E (2), 1020b 5.1):
///   - not answered:          M1, the five faces, M2 遲啲先答;
///   - skipped (M2 pressed):  M4 — tap it to open the faces; the row no
///                            longer opens by itself that day;
///   - answered:              M5 (face, word, time) and M6 而家有冇變？ (opens
///                            the faces again); M3 記低咗 briefly after a pick;
///   - answered again, same:  M5 with the new time;
///   - answered again, different: M5 and M8 (replaces M7).
/// M7 (E (4)): after the first answer of the day, until tapped or today's
/// check-in is done.  M8: after a later answer that differs from the one
/// before; gone once tapped and on the next App open (the App going to the
/// background counts).  M7 and M8 open 小欣's chat with an opener
/// ([MoodChatEntry]; needs `checkInChatV2Enabled`, the chat window's
/// switch — without it neither line shows).  Same in both arms.
///
/// Records (E (3)): every pick is one `daily_mood` row (first of the day
/// `is_primary`, the rest `supplementary`, server time) through
/// [MoodRowStore]; a skip logs `mood_checkin` with `skipped: true`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/shared_context_service.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../adherence/data/adherence_check.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/brief_pr_v2.dart';
import '../../data/mood_recorder.dart';
import '../../data/mood_row_copy.dart';
import '../../data/mood_row_store.dart';
import '../home_v2_scope.dart';

class MoodRowV2 extends StatefulWidget {
  const MoodRowV2({super.key});

  /// The M8 offer lives for this App run only ("下次打開也消失").
  static _M8Offer? _m8;

  @visibleForTesting
  static void resetForTest() => _m8 = null;

  @override
  State<MoodRowV2> createState() => _MoodRowV2State();
}

class _M8Offer {
  const _M8Offer(this.dateIso, this.previous, this.mood);
  final String dateIso;
  final int previous;
  final int mood;
}

class _MoodRowV2State extends State<MoodRowV2> with WidgetsBindingObserver {
  static const _ink = Color(0xFF5A4334);
  static const _softInk = Color(0xFF6E5642);

  MoodRowStore? _store;
  String? _uid;
  bool _loaded = false;
  String _dateIso = '';

  /// Today's latest pick and when (local time).
  int? _mood;
  DateTime? _at;

  bool _skipped = false;
  bool _m7Done = false;
  bool _checkInDone = false;
  bool _expanded = false;
  bool _justRecorded = false;
  Timer? _recordedTimer;

  DateTime _now() => HomeV2Scope.now(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeV2Refresh.changes.addListener(_refreshCheckIn);
    BriefPrV2.changes.addListener(_refreshCheckIn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AppSettingsScope.of(context).profile?.uid;
    if (_store == null || uid != _uid) {
      _uid = uid;
      _store = HomeV2Scope.maybeOf(context)?.moodStore ??
          DefaultMoodRowStore(
              available: AuthServiceScope.of(context).available);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _recordedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HomeV2Refresh.changes.removeListener(_refreshCheckIn);
    BriefPrV2.changes.removeListener(_refreshCheckIn);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Leaving the App: M8 is not offered again on the next open.
      MoodRowV2._m8 = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (MoodRecorder.dateIsoFor(_now()) != _dateIso) {
        unawaited(_load());
      } else {
        setState(() {});
        unawaited(_refreshCheckIn());
      }
    }
  }

  Future<void> _load() async {
    final store = _store;
    final uid = _uid;
    final now = _now();
    final today = MoodRecorder.dateIsoFor(now);
    MoodEntry? latest;
    String? skipped;
    String? m7Done;
    var checkIn = false;
    if (store != null && uid != null) {
      try {
        latest = await store.latestToday(uid, now);
      } catch (_) {}
      try {
        skipped = await store.readMark(MoodRowStore.skippedKey);
        m7Done = await store.readMark(MoodRowStore.m7DoneKey);
      } catch (_) {}
      if (!mounted) return;
      checkIn = await _readCheckIn(uid);
    }
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _dateIso = today;
      _mood = latest?.mood;
      _at = latest?.respondedAt.toLocal();
      _skipped = skipped == today;
      _m7Done = m7Done == today;
      _checkInDone = checkIn;
      _expanded = false;
    });
  }

  Future<bool> _readCheckIn(String uid) async {
    try {
      final custom = HomeV2Scope.maybeOf(context)?.checkedInToday;
      if (custom != null) return await custom(uid);
      return await AdherenceCheck(
              available: AuthServiceScope.of(context).available)
          .hasCheckedInToday(uid)
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshCheckIn() async {
    final uid = _uid;
    if (!mounted || uid == null) return;
    final done = await _readCheckIn(uid);
    if (mounted && done != _checkInDone) setState(() => _checkInDone = done);
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _pick(int value) async {
    final profile = AppSettingsScope.read(context).profile;
    final analytics = AnalyticsScope.of(context);
    final sharedContext = CoreServicesScope.of(context).sharedContext;
    final arm = Arm.isA(context) ? 'A' : 'B';
    final previous = _mood;
    final supplementary = previous != null;
    final now = _now();
    _recordedTimer?.cancel();
    setState(() {
      _mood = value;
      _at = now;
      _expanded = false;
      _justRecorded = true;
      if (supplementary && previous != value) {
        // M8 replaces M7 (and M7 does not come back today).
        MoodRowV2._m8 = _M8Offer(_dateIso, previous, value);
        _m7Done = true;
      }
    });
    _recordedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justRecorded = false);
    });
    if (supplementary && previous != value) {
      unawaited(_store?.writeMark(MoodRowStore.m7DoneKey, _dateIso));
    }
    final store = _store;
    if (profile != null && store != null) {
      // Fire-and-forget (offline writes queue; never lock the faces).
      unawaited(() async {
        try {
          await store.record(uid: profile.uid, mood: value, arm: arm);
        } catch (_) {}
      }());
      // Siu Yan's `[Recent mood snippet]`, as the old home pad.
      unawaited(() async {
        try {
          await sharedContext.updateRecentMood(
            uid: profile.uid,
            mood: SharedMoodSummary(
              summary: '最近一次心情評分：$value/5。',
              asOf: DateTime.now(),
            ),
          );
        } catch (_) {}
      }());
    }
    // The same events as the old pad (dashboards unchanged), new source.
    unawaited(analytics.logEvent(PhaseAEvents.moodCheckin, {
      'skipped': false,
      'mood': value,
      'source': MoodRowStore.sourceSurface,
      'supplementary': supplementary,
    }));
    if (supplementary) {
      unawaited(analytics.logEvent('daily_mood_supplementary', {
        'mood': value,
        'source_surface': MoodRowStore.sourceSurface,
      }));
    } else {
      unawaited(analytics.logDailyMoodSubmitted(mood: value));
    }
  }

  /// M2 遲啲先答: M4 for the rest of the day; one event.
  void _skip() {
    setState(() {
      _skipped = true;
      _expanded = false;
    });
    unawaited(_store?.writeMark(MoodRowStore.skippedKey, _dateIso));
    unawaited(AnalyticsScope.of(context).logEvent(PhaseAEvents.moodCheckin, {
      'skipped': true,
      'source': MoodRowStore.sourceSurface,
    }));
  }

  Future<void> _openChat(MoodChatEntry entry) async {
    setState(() {
      if (entry.changed) {
        MoodRowV2._m8 = null;
      } else {
        _m7Done = true;
      }
    });
    if (!entry.changed) {
      unawaited(_store?.writeMark(MoodRowStore.m7DoneKey, _dateIso));
    }
    unawaited(AnalyticsScope.of(context).logEvent('mood_row_chat_opened', {
      'prompt': entry.promptId,
      'mood': entry.mood,
      if (entry.previousMood != null) 'previous_mood': entry.previousMood,
      if (entry.direction != null) 'direction': entry.direction,
      'opener_id': entry.openerId,
      'copy_version': MoodRowCopy.version,
    }));
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => HomeV2Scope.buildMoodChat(ctx, entry),
    ));
    HomeV2Refresh.bump();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  bool get _chatAvailable => RemoteFeatureFlags.current.checkInChatV2Enabled;

  _M8Offer? get _m8 {
    final o = MoodRowV2._m8;
    return o != null && o.dateIso == _dateIso ? o : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 8);
    final children = <Widget>[];
    final mood = _mood;
    if (mood == null) {
      if (_skipped && !_expanded) {
        children.add(_TapLine(
          key: const ValueKey('mood_row_unanswered'),
          text: MoodRowCopy.m4,
          onTap: () => setState(() => _expanded = true),
        ));
      } else {
        children.add(Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                MoodRowCopy.m1,
                key: const ValueKey('mood_row_question'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    height: 1.3),
              ),
            ),
            if (!_skipped)
              TextButton(
                key: const ValueKey('mood_row_later'),
                onPressed: _skip,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: _softInk,
                ),
                child: const Text(MoodRowCopy.m2,
                    style: TextStyle(
                        fontSize: 15,
                        decoration: TextDecoration.underline)),
              ),
          ],
        ));
        children.add(const SizedBox(height: 6));
        children.add(_Faces(selected: null, onPick: _pick));
      }
    } else {
      children.add(Text(
        MoodRowCopy.m5(mood, _at ?? _now()),
        key: const ValueKey('mood_row_status'),
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: _ink, height: 1.3),
      ));
      if (_justRecorded) {
        children.add(const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            key: ValueKey('mood_row_recorded'),
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: _softInk),
              SizedBox(width: 6),
              Flexible(
                child: Text(MoodRowCopy.m3,
                    style: TextStyle(fontSize: 15, color: _softInk)),
              ),
            ],
          ),
        ));
      } else {
        children.add(Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('mood_row_change'),
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: _softInk,
            ),
            child: const Text(MoodRowCopy.m6,
                style: TextStyle(
                    fontSize: 15, decoration: TextDecoration.underline)),
          ),
        ));
      }
      if (_expanded) {
        children.add(const SizedBox(height: 4));
        children.add(_Faces(selected: mood, onPick: _pick));
      }
    }

    final offer = _chatOffer();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, 0.62),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
        if (offer != null) ...[
          const SizedBox(height: 10),
          offer,
        ],
      ],
    );
  }

  Widget? _chatOffer() {
    final mood = _mood;
    if (mood == null || !_chatAvailable) return null;
    final m8 = _m8;
    if (m8 != null) {
      return _ChatOffer(
        key: const ValueKey('mood_row_m8'),
        text: MoodRowCopy.m8,
        onTap: () => _openChat(
            MoodChatEntry(mood: m8.mood, previousMood: m8.previous)),
      );
    }
    if (_m7Done || _checkInDone) return null;
    return _ChatOffer(
      key: const ValueKey('mood_row_m7'),
      text: MoodRowCopy.m7,
      onTap: () => _openChat(MoodChatEntry(mood: mood)),
    );
  }
}

/// The five faces, 1 好差 … 5 好好 left to right (as the old pad).
class _Faces extends StatelessWidget {
  const _Faces({required this.selected, required this.onPick});
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var rank = 1; rank <= 5; rank++)
          Expanded(
            child: _Face(
              rank: rank,
              selected: selected == rank,
              onTap: () => onPick(rank),
            ),
          ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.rank, required this.selected, required this.onTap});
  final int rank;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final face = MoodRowCopy.faceFor(rank);
    final label = face.label(false);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: ValueKey('mood_row_face_$rank'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 6),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: selected
                ? const Color.fromRGBO(194, 112, 63, 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(face.emoji(), style: const TextStyle(fontSize: 34)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: const Color(0xFF5A4334),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// M4: the whole line is the button.
class _TapLine extends StatelessWidget {
  const _TapLine({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4334),
                    height: 1.3),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: Color(0xFF6E5642)),
          ],
        ),
      ),
    );
  }
}

/// M7 / M8: one tappable line under the row (小欣's colours, as her card).
class _ChatOffer extends StatelessWidget {
  const _ChatOffer({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAECE7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 22, color: Color(0xFF5A2410)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A2410),
                      height: 1.35,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 26, color: Color(0xFF5A2410)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

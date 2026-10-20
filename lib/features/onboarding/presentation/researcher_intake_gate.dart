/// 1020e §2.14 — the researcher explanation gate in front of the intake.
///
/// With `app_config/feature_flags.researcherIntakeGateEnabled` on, the
/// elder no longer goes straight from 「開始之前」 to the intake questions
/// (the five-question page, or — with `researcherIntakeEnabled` on — the
/// 「生命中重要嘅人」 page).  The App stops on a waiting page that shows only
/// [researcherIntakeGateText]: no button, no hint, nothing for a screen
/// reader to press.  The researcher taps the centre of the screen
/// [ResearcherIntakeGate.taps] times within [ResearcherIntakeGate.tapWindow]
/// and the intake opens.  "Centre" is the middle cell of a 3 × 3 grid over
/// the whole page ([ResearcherIntakeGate.centreZone]); taps anywhere else
/// are ignored (they neither count nor reset the count).  Both arms: same
/// page, same flow — nothing here reads the arm.
///
/// The unlock is stored once as `users/{uid}.intakeGateUnlockedAt`, the
/// server time ([IntakeGateUnlockStore]; firestore.rules accept only the
/// server time and no later change).  Until then the waiting page comes
/// back every time the App opens at this step.  An account that already
/// finished 「介紹三個夥伴」 never sees it ([ResearcherIntakeGate.applies]).
///
/// Switch timing.  The switch is read with the other app_config switches
/// at start-up and again right after sign-in (AuthGate).  On a fresh
/// install the start-up read happens before sign-in and is refused, so
/// until the sign-in re-read lands nothing is known.  If no read has
/// reached the document yet ([RemoteFeatureFlags.lastKnown] null — a slow
/// or broken network at sign-up), the gate neither skips nor hangs: it
/// shows the App's 「等一陣…」 and re-reads with growing time-outs; after
/// [ResearcherIntakeGate.flagWait] it shows the waiting page anyway (the
/// researcher can still unlock it) and keeps re-reading — if the switch
/// turns out to be off, the intake opens by itself.  A failed re-read
/// later on keeps the last value actually read.
///
/// The researcher's explanation script is not in the App (1020e §2.14 (5)).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_settings_scope.dart';
import '../../../core/feature_flags/remote_feature_flags.dart';
import '../../../shared/widgets/app_loading_indicator.dart';
import '../../auth/data/user_profile.dart';
import '../../consent/presentation/consent_gate.dart';

/// The waiting page's only text.  Dev draft (1020e §2.14 (1)); Junyu fixes
/// the wording from the screenshot.
const String researcherIntakeGateText = '請等研究人員同你講解，再繼續。';

/// Writes the unlock time.  Injectable for tests.
abstract class IntakeGateUnlockStore {
  Future<void> markUnlocked(String uid);
}

/// `users/{uid}.intakeGateUnlockedAt` = server time, merge (nothing else
/// on the profile is touched).
class FirestoreIntakeGateUnlockStore implements IntakeGateUnlockStore {
  const FirestoreIntakeGateUnlockStore();

  static const String field = 'intakeGateUnlockedAt';

  /// What is written — the server time, never the phone's.
  static Map<String, Object> payload() => {field: FieldValue.serverTimestamp()};

  @override
  Future<void> markUnlocked(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set(payload(), SetOptions(merge: true));
}

class ResearcherIntakeGate extends StatefulWidget {
  /// The signed-in profile (from ConsentGate).
  final UserProfile profile;

  /// The intake page the elder sees once the gate is passed.
  final Widget child;

  /// Test hook; defaults to [RemoteFeatureFlags.lastKnown].
  final bool? gateOn;

  /// Test hook; defaults to [FirestoreIntakeGateUnlockStore].
  final IntakeGateUnlockStore? store;

  /// Test hook for the switch re-read; defaults to
  /// [RemoteFeatureFlags.load] with the given time-out.
  final Future<void> Function(Duration timeout)? reloadFlags;

  /// Test hook for the tap times; defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// How long 「等一陣…」 shows while the switch is unknown before the
  /// waiting page is shown anyway.
  final Duration flagWait;

  const ResearcherIntakeGate({
    super.key,
    required this.profile,
    required this.child,
    this.gateOn,
    this.store,
    this.reloadFlags,
    this.clock,
    this.flagWait = defaultFlagWait,
  });

  /// Taps needed, and the window they must fall in (first to last).
  static const int taps = 3;
  static const Duration tapWindow = Duration(seconds: 2);
  static const Duration defaultFlagWait = Duration(seconds: 8);

  /// The gate is for an account that has neither unlocked it nor finished
  /// 「介紹三個夥伴」.  "Finished" is T37's rule with the fix on (the
  /// onboarding marker, or the App's own trace for accounts from before
  /// the marker), whatever `onboardingAfterEnrollmentFix` is set to — so
  /// an account onboarded before this switch never meets the gate, even
  /// if an intake page would show for it again.
  static bool applies(UserProfile profile) =>
      profile.intakeGateUnlockedAt == null &&
      ConsentGate.needsAgentOnboarding(profile, fixOn: true);

  /// The tap zone: the middle third across and the middle third down —
  /// the centre cell of a 3 × 3 grid over the page.
  static Rect centreZone(Size page) => Rect.fromLTWH(
    page.width / 3,
    page.height / 3,
    page.width / 3,
    page.height / 3,
  );

  @override
  State<ResearcherIntakeGate> createState() => _ResearcherIntakeGateState();
}

class _ResearcherIntakeGateState extends State<ResearcherIntakeGate> {
  final List<DateTime> _tapTimes = [];
  Timer? _retryTimer;
  Timer? _waitTimer;
  bool _waitedOut = false;
  bool _reading = false;
  bool _unlocked = false;
  int _attempt = 0;

  /// true / false once a read has reached the switch; null while unknown.
  bool? get _flagOn =>
      widget.gateOn ??
      RemoteFeatureFlags.lastKnown?.researcherIntakeGateEnabled;

  bool get _needsFlag =>
      !_unlocked &&
      ResearcherIntakeGate.applies(widget.profile) &&
      _flagOn == null;

  @override
  void initState() {
    super.initState();
    _syncFlagReads();
  }

  @override
  void didUpdateWidget(ResearcherIntakeGate old) {
    super.didUpdateWidget(old);
    _syncFlagReads();
  }

  @override
  void dispose() {
    _stopFlagReads();
    super.dispose();
  }

  void _stopFlagReads() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  /// Start (or keep) re-reading while the switch is unknown; stop once it
  /// is known or the gate no longer applies.
  void _syncFlagReads() {
    if (!_needsFlag) {
      _stopFlagReads();
      return;
    }
    _waitTimer ??= Timer(widget.flagWait, () {
      if (mounted) setState(() => _waitedOut = true);
    });
    if (!_reading && _retryTimer == null) unawaited(_readFlags());
  }

  Future<void> _readFlags() async {
    _reading = true;
    _attempt++;
    // 6 s, 9 s, 12 s … up to 20 s per try; the start-up read allows 3 s.
    final timeout = Duration(seconds: math.min(3 + 3 * _attempt, 20));
    try {
      await (widget.reloadFlags ?? _defaultReload)(timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[ResearcherIntakeGate] re-read failed: $e');
    }
    _reading = false;
    if (!mounted) return;
    if (!_needsFlag) {
      _stopFlagReads();
      setState(() {});
      return;
    }
    _retryTimer = Timer(Duration(seconds: math.min(2 * _attempt, 10)), () {
      _retryTimer = null;
      if (mounted) _syncFlagReads();
    });
  }

  static Future<void> _defaultReload(Duration timeout) =>
      RemoteFeatureFlags.load(timeout: timeout);

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _onCentreTap() {
    if (_unlocked) return;
    final now = _now();
    _tapTimes
      ..add(now)
      ..removeWhere((t) => now.difference(t) > ResearcherIntakeGate.tapWindow);
    if (_tapTimes.length >= ResearcherIntakeGate.taps) {
      _tapTimes.clear();
      _unlock(now);
    }
  }

  void _unlock(DateTime now) {
    setState(() => _unlocked = true);
    _stopFlagReads();
    final settings = AppSettingsScope.read(context);
    final profile = settings.profile ?? widget.profile;
    // In memory first so the intake opens at once; the server-time write
    // goes fire-and-forget (the SDK queues it while offline).
    settings.profile = profile.copyWith(intakeGateUnlockedAt: now);
    final store = widget.store ?? const FirestoreIntakeGateUnlockStore();
    unawaited(() async {
      try {
        await store.markUnlocked(profile.uid);
      } catch (e) {
        if (kDebugMode) debugPrint('[ResearcherIntakeGate] save failed: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || !ResearcherIntakeGate.applies(widget.profile)) {
      return widget.child;
    }
    final on = _flagOn;
    if (on == false) return widget.child;
    if (on == null && !_waitedOut) return const _GateLoading();
    return ResearcherIntakeWaitingPage(onCentreTap: _onCentreTap);
  }
}

/// The waiting page: the one line, centred, and a tap area over the whole
/// page that reports only taps inside [ResearcherIntakeGate.centreZone].
class ResearcherIntakeWaitingPage extends StatelessWidget {
  final VoidCallback? onCentreTap;

  const ResearcherIntakeWaitingPage({super.key, this.onCentreTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final page = constraints.biggest;
          return GestureDetector(
            key: const Key('intake_gate_tap_area'),
            behavior: HitTestBehavior.opaque,
            // No "double tap to activate" for a screen reader: there is
            // nothing for the elder to press here.
            excludeFromSemantics: true,
            onTapUp: (details) {
              if (ResearcherIntakeGate.centreZone(
                page,
              ).contains(details.localPosition)) {
                onCentreTap?.call();
              }
            },
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    researcherIntakeGateText,
                    key: const Key('intake_gate_text'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// While the switch is unknown: the App's usual loading line.
class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      body: AppLoadingIndicator(
        key: const Key('intake_gate_loading'),
        message: isEn ? 'Just a moment…' : '等一陣…',
      ),
    );
  }
}

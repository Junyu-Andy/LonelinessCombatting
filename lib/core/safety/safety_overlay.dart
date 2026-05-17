import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';
import '../../l10n/app_localizations.dart';
import '../core_services_scope.dart';
import 'distress_detector.dart';
import 'distress_state.dart';

/// Always-on-top "Talk to someone now" pill. Stacked above every route via
/// MaterialApp's `builder` so it survives full-screen pushes. The label
/// and colour are driven by [DistressState] so modules that detect
/// escalation can paint the pill stronger without owning the widget.
///
/// Suppression: pages that *are* the crisis surface (or that haven't
/// agreed to consent yet) can hide the pill by wrapping themselves in
/// [SafetyOverlaySuppressor]. The overlay maintains a depth counter so
/// nested suppressors compose cleanly.
///
/// Spec §Safety controls: "Persistent 'Talk to someone now' button on
/// every screen".
class SafetyOverlay extends StatefulWidget {
  final Widget child;
  const SafetyOverlay({super.key, required this.child});

  static SafetyOverlayState? _maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<SafetyOverlayState>();

  @override
  State<SafetyOverlay> createState() => SafetyOverlayState();
}

class SafetyOverlayState extends State<SafetyOverlay> {
  int _suppressionDepth = 0;

  void _suppress() {
    if (!mounted) return;
    setState(() => _suppressionDepth++);
  }

  void _release() {
    if (!mounted) return;
    setState(() {
      if (_suppressionDepth > 0) _suppressionDepth--;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_suppressionDepth == 0)
          const Positioned(
            right: 12,
            bottom: 90,
            child: _SafetyPill(),
          ),
      ],
    );
  }
}

/// Wrap a route's body in this to hide the global "Talk now" pill on
/// that screen.
class SafetyOverlaySuppressor extends StatefulWidget {
  final Widget child;
  const SafetyOverlaySuppressor({super.key, required this.child});

  @override
  State<SafetyOverlaySuppressor> createState() =>
      _SafetyOverlaySuppressorState();
}

class _SafetyOverlaySuppressorState extends State<SafetyOverlaySuppressor> {
  SafetyOverlayState? _overlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlay = SafetyOverlay._maybeOf(context);
      _overlay?._suppress();
    });
  }

  @override
  void dispose() {
    _overlay?._release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SafetyPill extends StatefulWidget {
  const _SafetyPill();

  @override
  State<_SafetyPill> createState() => _SafetyPillState();
}

class _SafetyPillState extends State<_SafetyPill> {
  DistressState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // CoreServicesScope may be absent in widget tests that don't build the
    // full app shell; fall back gracefully to the default "low" pill.
    final scope = context
        .dependOnInheritedWidgetOfExactType<CoreServicesScope>();
    final newState = scope?.distressState;
    if (newState != _state) {
      _state?.removeListener(_onChange);
      _state = newState;
      _state?.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _state?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final l10n = AppLocalizations.of(context);
    final level = _state?.level ?? DistressLevel.none;

    final (String label, String semantic, Color bg, IconData icon) =
        switch (level) {
      DistressLevel.none ||
      DistressLevel.low =>
        (
          l10n?.safetyPillLow ?? (isEn ? 'Talk now' : '搵人傾'),
          isEn ? 'Talk to someone now' : '即刻搵人傾',
          const Color(0xFFB91C1C),
          Icons.support_agent_rounded,
        ),
      DistressLevel.moderate => (
          l10n?.safetyPillModerate ?? (isEn ? 'Need support?' : '需要支援？'),
          isEn ? 'Open support options' : '打開支援選項',
          const Color(0xFF991B1B),
          Icons.support_agent_rounded,
        ),
      DistressLevel.acute => (
          l10n?.safetyPillAcute ?? (isEn ? 'Crisis line' : '緊急熱線'),
          isEn ? 'Open the crisis line' : '打開緊急熱線',
          const Color(0xFF7F1D1D),
          Icons.emergency_share_rounded,
        ),
    };

    final fontWeight =
        level == DistressLevel.acute ? FontWeight.w800 : FontWeight.w700;

    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: bg,
        elevation: 6,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            final navigator =
                Navigator.maybeOf(context, rootNavigator: true);
            navigator?.push(MaterialPageRoute<void>(
              builder: (_) => const EmergencySupportPage(),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: fontWeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';

/// Always-on-top "Talk to someone now" pill. Stacked above every route via
/// MaterialApp's `builder` so it survives full-screen pushes (check-in,
/// chat session, settings). Tapping opens the existing
/// [EmergencySupportPage].
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
/// that screen. Used by EmergencySupportPage (it would point at itself),
/// ConsentPage (pre-consent we don't want a red button competing with
/// the boundary card), and LoginPage (no signed-in context yet).
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

class _SafetyPill extends StatelessWidget {
  const _SafetyPill();

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Semantics(
      button: true,
      label: isEn ? 'Talk to someone now' : '即刻搵人傾',
      child: Material(
        color: const Color(0xFFB91C1C),
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
                const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  isEn ? 'Talk now' : '搵人傾',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

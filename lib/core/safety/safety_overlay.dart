import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';

/// Always-on-top "Talk to someone now" pill. Stacked above every route via
/// MaterialApp's `builder` so it survives full-screen pushes (check-in,
/// chat session, settings). Tapping opens the existing
/// [EmergencySupportPage].
///
/// Spec §Safety controls: "Persistent 'Talk to someone now' button on
/// every screen".
class SafetyOverlay extends StatelessWidget {
  final Widget child;
  const SafetyOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 12,
          bottom: 90,
          child: _SafetyPill(),
        ),
      ],
    );
  }
}

class _SafetyPill extends StatelessWidget {
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

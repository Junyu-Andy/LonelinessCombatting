/// Four-block agent intro (Spec §4).
///
///   1. Opening sentence (plain body)
///   2. "我可以做嘅事" — heading + bulleted list
///   3. "我做唔到嘅事" — heading + bulleted list
///   4. Closing AI-identity reminder (plain body)
///
/// All four blocks use the same typography. Block 2 / 3 carry a
/// 24 dp top margin (Spec §4 spacing).
library;

import 'package:flutter/material.dart';

import '../controller/agent_profile_controller.dart';

class ProfileIntroCard extends StatelessWidget {
  final AgentProfileResolution resolution;
  const ProfileIntroCard({super.key, required this.resolution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intro = resolution.intro;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bodyText(theme, resolution.resolveOpening()),
          const SizedBox(height: 24),
          _heading(theme, intro.capabilitiesHeading),
          const SizedBox(height: 10),
          for (final item in intro.capabilities) _bullet(theme, item),
          const SizedBox(height: 24),
          _heading(theme, intro.limitationsHeading),
          const SizedBox(height: 10),
          for (final item in intro.limitations) _bullet(theme, item),
          const SizedBox(height: 24),
          _bodyText(theme, resolution.resolveClosing()),
        ],
      ),
    );
  }

  Widget _bodyText(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _heading(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: resolution.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: _bodyText(theme, text),
          ),
        ],
      ),
    );
  }
}

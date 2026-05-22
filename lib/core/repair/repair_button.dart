/// B.9 — 唔啱意思 (repair / "that wasn't quite right") button.
///
/// Small inline thumbs-down underneath each assistant bubble.  Tapping it
/// signals to the host page that the user wants a different response.  The
/// host page owns the actual re-send / template advance — this widget is
/// just the affordance.
library;

import 'package:flutter/material.dart';

class RepairButton extends StatelessWidget {
  const RepairButton({
    super.key,
    required this.onTap,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.thumb_down_alt_outlined,
                size: 16,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                isEn ? "That wasn't quite right" : '唔啱意思',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Banner shown above a chat composer while a message typed offline is
/// waiting to auto-send when connectivity returns.
class OfflinePendingBanner extends StatelessWidget {
  final String text;
  final bool isEn;
  const OfflinePendingBanner({
    super.key,
    required this.text,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded,
              size: 20, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEn
                  ? "You're offline — this will send automatically once you're "
                      'back online:\n“$text”'
                  : '你而家離線 —— 上線之後會自動幫你發：\n「$text」',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

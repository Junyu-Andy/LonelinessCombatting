import 'package:flutter/material.dart';

/// P4.4 — confirmation dialog for **irreversible** actions only.
///
/// Use this for: deleting a saved memory, abandoning a multi-step
/// flow that has already collected user input, placing an emergency
/// call. Do NOT use it for routine save / submit / setting toggle —
/// adding a confirm step there trains older participants to ignore the
/// dialog, which weakens the signal when it actually matters.
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final isEn = Localizations.localeOf(context).languageCode == 'en';
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      final theme = Theme.of(dialogCtx);
      return AlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 8),
              child: Text(
                cancelLabel ?? (isEn ? 'Cancel' : '取消'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              child: Text(
                confirmLabel ??
                    (destructive
                        ? (isEn ? 'Delete' : '刪除')
                        : (isEn ? 'Confirm' : '確定')),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

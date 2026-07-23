import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';

/// Send button shared by all chat composers.
///
/// Normal theme: the familiar filled circle in the warm primary.
/// High-contrast: primary is pure black there, which turned this into an
/// unreadable black blob — so it flips to white fill + black border +
/// black arrow, matching the outlined high-contrast design language.
class ComposerSendButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const ComposerSendButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final highContrast = AppSettingsScope.of(context).highContrast;
    if (!highContrast) {
      return IconButton.filled(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_upward_rounded),
        iconSize: 28,
      );
    }
    return IconButton.outlined(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_upward_rounded),
      iconSize: 28,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.white,
        disabledForegroundColor: Colors.black38,
        side: BorderSide(
          color: onPressed == null ? Colors.black38 : Colors.black,
          width: 2,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/auth/presentation/auth_service_scope.dart';

/// P3.3 inline re-enable nudge.
///
/// When a participant has previously turned transcript retention off
/// from Settings → Privacy, the next time they enter any Arm A LLM
/// surface we offer a one-shot chance to turn it back on. We never
/// block the LLM call: declining means the session still works, but
/// `MemoryStore.writeSummary` keeps no-op'ing because the consent
/// gate is still off (per its existing contract).
///
/// Why session-scoped suppression: asking once per app launch is the
/// agreed UX trade-off — frequent enough to remind, rare enough to
/// not feel like a dark pattern. We track keys per module so a user
/// who opens M2 then M3 in the same session only sees the prompt once.
class TranscriptConsentPrompter {
  static final Set<String> _askedThisSession = <String>{};

  /// Call before the first LLM send in a module page. Safe to call
  /// multiple times — only the first call per [moduleKey] per session
  /// surfaces a dialog.
  ///
  /// Returns `true` if retention is on at exit (either was on already,
  /// or the user accepted the nudge), `false` otherwise. Callers don't
  /// need to inspect the return — they just continue.
  static Future<bool> maybePrompt({
    required BuildContext context,
    required String moduleKey,
  }) async {
    final settings = AppSettingsScope.read(context);
    final profile = settings.profile;
    if (profile == null) return false;
    if (profile.consent.transcriptRetention) return true;
    if (_askedThisSession.contains(moduleKey)) return false;
    _askedThisSession.add(moduleKey);

    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          isEn
              ? 'Want me to remember again?'
              : '要唔要我記得返你之前傾過嘅嘢？',
        ),
        content: Text(
          isEn
              ? 'You have memory turned off, so right now each visit '
                  'starts from zero. Turn it back on?'
              : '你之前熄咗記憶，所以而家每次都係由零開始。'
                  '要唔要而家開返？',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              isEn ? 'Not now' : '唔使住',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              isEn ? 'Turn it on' : '好，開返',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );

    if (accepted != true) return false;
    if (!context.mounted) return false;
    final updated = profile.copyWith(
      consent: profile.consent.copyWith(transcriptRetention: true),
    );
    settings.profile = updated;
    try {
      await AuthServiceScope.of(context).updateProfile(updated);
    } on AuthUnavailableException {
      // Guest mode — local update is still in effect.
    } catch (_) {
      // Network blip — local update still takes effect; AuthService
      // will reconcile on next successful write.
    }
    return true;
  }

  /// Test hook: clear the session-scoped suppression set so a fresh
  /// flow can re-trigger the prompt.
  @visibleForTesting
  static void resetForTest() {
    _askedThisSession.clear();
  }
}

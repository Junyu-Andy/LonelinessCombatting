import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_overlay.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';

/// Single-screen tiered consent + system-boundary statement.
///
/// P3.3 refactor:
///   - Onboarding only collects the one *required* decision (functional
///     data). Transcript retention defaults to ON and is reframed as an
///     informational tile here; the user can disable it any time from
///     Settings → Privacy.
///   - The previous two-toggle flow asked older participants to make a
///     decision they had little context for. Defaulting transcript ON
///     with a clear disclosure + reachable kill-switch matches §M3's
///     long-term memory design and ConsentGate's ethics rationale
///     (summaries are user-reviewed, not raw transcript).
///
/// The page is shown automatically (by [ConsentGate]) the first time a
/// signed-in profile does not yet have `consent.functionalData == true`.
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafetyOverlaySuppressor(
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(isEn ? 'Before we begin' : '開始之前'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            // 2026-07 simplification: the in-app data-consent tiles
            // (functional data / data summary) duplicated what the signed
            // HREC consent form already covers, and asked elders to
            // re-decide something they'd just signed. This page now only
            // (1) states the research purpose plainly and (2) keeps the
            // system-boundary disclosure. Consent flags are set on 繼續
            // (paper consent is the authority; transcript kill-switch
            // stays in Settings → Privacy).
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.school_outlined,
                            size: 26, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isEn ? 'Research use' : '研究用途',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isEn
                          ? 'This application forms part of a University of '
                              'Hong Kong research study, and is not a product '
                              'for personal use. Your use of the application '
                              'falls within the scope of this study.'
                          : '本應用程式屬香港大學一項研究之一部分，'
                              '並非供個人用途之產品。閣下使用本應用程式之過程，'
                              '均屬是項研究之範圍。',
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _BoundaryCard(isEn: isEn),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _accept,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isEn ? 'Continue' : '繼續',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _ContactFooter(isEn: isEn),
          ],
        ),
      ),
    ));
  }

  Future<void> _accept() async {
    final auth = AuthServiceScope.of(context);
    final settings = AppSettingsScope.read(context);
    final profile = settings.profile;
    if (profile == null) return;
    setState(() => _busy = true);
    final updated = profile.copyWith(
      consent: ConsentFlags(
        // Paper HREC consent is the authority; tapping 繼續 records it.
        functionalData: true,
        // P3.3: transcript retention defaults ON; the user reaches the
        // kill-switch in Settings → Privacy.
        transcriptRetention: true,
        acceptedAt: DateTime.now(),
      ),
    );
    // In-memory first so the consent gate opens immediately; the
    // Firestore write syncs in the background.  Offline, updateProfile's
    // set() waits for server ack — awaiting it froze this Continue
    // button forever (the SDK still queues + syncs the queued write).
    settings.profile = updated;
    unawaited(() async {
      try {
        await auth.updateProfile(updated);
      } on AuthUnavailableException {
        // Guest mode — keep state in memory only.
      } catch (_) {}
    }());
  }
}

class _BoundaryCard extends StatelessWidget {
  final bool isEn;
  const _BoundaryCard({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 26, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'About this tool' : '關於本應用程式',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'This is a research tool, not a medical service, and '
                      'cannot replace professional advice or personal '
                      'relationships.'
                  : '本應用程式為研究用途之數碼工具，並非醫療服務，'
                      '亦不能取代專業意見或人際關係。',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer pointing the participant to the formal consent form and the
/// study contact email.
class _ContactFooter extends StatelessWidget {
  final bool isEn;
  const _ContactFooter({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    return Text(
      isEn
          ? 'Further details are set out in the Informed Consent Form.'
          : '詳情請參閱《知情同意書》。',
      style: style,
      textAlign: TextAlign.center,
    );
  }
}


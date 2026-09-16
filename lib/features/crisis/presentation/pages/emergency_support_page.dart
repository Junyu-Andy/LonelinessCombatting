import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_copy.dart';
import '../../../../core/safety/safety_overlay.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../analytics/presentation/analytics_scope.dart';

/// Crisis page (Phase A baseline S-4, HREC approval §8.1).
///
/// Surfaced by the distress router on an acute flag, from the moderate
/// sheet's "reach someone", and from the settings / footer entry points.
///
/// Content rules (spec §S-4):
///   • Exactly the four resources in `crisis_resources.json`, in order
///     (生命熱線 → 撒瑪利亞會 → 醫管局精神健康專線 → 急症室 / 999).
///   • Every item is one-tap dial; every text ≥ 20 sp.
///   • One headline sentence ≤ 20 characters at the top.
///   • Footer: 「資料核對日期：YYYY-MM-DD」 from the JSON (待核對 until the
///     PI fills it).  Numbers never live in code.
///
/// Logs `crisis_page_shown(from)` on open and `crisis_call_tapped(resource)`
/// per dial.
class EmergencySupportPage extends StatefulWidget {
  /// Where the page was opened from (`acute_route` / `moderate_sheet` /
  /// `settings` / `today_footer` / …) — logged, never shown.
  final String from;

  const EmergencySupportPage({super.key, this.from = 'unknown'});

  @override
  State<EmergencySupportPage> createState() => _EmergencySupportPageState();
}

class _EmergencySupportPageState extends State<EmergencySupportPage> {
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;
    unawaited(AnalyticsScope.of(context).logEvent(
      PhaseAEvents.crisisPageShown,
      {'from': widget.from, 'resourcesVersion': SafetyCopy.crisis.version},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.of(context).profile;
    final contactName = profile?.emergencyContactName?.trim();
    final contactPhone = profile?.emergencyContactPhone?.trim();
    final hasContact = contactName != null && contactName.isNotEmpty;
    final crisis = SafetyCopy.crisis;
    final verified = crisis.verifiedDate.trim();

    return SafetyOverlaySuppressor(
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEn ? 'Get help now' : '即時支援'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // S-4 — one headline sentence, ≤ 20 characters.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    size: 32,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      crisis.headline(isEn),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < crisis.resources.length; i++) ...[
              _ResourceCard(
                index: i + 1,
                resource: crisis.resources[i],
                isEn: isEn,
                emphasis: crisis.resources[i].id == 'emergency_999',
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            _SectionHeader(
              icon: Icons.contacts_outlined,
              title: isEn ? 'Your trusted contact' : '你嘅信任聯絡人',
            ),
            const SizedBox(height: 12),
            if (hasContact)
              _TrustedContactCard(name: contactName, number: contactPhone ?? '')
            else
              _EmptyTrustedContactHint(theme: theme),
            const SizedBox(height: 24),
            Center(
              child: Text(
                isEn
                    ? 'Information verified: ${verified.isEmpty ? 'pending' : verified}'
                    : '資料核對日期：${verified.isEmpty ? '待核對' : verified}',
                style: TextStyle(
                  fontSize: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _dialNumber(BuildContext context, String number,
    {String? resourceId}) async {
  unawaited(AnalyticsScope.of(context).logEvent(
    PhaseAEvents.crisisCallTapped,
    {'resource': resourceId ?? number},
  ));
  final digits = number.replaceAll(RegExp(r'\s'), '');
  final uri = Uri(scheme: 'tel', path: digits);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    if (!context.mounted) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEn ? 'Please dial $number manually' : '請手動撥打 $number'),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 30, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final int index;
  final CrisisResource resource;
  final bool isEn;
  final bool emphasis;

  const _ResourceCard({
    required this.index,
    required this.resource,
    required this.isEn,
    required this.emphasis,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: emphasis ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$index. ${resource.name(isEn)}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text(
              resource.number,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: emphasis ? theme.colorScheme.error : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${resource.hours(isEn)}・${resource.note(isEn)}',
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    _dialNumber(context, resource.number, resourceId: resource.id),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  backgroundColor: emphasis ? theme.colorScheme.error : null,
                  foregroundColor: emphasis ? theme.colorScheme.onError : null,
                  textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.phone_rounded, size: 30),
                label: Text(isEn ? 'Call ${resource.number}' : '撥打 ${resource.number}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedContactCard extends StatelessWidget {
  final String name;
  final String number;

  const _TrustedContactCard({required this.name, required this.number});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final hasNumber = number.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.characters.first,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    hasNumber ? number : (isEn ? 'No phone number' : '未填電話'),
                    style: TextStyle(fontSize: 20, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: hasNumber
                  ? () => _dialNumber(context, number, resourceId: 'trusted_contact')
                  : null,
              iconSize: 32,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(Icons.phone_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrustedContactHint extends StatelessWidget {
  final ThemeData theme;
  const _EmptyTrustedContactHint({required this.theme});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.person_off_outlined, size: 26, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isEn
                    ? 'No trusted contact yet. You can add one in Settings → Profile.'
                    : '仲未設定信任聯絡人。可以喺「設定 → 個人資料」入面填。',
                style: const TextStyle(fontSize: 20, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

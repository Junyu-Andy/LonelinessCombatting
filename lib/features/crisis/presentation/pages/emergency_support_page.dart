import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_overlay.dart';

/// Emergency support page surfaced when the safety pill is tapped or
/// the distress router routes here on an acute flag.
///
/// Buttons fire `tel:` URIs via url_launcher for one-tap dialling on
/// Android and iOS. Falls back to a clipboard copy + snackbar on
/// platforms that don't support tel: (web).
///
/// Defaults trimmed per the May-2026 review:
///   • Hard-coded "表姐 / 阿May" trusted-contact rows removed; the page
///     now reads from `UserProfile.emergencyContactName/Phone` (which
///     onboarding now requires).
///   • Opening copy reframed from "如果你或者身邊嘅人有即時危險" to
///     "如果你有不安嘅諗法" so a participant in moderate distress
///     does not bounce off a phrasing that only fits acute danger.
class EmergencySupportPage extends StatelessWidget {
  const EmergencySupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.of(context).profile;
    final contactName = profile?.emergencyContactName?.trim();
    final contactPhone = profile?.emergencyContactPhone?.trim();
    final hasContact =
        contactName != null && contactName.isNotEmpty;

    return SafetyOverlaySuppressor(
        child: Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Get help now' : '即時支援'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 32,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEn ? 'If you are having upsetting thoughts' : '如果你有不安嘅諗法',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isEn
                      ? 'You can call any of the listeners below for a chat. '
                          'If you or someone near you is in immediate danger, please call 999 right away or go to the nearest A&E.'
                      : '可以打電話搵下面任何一個聆聽者傾下。'
                          '如果你或者身邊嘅人有即時危險，請即刻撥 999 或者去最近嘅急症室。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _dialNumber(context, '999'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    icon: const Icon(Icons.local_phone_rounded, size: 30),
                    label: Text(isEn ? 'Call 999' : '撥 999'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.support_agent_outlined,
            title: isEn ? '24-hour emotional support hotlines' : '24 小時情緒支援熱線',
          ),
          const SizedBox(height: 14),
          _HotlineCard(
            name: isEn ? 'Samaritan Befrienders Hong Kong' : '撒瑪利亞防止自殺會',
            number: '2382 0000',
            hours: isEn ? '24 hours' : '全日 24 小時',
            note: isEn
                ? '24-hour suicide prevention hotline.'
                : '24 小時防止自殺熱線。',
          ),
          const SizedBox(height: 12),
          _HotlineCard(
            name: isEn
                ? 'The Samaritans Hong Kong (multilingual)'
                : '香港撒瑪利亞會（多語）',
            number: '2896 0000',
            hours: isEn ? '24 hours' : '全日 24 小時',
            note: isEn
                ? 'Cantonese, Mandarin or English available.'
                : '可以粵語、普通話或英語溝通。',
          ),
          const SizedBox(height: 12),
          _HotlineCard(
            name: isEn
                ? 'Hospital Authority mental health hotline'
                : '醫管局精神健康專線',
            number: '2466 7350',
            hours: isEn ? '24 hours' : '24 小時',
            note: isEn
                ? 'Hong Kong Hospital Authority psychiatric hotline.'
                : '香港醫院管理局精神科熱線。',
          ),
          const SizedBox(height: 12),
          _HotlineCard(
            name: isEn ? '999 emergency services' : '999 緊急服務',
            number: '999',
            hours: isEn ? '24 hours' : '24 小時',
            note: isEn
                ? 'Call right away if you are in immediate danger.'
                : '即時危險時請即刻撥打。',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.contacts_outlined,
            title: isEn ? 'Your trusted contact' : '你嘅信任聯絡人',
          ),
          const SizedBox(height: 14),
          if (hasContact)
            _TrustedContactCard(
              name: contactName,
              number: contactPhone ?? '',
            )
          else
            _EmptyTrustedContactHint(theme: theme),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.self_improvement,
            title: isEn ? 'While you wait, take a few deep breaths' : '等嚟緊再深呼吸幾下',
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? 'A few things you can try now' : '現在可以試吓嘅幾個動作',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  _TipRow(
                    number: '1',
                    text: isEn
                        ? 'Sit down or lean against a wall, and slowly take three deep breaths.'
                        : '坐落或者攰住牆，慢慢深呼吸三次。',
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    number: '2',
                    text: isEn
                        ? 'Look around, and name three things you can see.'
                        : '望下周圍，講出你見到嘅三樣嘢。',
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    number: '3',
                    text: isEn
                        ? 'Drink a sip of water and give your body a moment to relax.'
                        : '飲一啖水，畀身體一啲時間放鬆。',
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    number: '4',
                    text: isEn
                        ? 'Call or text any of the people listed above.'
                        : '撥電話或者傳訊息畀上面任何一個人。',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

Future<void> _dialNumber(BuildContext context, String number) async {
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
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _HotlineCard extends StatelessWidget {
  final String name;
  final String number;
  final String hours;
  final String note;

  const _HotlineCard({
    required this.name,
    required this.number,
    required this.hours,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              number,
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  hours,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Builder(builder: (context) {
                final isEn =
                    Localizations.localeOf(context).languageCode == 'en';
                return FilledButton.icon(
                  onPressed: () => _dialNumber(context, number),
                  icon: const Icon(Icons.phone_rounded, size: 26),
                  label: Text(isEn ? 'Call $number' : '撥打 $number'),
                );
              }),
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

  const _TrustedContactCard({
    required this.name,
    required this.number,
  });

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
                  Text(
                    name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasNumber ? number : (isEn ? 'No phone number' : '未填電話'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: hasNumber
                  ? () => _dialNumber(context,number)
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
            Icon(Icons.person_off_outlined,
                size: 26, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isEn
                    ? 'No trusted contact yet. You can add one in Settings → Profile.'
                    : '仲未設定信任聯絡人。可以喺「設定 → 個人資料」入面填。',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final String number;
  final String text;

  const _TipRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

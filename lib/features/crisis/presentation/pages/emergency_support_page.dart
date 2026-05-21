import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_overlay.dart';

/// Emergency support page surfaced when the safety pill is tapped or
/// the distress router routes here on an acute flag.
///
/// Buttons used to be inert (empty onPressed). They now copy the
/// number to the clipboard and surface a confirmation snackbar — the
/// most reliable cross-platform behaviour we can ship without the
/// url_launcher dependency. The Phase A pilot's older-adult cohort
/// can paste into the dialer (or the researcher walks them through
/// it in the cognitive interview).
///
/// Defaults trimmed per the May-2026 review:
///   • Hotline list reduced from four to two (Samaritans + Suicide
///     Prevention Services).
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
    final profile = AppSettingsScope.of(context).profile;
    final contactName = profile?.emergencyContactName?.trim();
    final contactPhone = profile?.emergencyContactPhone?.trim();
    final hasContact =
        contactName != null && contactName.isNotEmpty;

    return SafetyOverlaySuppressor(
        child: Scaffold(
      appBar: AppBar(
        title: const Text('即時支援'),
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
                        '如果你有不安嘅諗法',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '可以打電話搵下面任何一個聆聽者傾下。'
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
                    onPressed: () => _copyAndNotify(context, '999'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    icon: const Icon(Icons.local_phone_rounded, size: 30),
                    label: const Text('撥 999'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.support_agent_outlined,
            title: '24 小時情緒支援熱線',
          ),
          const SizedBox(height: 14),
          const _HotlineCard(
            name: '撒瑪利亞防止自殺會',
            number: '2382 0000',
            hours: '全日 24 小時',
            note: '24 小時防止自殺熱線。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '香港撒瑪利亞會（多語）',
            number: '2896 0000',
            hours: '全日 24 小時',
            note: '可以粵語、普通話或英語溝通。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '醫管局精神健康專線',
            number: '2466 7350',
            hours: '24 小時',
            note: '香港醫院管理局精神科熱線。',
          ),
          const SizedBox(height: 12),
          const _HotlineCard(
            name: '999 緊急服務',
            number: '999',
            hours: '24 小時',
            note: '即時危險時請即刻撥打。',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.contacts_outlined,
            title: '你嘅信任聯絡人',
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
            title: '等嚟緊再深呼吸幾下',
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '現在可以試吓嘅幾個動作',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  const _TipRow(
                    number: '1',
                    text: '坐落或者攰住牆，慢慢深呼吸三次。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '2',
                    text: '望下周圍，講出你見到嘅三樣嘢。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '3',
                    text: '飲一啖水，畀身體一啲時間放鬆。',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    number: '4',
                    text: '撥電話或者傳訊息畀上面任何一個人。',
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

/// Phone-dial buttons in Phase A copy the number to the clipboard so
/// participants can paste into the system dialer. Adding the
/// `url_launcher` dependency to fire `tel:` URIs is the obvious next
/// step but is held off to keep the dependency surface minimal until
/// the Phase B build.
Future<void> _copyAndNotify(BuildContext context, String number) async {
  await Clipboard.setData(ClipboardData(text: number));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('電話 $number 已複製。打開電話應用程式貼上即可撥出。'),
      duration: const Duration(seconds: 4),
    ),
  );
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
              child: FilledButton.icon(
                onPressed: () => _copyAndNotify(context, number),
                icon: const Icon(Icons.phone_rounded, size: 26),
                label: const Text('複製電話號碼'),
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

  const _TrustedContactCard({
    required this.name,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    hasNumber ? number : '未填電話',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: hasNumber
                  ? () => _copyAndNotify(context, number)
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
                '仲未設定信任聯絡人。可以喺「設定 → 個人資料」入面填。',
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

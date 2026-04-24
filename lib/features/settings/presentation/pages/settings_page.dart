import 'package:flutter/material.dart';
import '../../../../app/app_settings_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';
import 'faq_page.dart';
import 'privacy_policy_page.dart';

enum _FontScale { standard, large, xlarge }

enum _AppLanguage { cantonese, english }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _FontScale _fontScale = _FontScale.standard;
  bool _quietHours = true;
  bool _voiceReadback = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = AppSettingsScope.of(context);
    final highContrast = settings.highContrast;
    final isEn = settings.locale.languageCode == 'en';
    final language = isEn ? _AppLanguage.english : _AppLanguage.cantonese;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(l10n.settingsTab),
        toolbarHeight: 64,
      ),
      body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            l10n.settingsSubtitle,
            style: theme.textTheme.bodyLarge,
          ),
          if (settings.profile != null) ...[
            const SizedBox(height: 20),
            _ProfileCard(profile: settings.profile!, isEn: isEn),
          ],
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.text_fields_rounded,
            title: isEn ? 'Display' : '顯示設定',
          ),
          const SizedBox(height: 14),
          _FontScaleCard(
            value: _fontScale,
            onChanged: (value) => setState(() => _fontScale = value),
            isEn: isEn,
          ),
          const SizedBox(height: 14),
          _SwitchTileCard(
            icon: Icons.contrast_rounded,
            title: isEn ? 'High-Contrast Mode' : '高對比模式',
            subtitle: isEn
                ? 'Stronger contrast between text and background.'
                : '字體同背景顏色對比更加清楚。',
            value: highContrast,
            onChanged: (value) => settings.highContrast = value,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.language_rounded,
            title: isEn ? 'Language' : '語言',
          ),
          const SizedBox(height: 14),
          _LanguageCard(
            value: language,
            onChanged: (value) {
              settings.locale = value == _AppLanguage.english
                  ? const Locale('en')
                  : const Locale('zh');
            },
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.notifications_none_rounded,
            title: isEn ? 'Notifications' : '通知',
          ),
          const SizedBox(height: 14),
          _SwitchTileCard(
            icon: Icons.nightlight_round,
            title: isEn ? 'Quiet Hours' : '安靜時段',
            subtitle: isEn
                ? 'No reminders between 10 pm and 8 am.'
                : '晚上 10 點到早上 8 點唔會出聲提醒。',
            value: _quietHours,
            onChanged: (value) => setState(() => _quietHours = value),
          ),
          const SizedBox(height: 14),
          _SwitchTileCard(
            icon: Icons.record_voice_over_outlined,
            title: isEn ? 'Voice Read-back' : '語音讀出內容',
            subtitle: isEn
                ? 'Main text will be read aloud when enabled.'
                : '打開後，主要文字會有語音朗讀。',
            value: _voiceReadback,
            onChanged: (value) => setState(() => _voiceReadback = value),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.shield_outlined,
            title: isEn ? 'System Boundaries' : '系統界線',
          ),
          const SizedBox(height: 14),
          _BoundaryCard(isEn: isEn),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.info_outline_rounded,
            title: isEn ? 'About & Support' : '關於同支援',
          ),
          const SizedBox(height: 14),
          _AboutCard(version: '1.0.0 demo', isEn: isEn),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FaqPage(),
                  ),
                );
              },
              icon: const Icon(Icons.help_outline_rounded, size: 26),
              label: Text(isEn ? 'FAQ' : '常見問題'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyPage(),
                  ),
                );
              },
              icon: const Icon(Icons.policy_outlined, size: 26),
              label: Text(isEn ? 'Privacy Policy' : '私隱政策'),
            ),
          ),
        ],
      ),
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

class _FontScaleCard extends StatelessWidget {
  final _FontScale value;
  final ValueChanged<_FontScale> onChanged;
  final bool isEn;

  const _FontScaleCard({required this.value, required this.onChanged, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final options = isEn
        ? const [
            (_FontScale.standard, 'Std', 18.0),
            (_FontScale.large, 'Large', 22.0),
            (_FontScale.xlarge, 'X-Large', 26.0),
          ]
        : const [
            (_FontScale.standard, '標準', 18.0),
            (_FontScale.large, '大', 22.0),
            (_FontScale.xlarge, '特大', 26.0),
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn ? 'Text Size' : '字體大小',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              isEn ? 'The preview below updates instantly.' : '預覽效果會即時反映喺下面。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(options.length, (index) {
                final option = options[index];
                final selected = option.$1 == value;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == options.length - 1 ? 0 : 8,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onChanged(option.$1),
                      child: Container(
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          option.$2,
                          style: TextStyle(
                            fontSize: option.$3,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isEn
                    ? 'Preview: Feeling good today — maybe call a friend.'
                    : '預覽：今日心情幾好，試吓打個電話畀阿May。',
                style: TextStyle(
                  fontSize: options
                      .firstWhere((option) => option.$1 == value)
                      .$3,
                  height: 1.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final _AppLanguage value;
  final ValueChanged<_AppLanguage> onChanged;

  const _LanguageCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = const [
      (_AppLanguage.cantonese, '繁體中文（粵語）', 'Cantonese'),
      (_AppLanguage.english, 'English', '英文'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: options.map((option) {
            final selected = option.$1 == value;
            return RadioListTile<_AppLanguage>(
              value: option.$1,
              groupValue: value,
              onChanged: (selectedValue) {
                if (selectedValue != null) onChanged(selectedValue);
              },
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: Text(
                option.$2,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                option.$3,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              activeColor: Theme.of(context).colorScheme.primary,
              selected: selected,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SwitchTileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTileCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 1.2,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoundaryCard extends StatelessWidget {
  final bool isEn;
  const _BoundaryCard({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = isEn
        ? const [
            (Icons.check_circle_outline, 'Helps you organise feelings and plan next steps.'),
            (Icons.check_circle_outline, 'Provides small, concrete action suggestions.'),
            (Icons.do_disturb_on_outlined, 'Cannot replace a doctor, therapist, or emergency service.'),
            (Icons.do_disturb_on_outlined, 'Should not be used as a crisis-support tool.'),
          ]
        : const [
            (Icons.check_circle_outline, '幫你整理心情、諗下下一步。'),
            (Icons.check_circle_outline, '提供細小、具體嘅行動建議。'),
            (Icons.do_disturb_on_outlined, '唔可以取代醫生、治療或者緊急支援。'),
            (Icons.do_disturb_on_outlined, '唔應該當成危機求助工具。'),
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn ? 'What this app can and cannot do' : '呢個 app 可以做同唔做啲乜',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.$1,
                      size: 26,
                      color: item.$1 == Icons.check_circle_outline
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmergencySupportPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.emergency_outlined,
                      size: 26,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEn
                            ? 'If you are in immediate crisis, call 999 or contact family now.'
                            : '如果有即時危機，請立即撥 999 或者搵屋企人。',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 26,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final String version;
  final bool isEn;

  const _AboutCard({required this.version, required this.isEn});

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
                Icon(
                  Icons.favorite,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'Companion App Demo' : '陪伴型 App Demo',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'This demo shows how a simple structure can help older adults gently face loneliness.'
                  : '呢個 demo 目的係展示點樣用簡單嘅結構，陪長者一齊面對孤獨感。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8A1538), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8A1538),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'HKU',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '由香港大學數據及系統工程學系開發\nHKU Department of Data and Systems Engineering',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B0F2A),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  isEn ? 'Version: $version' : '版本：$version',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserProfile profile;
  final bool isEn;

  const _ProfileCard({required this.profile, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emergencyPhone = profile.emergencyContactPhone;
    final lines = <(IconData, String)>[
      (Icons.person_outline, profile.displayName),
      (Icons.mail_outline, profile.email),
      if (profile.ageGroup != null)
        (Icons.cake_outlined, isEn ? 'Age group: ${profile.ageGroup}' : '年齡組別：${profile.ageGroup}'),
      if (profile.emergencyContactName != null)
        (
          Icons.favorite_outline,
          emergencyPhone != null
              ? (isEn
                  ? 'Emergency: ${profile.emergencyContactName} ($emergencyPhone)'
                  : '緊急聯絡：${profile.emergencyContactName} ($emergencyPhone)')
              : (isEn
                  ? 'Emergency: ${profile.emergencyContactName}'
                  : '緊急聯絡：${profile.emergencyContactName}')
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.account_circle_outlined,
                      size: 28, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(isEn ? 'Your Profile' : '你嘅資料', style: theme.textTheme.titleLarge),
                ),
                _SignOutButton(),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(line.$1,
                        size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line.$2,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = AuthServiceScope.of(context);
    final settings = AppSettingsScope.read(context);
    return TextButton.icon(
      onPressed: () async {
        await auth.signOut();
        settings.profile = null;
      },
      icon: const Icon(Icons.logout_rounded, size: 20),
      label: Builder(builder: (ctx) {
        final isEn = Localizations.localeOf(ctx).languageCode == 'en';
        return Text(isEn ? 'Sign out' : '登出');
      }),
    );
  }
}

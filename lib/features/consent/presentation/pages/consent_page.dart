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
  bool _functional = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
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
            _BoundaryCard(isEn: isEn),
            const SizedBox(height: 16),
            _DataSummaryCard(isEn: isEn),
            const SizedBox(height: 20),
            _ConsentTile(
              required: true,
              value: _functional,
              onChanged: (v) => setState(() => _functional = v),
              title: isEn
                  ? 'Functional data (required)'
                  : '基本功能數據（必須）',
              detail: isEn
                  ? 'Daily mood scores, completed actions, and reminder '
                      'times are stored under your account so the app can '
                      'function.'
                  : '每日心情分數、已完成的小行動、以及提醒時間，'
                      '會儲存於您的帳戶之內，以維持應用程式正常運作。',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _functional && !_busy ? _accept : null,
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
        functionalData: _functional,
        // P3.3: transcript retention defaults ON; the user reaches the
        // kill-switch in Settings → Privacy.
        transcriptRetention: true,
        acceptedAt: DateTime.now(),
      ),
    );
    try {
      await auth.updateProfile(updated);
    } on AuthUnavailableException {
      // Guest mode — keep state in memory only.
    }
    if (!mounted) return;
    settings.profile = updated;
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

/// Concise data-handling summary. The detailed informed-consent for
/// conversation retention is collected on paper alongside this app
/// (May-2026 review decision), so the in-app copy names only what
/// the participant needs to know to use the tool.
class _DataSummaryCard extends StatelessWidget {
  final bool isEn;
  const _DataSummaryCard({required this.isEn});

  @override
  Widget build(BuildContext context) {
    return _InfoTile(
      icon: Icons.lock_outline,
      title: isEn ? 'Data handling' : '資料處理',
      detail: isEn
          ? 'Basic functional data (mood scores, completed actions, '
              'reminder times) is stored under your account so the app '
              'can work. Details on conversation retention appear in '
              'the printed consent form you signed with the research team.'
          : '基本功能數據（心情分數、已完成的小行動、提醒時間）'
              '會儲存於您的帳戶之內，以維持應用程式運作。'
              '有關對話記錄保留嘅詳情，請參閱您同研究團隊簽署嘅紙本知情同意書。',
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
          ? 'Further details are set out in the Research Informed Consent '
              'Form. For enquiries, please contact zhaojyxs@connect.hku.hk.'
          : '詳細內容請參閱《研究知情同意書》。'
              '如有疑問，請電郵 zhaojyxs@connect.hku.hk。',
      style: style,
      textAlign: TextAlign.center,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool required;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String detail;

  const _ConsentTile({
    required this.required,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.detail,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Switch(
                value: value,
                onChanged: onChanged,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(detail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

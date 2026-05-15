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
    final theme = Theme.of(context);
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
            const SizedBox(height: 20),
            Text(
              isEn ? 'One simple choice' : '一個簡單嘅選擇',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _ConsentTile(
              required: true,
              value: _functional,
              onChanged: (v) => setState(() => _functional = v),
              title: isEn
                  ? 'Functional data (required)'
                  : '基本功能數據（必須）',
              detail: isEn
                  ? 'Daily mood scores, completed actions, reminder times — '
                      'the app needs these to work. Stored under your account.'
                  : '每日心情分數、做咗嘅小行動、提醒時間 —— app 需要呢啲先運作得到。'
                      '只會放喺你個帳號入面。',
            ),
            const SizedBox(height: 12),
            _InfoTile(
              icon: Icons.history_edu_outlined,
              title: isEn
                  ? 'We\'ll also remember what you share'
                  : '我哋亦會記得你傾過嘅內容',
              detail: isEn
                  ? 'So next time I can say "last week you mentioned…". The '
                      'summaries are short, reviewed by you, and you can turn '
                      'memory off any time in Settings → Privacy.'
                  : '咁下次我先記得返「上個禮拜你提過…」。記憶都係短小結，'
                      '你自己睇過/改過，隨時可以喺「設定」→「私隱」入面熄返。',
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'You can change these any time in Settings → Privacy.'
                  : '隨時可以喺「設定」→「私隱」入面更改。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
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
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'What I am' : '我係咩',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isEn
                  ? 'I am a digital tool, not a person. I am not a doctor. '
                      'I cannot replace human connection. I am here to help '
                      'you reflect, plan, and stay connected.'
                  : '我係一個數碼工具，唔係真人，亦都唔係醫生。我冇辦法代替人與人之間嘅連結。'
                      '我喺度，係幫你慢慢諗、慢慢計劃、同保持聯繫。',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
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

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_overlay.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';

/// Single-screen tiered consent + system-boundary statement.
///
/// Spec §M1: the original onboarding deck is intentionally out of the in-app
/// flow. What we keep is the *minimum* required to make the consent + boundary
/// promise legible:
///   - One sentence explaining what the app is and is not.
///   - Two independent toggles:
///       * Functional data (required to use the app at all).
///       * Conversation-log retention (optional; Arm A LLM logs only).
///   - Time-stamp on accept.
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
  bool _transcript = false;
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
              isEn ? 'Two simple choices' : '兩個簡單嘅選擇',
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
            _ConsentTile(
              required: false,
              value: _transcript,
              onChanged: (v) => setState(() => _transcript = v),
              title: isEn
                  ? 'Save conversation logs (optional)'
                  : '保留對話紀錄（選擇性）',
              detail: isEn
                  ? 'Lets the app refer back to what you shared in earlier '
                      'sessions ("last week you mentioned..."). You can turn '
                      'this off any time in Settings and your logs will be '
                      'deleted.'
                  : '畀 app 可以記得你之前傾過嘅內容（「上星期你提過…」）。'
                      '隨時可以喺「設定」入面熄返，紀錄會一齊刪除。',
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
        transcriptRetention: _transcript,
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

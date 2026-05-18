import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_overlay.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/auth_service.dart';
import '../../data/user_profile.dart';

/// Email + password sign-in, with a sign-up flow that captures the key
/// profile fields we want to persist: display name, age group, and an
/// emergency contact.
class LoginPage extends StatefulWidget {
  final AuthService authService;

  const LoginPage({super.key, required this.authService});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final settings = AppSettingsScope.read(context);
      late UserProfile profile;
      if (_isSignUp) {
        profile = await widget.authService.signUp(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
          ageGroup: _ageCtrl.text.trim().isEmpty ? null : _ageCtrl.text.trim(),
          emergencyContactName: _contactNameCtrl.text.trim().isEmpty
              ? null
              : _contactNameCtrl.text.trim(),
          emergencyContactPhone: _contactPhoneCtrl.text.trim().isEmpty
              ? null
              : _contactPhoneCtrl.text.trim(),
          preferredLanguage: settings.locale.languageCode,
        );
        if (mounted) {
          AnalyticsScope.of(context).logAuth('signed_up');
        }
      } else {
        profile = await widget.authService.signIn(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
      }
      if (!mounted) return;
      settings.profile = profile;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppSettingsScope.of(context);

    return SafetyOverlaySuppressor(child: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(isSignUp: _isSignUp),
                const SizedBox(height: 24),
                if (!widget.authService.available)
                  _GuestBanner()
                else
                  const SizedBox.shrink(),
                if (!widget.authService.available) const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '電郵',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return '請輸入電郵。';
                    if (!value.contains('@')) return '電郵格式唔啱。';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  textInputAction: _isSignUp
                      ? TextInputAction.next
                      : TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '密碼',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) {
                    if ((v ?? '').length < 6) return '密碼最少 6 個字。';
                    return null;
                  },
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: 20),
                  _SectionLabel(
                    icon: Icons.badge_outlined,
                    text: '基本資料',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '你想我哋點樣叫你？',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '請輸入稱呼。' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '年齡',
                      hintText: '例：72',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null; // optional
                      final n = int.tryParse(text);
                      if (n == null) return '請輸入數字。';
                      if (n < 1 || n > 120) return '請輸入合理嘅年齡。';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(
                    icon: Icons.contacts_outlined,
                    text: '緊急聯絡人（必須）',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '我哋會喺「即時支援」頁面顯示呢位聯絡人，方便有需要時搵到佢。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _contactNameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '聯絡人稱呼',
                      prefixIcon: Icon(Icons.favorite_outline),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '請填寫聯絡人稱呼。' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contactPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '聯絡電話',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return '請填寫聯絡電話。';
                      if (value.length < 6) return '電話號碼太短。';
                      return null;
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_isSignUp
                          ? Icons.person_add_alt
                          : Icons.login_rounded),
                  label: Text(_isSignUp ? '建立帳號' : '登入'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                          }),
                  child: Text(
                    _isSignUp ? '已有帳號？登入' : '未有帳號？建立一個',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 18),
                _LanguageSwitcher(
                  currentLocale: settings.locale,
                  onChanged: (locale) => settings.locale = locale,
                ),
                const SizedBox(height: 22),
                const _HkuBadge(),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _HkuBadge extends StatelessWidget {
  const _HkuBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
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
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '由香港大學數據及系統工程學系開發',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'HKU Department of Data and Systems Engineering',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool isSignUp;

  const _Header({required this.isSignUp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite, size: 36, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text('陪伴型 Demo', style: theme.textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          isSignUp ? '建立你嘅帳號' : '歡迎返嚟',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          isSignUp
              ? '填少少資料幫我哋認識你。'
              : '輸入你嘅電郵同密碼。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(text, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade700, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Firebase 未設定。登入功能暫時唔可用，但語言同高對比模式仍然正常。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.brown.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSwitcher extends StatelessWidget {
  final Locale currentLocale;
  final ValueChanged<Locale> onChanged;

  const _LanguageSwitcher({
    required this.currentLocale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = currentLocale.languageCode == 'zh';
    return Center(
      child: Wrap(
        spacing: 8,
        children: [
          Icon(Icons.language_rounded,
              size: 22, color: theme.colorScheme.onSurfaceVariant),
          InkWell(
            onTap: () => onChanged(const Locale('zh')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '中文',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isZh ? FontWeight.w700 : FontWeight.w400,
                  color:
                      isZh ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Text('|', style: theme.textTheme.bodyLarge),
          InkWell(
            onTap: () => onChanged(const Locale('en')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'English',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: !isZh ? FontWeight.w700 : FontWeight.w400,
                  color: !isZh
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

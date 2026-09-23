import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../../core/testing/tester_gate.dart';
import '../../../../core/version/build_info.dart';
import '../../../../l10n/app_localizations.dart';
import 'faq_page.dart';
import 'privacy_policy_page.dart';

/// 關於同支援 — sub-page holding the app info card, FAQ and privacy policy.
/// Nested here (2026-07 IA cleanup) so the 自己 tab stops scrolling forever.
class SupportAboutPage extends StatelessWidget {
  /// Displayed version string, passed from the settings page.
  final String version;
  const SupportAboutPage({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'About & Support' : '關於同支援'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite,
                            size: 26, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(l10n.appTitle,
                            style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // V-1 — field-checkable pin: version, build, lexicon and
                    // the first 8 hex of promptBundleHash must match the
                    // Manual §13 table for this Phase A build.
                    // Tester unlock: 7 taps on the version line → PIN dialog.
                    const _VersionTapTarget(),
                    const SizedBox(height: 4),
                    Text(
                      (isEn ? 'Lexicon ' : '詞表 ') + BuildInfo.lexiconVersion,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (isEn ? 'Prompt bundle ' : 'Prompt bundle ') +
                          BuildInfo.promptBundleHashShort,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '由香港大學數據及系統工程學系開發',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FaqPage()),
                ),
                icon: const Icon(Icons.help_outline_rounded, size: 26),
                label: Text(isEn ? 'FAQ' : '常見問題'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyPage()),
                ),
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


class _VersionTapTarget extends StatefulWidget {
  const _VersionTapTarget();

  @override
  State<_VersionTapTarget> createState() => _VersionTapTargetState();
}

class _VersionTapTargetState extends State<_VersionTapTarget> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTap() {
    final now = DateTime.now();
    _taps = now.difference(_last) > const Duration(seconds: 2) ? 1 : _taps + 1;
    _last = now;
    if (_taps >= 7) {
      _taps = 0;
      _askPin();
    }
  }

  Future<void> _askPin() async {
    if (TesterGate.unlocked.value) {
      _toast('測試員工具已解鎖，去「自己」頁最底。');
      return;
    }
    if (!TesterGate.isConfigured) {
      _toast('呢個 build 冇設定測試密碼（build 時加 --dart-define=TESTER_PIN=…）。');
      return;
    }
    if (TesterGate.isLockedOut) {
      _toast('輸入錯誤次數太多，請重開 app 再試。');
      return;
    }
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('測試員密碼'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '輸入密碼'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('解鎖'),
          ),
        ],
      ),
    );
    if (pin == null || !mounted) return;
    if (TesterGate.tryUnlock(pin)) {
      _toast('已解鎖。測試員工具喺「自己」頁最底；重開 app 會自動鎖返。');
    } else {
      _toast(TesterGate.isLockedOut
          ? '密碼錯誤，已鎖定到下次重開 app。'
          : '密碼錯誤（仲可以試 ${TesterGate.attemptsLeft} 次）。');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Text(
        isEn
            ? 'Version ${BuildInfo.appVersion} (build ${BuildInfo.buildNumber})'
            : '版本 ${BuildInfo.appVersion}（build ${BuildInfo.buildNumber}）',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

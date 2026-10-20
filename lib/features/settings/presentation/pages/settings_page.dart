import 'package:flutter/material.dart';
import '../../../../app/app_settings.dart';
import '../../../../app/app_settings_scope.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/memory/memory_mode.dart';
import '../../../../core/privacy/transcript_retention.dart';
import '../../../../core/testing/tester_gate.dart';
import '../../../../core/version/build_info.dart';
import '../../data/quiet_hours_store.dart';
import '../../data/tester_arm_switch.dart';
import '../../data/tester_tools.dart';
import '../widgets/quiet_hours_card.dart';
import '../widgets/tester_arm_switch_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';
import '../../../personalization/presentation/pages/personalization_page.dart';
import '../../../memory/presentation/pages/remembered_page.dart';
import '../../../my_story/presentation/pages/my_story_page.dart';
import '../../../assessment/presentation/pages/pgic_page.dart';
import '../../../assessment/presentation/pages/agent_diff_page.dart';
import '../../../../core/config/phase_a_schedule_config.dart';
import '../../../ada/data/ada_gate.dart';
import '../../../ada/presentation/ada_page.dart';
import '../../../ada/data/survey_draft_store.dart';
import '../../../ada/presentation/day7_flow_page.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../assessment/presentation/pages/djg_es_page.dart';
import '../../../assessment/data/djg_w2.dart';
import '../../../assessment/presentation/pages/djg_w2_page.dart';
import '../../../ppr/presentation/pages/ppr_brief_page.dart';
import '../../../weekly_pr/data/weekly_pr_trigger.dart';
import '../../../weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'support_about_page.dart';
import 'tester_schedule_page.dart';
import 'tester_weekly_bundle_page.dart';

enum _AppLanguage { cantonese, english }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.testerArmBackend = const CloudTesterArmBackend(),
  });

  /// The `setTesterArm` call behind the tester arm switch (tests: a fake).
  final TesterArmBackend testerArmBackend;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    TesterGate.unlocked.addListener(_onGate);
  }

  @override
  void dispose() {
    TesterGate.unlocked.removeListener(_onGate);
    super.dispose();
  }

  void _onGate() {
    if (mounted) setState(() {});
  }

  // T37: 安靜時段 / 語音讀出內容 moved from widget state to AppSettings so
  // they survive closing the App (persisted with the display settings).

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = AppSettingsScope.of(context);
    final fontScale = settings.fontScale;
    final isEn = settings.locale.languageCode == 'en';
    final language = isEn ? _AppLanguage.english : _AppLanguage.cantonese;

    return Scaffold(
      body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // 10/19: the old intro line (「語言、界線、demo 資料」) and the
          // 「你嘅資料」 card with its 登出 button are gone; the details,
          // editing and 登出 all live behind the 個人資料 tile below.

          // 自己 tab (Product Overview §3.2) now folds three personal
          // surfaces above the existing settings sections:
          //   · 我的紀錄 (Progress)
          //   · 我的資料 (Profile / Personalization)
          //   · 緊急支援 (Emergency support)
          // 2026-07 IA cleanup: 「關於我」grab-bag split into 個人資料
          // (who I am) and 反饋／問卷 (research instruments); the weekly
          // recap tile removed (你嘅一個禮拜 lives behind Today's 進度
          // shortcut). 人生回顧 stays here TEMPORARILY pending its new
          // home (likely 搵人傾) — removing it now would orphan M3.
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.person_outline,
            title: isEn ? 'My profile' : '個人資料',
          ),
          const SizedBox(height: 10),
          _NavTileCard(
            icon: Icons.account_circle_outlined,
            title: isEn ? 'My profile' : '個人資料',
            subtitle: l10n.meItemProfileSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PersonalizationPage(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTileCard(
            icon: Icons.support_outlined,
            title: l10n.meItemCrisis,
            subtitle: l10n.meItemCrisisSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmergencySupportPage(from: 'settings'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTileCard(
            icon: Icons.menu_book_outlined,
            title: isEn ? 'Life-review progress' : '人生回顧',
            subtitle: isEn
                ? 'Take your time — skip anything you\'d rather not discuss.'
                : '慢慢嚟，可以跳過唔想講嘅時期。',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyStoryPage()),
            ),
          ),
          // C20 / decision 0020: the participant's own off switch for
          // transcript retention (both arms; default stays on).  10/19:
          // hidden unless app_config/feature_flags.
          // transcriptRetentionToggleEnabled; the stored value is untouched.
          if (RemoteFeatureFlags.current.transcriptRetentionToggleEnabled) ...[
            const SizedBox(height: 10),
            _TranscriptRetentionTile(
              isEn: isEn,
              value: TranscriptRetention.isOn(settings.profile),
              onChanged: settings.profile == null
                  ? null
                  : (value) async {
                      final profile = settings.profile!;
                      final updated = profile.copyWith(
                        consent:
                            TranscriptRetention.set(profile.consent, value),
                      );
                      settings.profile = updated;
                      try {
                        await AuthServiceScope.of(context)
                            .updateProfile(updated);
                      } catch (_) {
                        // Offline / guest: the local value stands; the SDK
                        // syncs later.
                      }
                    },
            ),
          ],

          // Memory v1: Phase B Arm A has it (no toggle); testers on a
          // MEMORY_V1 build can switch it on. Everyone else: no section.
          if (FeatureFlags.memoryV1 ||
              MemoryModes.of(settings.profile) == MemoryMode.phaseB) ...[
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.psychology_outlined,
              title: isEn ? 'Memory' : '記憶',
            ),
            if (MemoryModes.of(settings.profile) != MemoryMode.phaseB) ...[
            const SizedBox(height: 10),
            _SwitchTileCard(
              icon: Icons.bookmark_border_rounded,
              title: isEn ? 'Let companions remember' : '俾佢哋記得我講過嘅嘢',
              subtitle: isEn
                  ? 'Your name and family are known to all three; what '
                      'you tell each one stays with that one. Off any time.'
                  : '三位都會知你叫咩名、屋企有邊個；你同每位講嘅心事，'
                      '就只有佢知。隨時可以熄。',
              value: settings.profile?.memoryEnabled ?? false,
              onChanged: (value) async {
                final profile = settings.profile;
                if (profile == null) return;
                final updated = profile.copyWith(memoryEnabled: value);
                settings.profile = updated;
                try {
                  await AuthServiceScope.of(context).updateProfile(updated);
                } catch (_) {
                  // Offline: the local value stands; the SDK syncs later.
                }
              },
            ),
            ],
            const SizedBox(height: 10),
            _NavTileCard(
              icon: Icons.list_alt_rounded,
              title: isEn ? 'What I remember' : '我記得嘅嘢',
              subtitle: isEn
                  ? 'See, confirm or delete anything remembered.'
                  : '睇下、確認或者刪除記住咗嘅嘢。',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RememberedPage(),
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.text_fields_rounded,
            title: isEn ? 'Display' : '顯示設定',
          ),
          const SizedBox(height: 14),
          _FontScaleCard(
            value: fontScale,
            onChanged: (value) => settings.fontScale = value,
            isEn: isEn,
          ),
          // 10/20 (dev-tasks-1020 §H): 高對比 moved one level down to
          // 我的設定 → 顯示; the 通知 section (安靜時段, 今日休息) is gone
          // from this level; the server ignores quietHoursEnabled and
          // quietTodayActivatedAt.  1020o: 安靜時段 is back one level down,
          // 我的設定 → 安靜時段 (「由」 / 「到」, no switch).
          const SizedBox(height: 14),
          _NavTileCard(
            key: const Key('settings_my_settings'),
            icon: Icons.tune_rounded,
            title: isEn ? 'My settings' : '我的設定',
            subtitle: isEn ? 'Display: high contrast' : '顯示：高對比模式',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MySettingsPage()),
            ),
          ),
          // Language picker hidden while the app is Cantonese-only
          // (AppSettings.englishEnabled). Re-enable both together.
          if (AppSettings.englishEnabled) ...[
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
          ],
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
          // App info + FAQ + privacy nested one level down so the 自己
          // tab stops scrolling forever (2026-07 IA cleanup).
          _NavTileCard(
            icon: Icons.help_outline_rounded,
            title: isEn ? 'About, FAQ & privacy' : '關於本App／常見問題／私隱',
            subtitle: isEn
                ? 'Version info, common questions, privacy policy'
                : '版本資料、常見問題、私隱政策',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportAboutPage(
                    version: '${BuildInfo.appVersion}+${BuildInfo.buildNumber}'),
              ),
            ),
          ),
          // Research section deferred per product — weekly PPR and the
          // researcher dashboard return here when those instruments are
          // ready to expose to participants again.

          // T6 — tester tools.  Hidden from everyone until unlocked on
          // 關於同支援 → tap the version line 7×: an isTester account with
          // app_config/feature_flags.testerToolsEnabled gets straight in
          // (10/19), otherwise the build's TESTER_PIN (core/testing).
          if (TesterGate.unlocked.value) ...[
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.bug_report_outlined,
              title: isEn ? 'Tester tools' : '測試員工具',
            ),
            const SizedBox(height: 14),
            // 1014e §2.3 (backlog 96): the tester flag is admin-only now —
            // the rules refuse any client write — so this is read-only.
            Card(
              key: const Key('settings_tester_flag'),
              child: ListTile(
                leading: const Icon(Icons.science_outlined),
                title: Text(isEn ? 'Tester account' : '測試員帳號'),
                subtitle: Text(isEn
                    ? ((settings.profile?.isTester ?? false)
                        ? 'This account is a tester: excluded from research '
                            'data; acute alerts are logged but not e-mailed. '
                            'Set by the admin (tool/set_tester.js).'
                        : 'Not a tester. Only the admin can change this '
                            '(tool/set_tester.js or the console).')
                    : ((settings.profile?.isTester ?? false)
                        ? '呢個帳號係測試員：唔計入研究數據；acute 事件會記錄但唔會 email。'
                            '由管理員設定（tool/set_tester.js）。'
                        : '唔係測試員。只有管理員可以改（tool/set_tester.js 或控制台）。')),
              ),
            ),
            // Tester arm switch: tester accounts only (functions/tester_arm.js).
            if (settings.profile?.isTester ?? false) ...[
              const SizedBox(height: 12),
              TesterArmSwitchCard(backend: widget.testerArmBackend),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _resetMyData(isEn),
                icon: const Icon(Icons.restart_alt_rounded, size: 26),
                label: Text(isEn ? 'Reset my data' : '重置我嘅資料'),
              ),
            ),
            const SizedBox(height: 20),
            // Survey preview (办法二): open each instrument directly, without
            // meeting its real trigger conditions, so testers can see the
            // actual UI. Completing one writes to THIS (tester) account.
            Text(
              isEn ? 'Preview surveys' : '預覽量表',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _SurveyPreviewButtons(isEn: isEn),
            const SizedBox(height: 12),
            // 10/19: the weekly questionnaire (T24) on demand — preview any
            // bundle at once, or jump the in-app clock to its day.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('settings_tester_weekly_bundle'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const TesterWeeklyBundlePage()),
                ),
                icon: const Icon(Icons.assignment_outlined, size: 26),
                label: const Text('每週問卷測試'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TesterSchedulePage()),
                ),
                icon: const Icon(Icons.calendar_month_outlined, size: 26),
                label: const Text('日程模擬／測試推送'),
              ),
            ),
            // Direct survey entries — moved here from the participant-visible
            // settings list (2026-09-23): participants must only reach PGIC
            // / Agent Differentiation through their scheduled windows.
          const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.fact_check_outlined,
              title: isEn ? 'Feedback & surveys' : '反饋／問卷',
            ),
            const SizedBox(height: 10),
            _NavTileCard(
              icon: Icons.sentiment_satisfied_outlined,
              // 1020f: named like the PGIC part and its new stem.
              title: isEn ? 'Compared with when you started' : '同開始用嗰時比較',
              subtitle: isEn
                  ? 'Loneliness compared with before you started'
                  : '同開始用之前比，孤獨感有冇變？',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PgicPage()),
              ),
            ),
            // T17 — old W2/W4 page: hidden where AdaGate says so (Phase B
            // default, or Phase A once the new ADA is on).
            if (AdaGate.legacyAgentDiffVisible()) ...[
            const SizedBox(height: 10),
            _NavTileCard(
              icon: Icons.people_alt_outlined,
              title: isEn ? 'Companion assessment' : '夥伴評估',
              subtitle: isEn
                  ? 'W2/W4 usage and personality rating'
                  : '第 2 及 4 週嘅夥伴使用評估',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AgentDiffPage(wave: 2),
                ),
              ),
            ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: TesterGate.lock,
                icon: const Icon(Icons.lock_outline, size: 24),
                label: const Text('鎖定測試員工具（同時返回真實時間）'),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Future<void> _resetMyData(bool isEn) async {
    final settings = AppSettingsScope.read(context);
    final auth = AuthServiceScope.of(context);
    final profile = settings.profile;
    if (profile == null) return;
    final confirmed = await showAppConfirm(
      context: context,
      title: isEn ? 'Reset my data?' : '重置我嘅資料？',
      message: isEn
          ? 'Deletes this account\'s agent memory, mood log, and rolling '
              'summaries so you can re-walk onboarding. Cannot be undone.'
          : '會刪除呢個帳號嘅 agent 記憶、心情記錄同滾動摘要，等你可以由頭再行一次。'
              '刪咗冇得返。',
      confirmLabel: isEn ? 'Reset' : '重置',
    );
    if (!confirmed || !mounted) return;
    final tools = TesterTools(available: auth.available);
    final count = await tools.resetMyData(profile.uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEn
            ? 'Reset done — $count document(s) deleted.'
            : '已重置 — 刪咗 $count 份記錄。'),
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

class _FontScaleCard extends StatefulWidget {
  final AppFontScale value;
  final ValueChanged<AppFontScale> onChanged;
  final bool isEn;

  const _FontScaleCard({required this.value, required this.onChanged, required this.isEn});

  @override
  State<_FontScaleCard> createState() => _FontScaleCardState();
}

/// 10/19 (Junyu): five levels; each button shows 「字」 at a fixed size that
/// grows level by level, the name underneath.  A pick changes the whole App
/// at once, so instead of a preview line the card asks once whether the
/// new size is too big (or too small), with a button back to the old one.
/// Answering is optional.
class _FontScaleCardState extends State<_FontScaleCard> {
  static const _glyphSizes = [17.0, 19.0, 21.0, 23.0, 25.0];

  /// The level before the last pick; null = no question showing.
  AppFontScale? _before;

  bool get isEn => widget.isEn;

  String _name(AppFontScale s) => switch (s) {
        AppFontScale.standard => isEn ? 'Std' : '標準',
        AppFontScale.slightlyLarge => isEn ? 'M' : '稍大',
        AppFontScale.large => isEn ? 'L' : '大',
        AppFontScale.larger => isEn ? 'XL' : '較大',
        AppFontScale.xLarge => isEn ? 'Max' : '特大',
      };

  void _pick(AppFontScale s) {
    if (s == widget.value) return;
    setState(() => _before = widget.value);
    widget.onChanged(s);
  }

  void _undo() {
    final before = _before;
    setState(() => _before = null);
    if (before != null) widget.onChanged(before);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const levels = AppFontScale.values;
    final value = widget.value;
    final before = _before;

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
              isEn
                  ? 'The whole App changes as soon as you pick.'
                  : '揀咗之後，成個 App 嘅字即刻跟住變。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // The buttons keep their own sizes whatever level is on, so the
            // five always fit in one row.
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.noScaling),
              child: Row(
                children: [
                  for (var i = 0; i < levels.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: i == levels.length - 1 ? 0 : 6),
                        child: Semantics(
                          button: true,
                          selected: levels[i] == value,
                          label: _name(levels[i]),
                          excludeSemantics: true,
                          child: InkWell(
                            key: Key('font_scale_${levels[i].name}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _pick(levels[i]),
                            child: Container(
                              height: 76,
                              decoration: BoxDecoration(
                                color: levels[i] == value
                                    ? cs.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: levels[i] == value
                                      ? cs.primary
                                      : cs.outlineVariant,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isEn ? 'A' : '字',
                                    style: TextStyle(
                                      fontSize: _glyphSizes[i],
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                      color: levels[i] == value
                                          ? cs.onPrimary
                                          : cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _name(levels[i]),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: levels[i] == value
                                            ? cs.onPrimary
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (before != null && before != value) ...[
              const SizedBox(height: 16),
              _FontSizeCheck(
                key: const Key('font_scale_check'),
                bigger: value.index > before.index,
                beforeName: _name(before),
                isEn: isEn,
                onUndo: _undo,
                onKeep: () => setState(() => _before = null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「字大咗，會唔會太大？」 (or 太細) with 返回 and 啱啱好.
class _FontSizeCheck extends StatelessWidget {
  final bool bigger;
  final String beforeName;
  final bool isEn;
  final VoidCallback onUndo;
  final VoidCallback onKeep;

  const _FontSizeCheck({
    super.key,
    required this.bigger,
    required this.beforeName,
    required this.isEn,
    required this.onUndo,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final question = bigger
        ? (isEn ? 'Text is bigger now. Too big?' : '字大咗。會唔會太大？')
        : (isEn ? 'Text is smaller now. Too small?' : '字細咗。會唔會太細？');
    final undo = bigger
        ? (isEn ? 'Too big, back to $beforeName' : '太大，返回「$beforeName」')
        : (isEn ? 'Too small, back to $beforeName' : '太細，返回「$beforeName」');
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              question,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('font_scale_undo'),
              onPressed: onUndo,
              child: Text(undo, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('font_scale_keep'),
              onPressed: onKeep,
              child: Text(isEn ? 'Just right' : '啱啱好'),
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
            // ignore: deprecated_member_use
            return RadioListTile<_AppLanguage>(
              value: option.$1,
              // ignore: deprecated_member_use
              groupValue: value,
              // ignore: deprecated_member_use
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
    super.key,
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
                    builder: (_) => const EmergencySupportPage(from: 'settings'),
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


class _TranscriptRetentionTile extends StatelessWidget {
  final bool isEn;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _TranscriptRetentionTile({
    required this.isEn,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEn
                        ? 'Remember our conversations'
                        : '保留對話紀錄',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'When this is off, I won\'t remember what you shared in earlier sessions — each visit starts from zero.'
                  : '熄咗之後，我下次就唔記得返你之前傾過嘅內容，每次都係由零開始。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple ListTile-style navigation card used by the new 自己 tab
/// header (Progress / Profile / Emergency).  Visually consistent with
/// the existing [_SwitchTileCard] but without the trailing switch.
class _NavTileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tester-only: one tap opens each survey with placeholder context so the
/// real UI can be reviewed without waiting for its trigger conditions.
class _SurveyPreviewButtons extends StatelessWidget {
  final bool isEn;
  const _SurveyPreviewButtons({required this.isEn});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, Widget page) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _open(context, page),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(label),
              ),
            ),
          ),
        );

    return Column(
      children: [
        btn(
          isEn ? 'Brief PR (4 sliders)' : 'Brief PR（4 滑桿）',
          const BriefPrPage(
            agentId: 'siu_yan',
            agentDisplayName: '小欣',
            isAnchorPrompt: true,
          ),
        ),
        btn(
          isEn ? 'Weekly PR (12 items)' : 'Weekly PR（12 題）',
          WeeklyPrPage(
            agent: WeeklyPrAgentUsage(
              agentId: 'siu_yan',
              displayName: '小欣',
              sessionCount: 3,
              firstUseAt: DateTime.now(),
            ),
          ),
        ),
        btn('PGIC', const PgicPage()),
        // 1020f: the Phase A DJG-ES page; a Phase B build shows only the
        // Phase B DJG W2 below, so testers cannot open the wrong one.
        if (!FeatureFlags.phaseB)
          btn(
            isEn ? 'DJG-ES (Week 2, 6 items)' : 'DJG-ES（第 2 週，6 題）',
            const DjgEsPage(timepoint: 'week2'),
          ),
        // T18 — Phase B W2 DJG preview for reviewers; saves nothing.
        btn(
          isEn ? 'DJG W2 (Phase B, 6 items, preview — not saved)' : 'DJG W2（Phase B，6 題，預覽，不儲存）',
          DjgW2Page(store: PreviewDjgW2Store()),
        ),
        btn(
          isEn ? 'Crisis page (S-4)' : '危機頁面（S-4）',
          const EmergencySupportPage(from: 'tester_tools'),
        ),
        btn(
          isEn ? 'PPR brief (after session)' : 'PPR 簡版（session 後）',
          const PprBriefPage(
            agentId: 'ah_jan_ah_bak',
            sessionTag: 'preview',
          ),
        ),
        if (AdaGate.legacyAgentDiffVisible())
          btn(
            isEn ? 'Agent Diff (wave 2)' : 'Agent Diff（第 2 波）',
            const AgentDiffPage(wave: 2),
          ),
        // T17 — Phase A ADA / day-7 previews; never in a Phase B build.
        // Preview timepoints (unique per build of this list) don't block
        // the real ones, and a submitted preview can be repeated.
        if (!FeatureFlags.phaseB) ...[
          btn(
            isEn ? 'ADA (short: B+D, visit 1)' : 'ADA（短版 B+D，第 1 次到訪）',
            AdaPage(
              timepoint: AdaTimepoint(
                  id: 'preview_short_${DateTime.now().millisecondsSinceEpoch}',
                  form: AdaForm.short,
                  dayFrom: 0,
                  dayTo: 0),
              allowSkip: PhaseAScheduleConfig.current.adaAllowSkip,
              askReminderTime: true,
            ),
          ),
          btn(
            isEn ? 'ADA (full: A+B+C+D)' : 'ADA（全版 A+B+C+D）',
            AdaPage(
              timepoint: AdaTimepoint(
                  id: 'preview_full_${DateTime.now().millisecondsSinceEpoch}',
                  form: AdaForm.full,
                  dayFrom: 0,
                  dayTo: 0),
              allowSkip: PhaseAScheduleConfig.current.adaAllowSkip,
            ),
          ),
          // T17b — the whole day-7 flow, kept in memory (writes nothing).
          btn(
            isEn ? 'Day-7 flow (preview, not saved)' : '第 7 日問卷（預覽，唔儲存）',
            Day7FlowPage(
              parts: const [Day7Part.ada, Day7Part.open],
              adaTimepoint: PhaseAScheduleConfig.defaultAdaTimepoints.last,
              store: InMemorySurveyDraftStore(),
              uid: 'preview',
            ),
          ),
        ],
      ],
    );
  }
}

/// 10/20 (dev-tasks-1020 §H(1)) — 自己 → 我的設定: the settings that left the
/// first level.  顯示 → 高對比模式 (same switch, same stored preference as
/// before); 1020o 第三节 (decision 0066): 安靜時段 with 「由」 / 「到」 (no
/// on/off switch; replaces 10/19 第 14 条 (2) "fixed on").  Both arms.
class MySettingsPage extends StatelessWidget {
  const MySettingsPage({
    super.key,
    this.quietHoursStore = const FirestoreQuietHoursStore(),
  });

  /// Where a 安靜時段 pick is written (tests: an in-memory store).
  final QuietHoursStore quietHoursStore;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final isEn = settings.locale.languageCode == 'en';
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'My settings' : '我的設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _SectionHeader(
              icon: Icons.text_fields_rounded,
              title: isEn ? 'Display' : '顯示',
            ),
            const SizedBox(height: 14),
            _SwitchTileCard(
              key: const Key('settings_high_contrast'),
              icon: Icons.contrast_rounded,
              title: isEn ? 'High-Contrast Mode' : '高對比模式',
              subtitle: isEn
                  ? 'Stronger contrast between text and background.'
                  : '字體同背景顏色對比更加清楚。',
              value: settings.highContrast,
              onChanged: (value) => settings.highContrast = value,
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.bedtime_outlined,
              title: isEn ? 'Quiet hours' : '安靜時段',
            ),
            const SizedBox(height: 14),
            QuietHoursCard(store: quietHoursStore),
          ],
        ),
      ),
    );
  }
}

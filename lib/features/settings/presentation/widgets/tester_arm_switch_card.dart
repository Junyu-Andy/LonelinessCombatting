/// 測試員工具 → 「切換組別（只限測試員帳號）」.
///
/// Shown only when the tester tools are unlocked (TesterGate PIN) AND the
/// signed-in account is a tester (`isTester`) — the settings page checks
/// both before building this.  Tester / researcher text only; elders never
/// see it.
///
/// Pressing a button calls `setTesterArm` (via [TesterArmBackend]), then
/// re-reads the profile through [AuthService.reloadProfile] and puts it in
/// [AppSettings], so [Arm.of] and every [ArmGate] in the App switch at
/// once.  A failure shows the reason under the buttons.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/tester_arm_switch.dart';

class TesterArmSwitchCard extends StatefulWidget {
  const TesterArmSwitchCard({super.key, required this.backend});

  final TesterArmBackend backend;

  @override
  State<TesterArmSwitchCard> createState() => _TesterArmSwitchCardState();
}

class _TesterArmSwitchCardState extends State<TesterArmSwitchCard> {
  bool _busy = false;
  String? _error;

  static String _label(ArmAssignment? arm) => switch (arm) {
        ArmAssignment.a => 'Hybrid 組',
        ArmAssignment.b => '規則組',
        null => '未分組（App 顯示規則組）',
      };

  Future<void> _switch(ArmAssignment target) async {
    final settings = AppSettingsScope.read(context);
    final auth = AuthServiceScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.setArm(target.code);
      final fresh = await auth.reloadProfile();
      if (fresh == null) {
        throw const TesterArmException('已切換，但重新讀取帳號資料失敗，請重開 App。');
      }
      settings.profile = fresh;
    } on TesterArmException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } catch (e) {
      if (mounted) setState(() => _error = '切換失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final stored = profile?.arm;
    final shown = Arm.of(context);
    final flagOn = RemoteFeatureFlags.current.testerArmSwitchEnabled;
    final enabled = flagOn && !_busy && profile != null;
    final notes = <String>[
      if (!flagOn) '伺服器開關 testerArmSwitchEnabled 未開，暫時切換唔到。',
      if (!FeatureFlags.phaseB)
        '呢個係 Phase A 包：App 一律顯示 Hybrid 組；伺服器仍然按組別放行或拒絕 AI。',
      if (shown != stored && FeatureFlags.phaseB)
        '呢個包帶咗 FORCE_ARM，App 而家顯示：${_label(shown)}。',
    ];
    return Card(
      key: const Key('tester_arm_switch'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('切換組別（只限測試員帳號）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('而家：${_label(stored)}',
                key: const Key('tester_arm_current'),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '切去 Hybrid 組會開埋跨次記憶；切去規則組唔會刪記憶，切返嚟仲喺度。'
              '只影響呢個測試員帳號，唔計入研究數據。',
              style: theme.textTheme.bodyMedium,
            ),
            for (final n in notes) ...[
              const SizedBox(height: 4),
              Text(n, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ArmButton(
                    key: const Key('tester_arm_a'),
                    label: 'Hybrid 組',
                    selected: stored == ArmAssignment.a,
                    onPressed: enabled && stored != ArmAssignment.a
                        ? () => _switch(ArmAssignment.a)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ArmButton(
                    key: const Key('tester_arm_b'),
                    label: '規則組',
                    selected: stored == ArmAssignment.b,
                    onPressed: enabled && stored != ArmAssignment.b
                        ? () => _switch(ArmAssignment.b)
                        : null,
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('tester_arm_error'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArmButton extends StatelessWidget {
  const _ArmButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    return selected
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

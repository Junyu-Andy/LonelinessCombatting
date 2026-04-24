import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../follow_up/presentation/widgets/follow_up_section.dart';

/// "了解你" — the user's personalised hub. Combines:
///   • profile (name, age, emergency contact, language) with inline edits
///   • a glance at the most recent check-in
///   • the follow-up content (reminders, progress, pace, celebrations)
///
/// In guest mode (no signed-in profile) the profile section becomes a
/// gentle prompt to sign in instead of an editor.
class PersonalizationPage extends StatelessWidget {
  const PersonalizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final profile = settings.profile;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              Icon(Icons.person_pin_circle_outlined,
                  size: 30, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.contextTab,
                    style: theme.textTheme.headlineMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(l10n.contextSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 20),
          if (profile == null)
            const _SignedOutProfileCard()
          else
            _ProfileCard(profile: profile),
          const SizedBox(height: 18),
          const _RecentCheckInCard(
            mood: 3,
            loneliness: 4,
            socialEnergy: 2,
          ),
          const SizedBox(height: 18),
          const FollowUpSection(),
        ],
      ),
    );
  }
}

class _SignedOutProfileCard extends StatelessWidget {
  const _SignedOutProfileCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('未登入', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '登入之後，呢度會記住你嘅資料同跟進節奏，跨裝置都搵得返。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserProfile profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emergencyText = profile.emergencyContactName == null
        ? '未設定'
        : profile.emergencyContactPhone != null
            ? '${profile.emergencyContactName} (${profile.emergencyContactPhone})'
            : profile.emergencyContactName!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.person,
                      size: 30, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName,
                          style: theme.textTheme.titleLarge),
                      Text(profile.email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.cake_outlined,
              label: '年齡組別',
              value: profile.ageGroup ?? '未填',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.favorite_outline,
              label: '緊急聯絡',
              value: emergencyText,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.translate_rounded,
              label: '預設語言',
              value: profile.preferredLanguage == 'en' ? 'English' : '中文',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _openEditor(context, profile),
                icon: const Icon(Icons.edit_outlined, size: 22),
                label: const Text('更新我嘅資料'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _ProfileEditor(profile: profile),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text('$label：',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Expanded(
          child: Text(value,
              style: theme.textTheme.bodyLarge,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  final UserProfile profile;
  const _ProfileEditor({required this.profile});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.displayName);
  late final TextEditingController _emergencyName = TextEditingController(
      text: widget.profile.emergencyContactName ?? '');
  late final TextEditingController _emergencyPhone = TextEditingController(
      text: widget.profile.emergencyContactPhone ?? '');
  String? _ageGroup;
  bool _busy = false;
  String? _error;

  static const _ageGroups = ['60-69', '70-79', '80+', '未滿 60'];

  @override
  void initState() {
    super.initState();
    _ageGroup = widget.profile.ageGroup;
  }

  @override
  void dispose() {
    _name.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthServiceScope.of(context);
    final settings = AppSettingsScope.read(context);
    final updated = widget.profile.copyWith(
      displayName: _name.text.trim().isEmpty
          ? widget.profile.displayName
          : _name.text.trim(),
      ageGroup: _ageGroup,
      emergencyContactName: _emergencyName.text.trim().isEmpty
          ? null
          : _emergencyName.text.trim(),
      emergencyContactPhone: _emergencyPhone.text.trim().isEmpty
          ? null
          : _emergencyPhone.text.trim(),
    );
    try {
      await auth.updateProfile(updated);
      if (!mounted) return;
      settings.profile = updated;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('更新資料', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '稱呼',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          Text('年齡組別', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ageGroups.map((g) {
              final selected = g == _ageGroup;
              return ChoiceChip(
                label: Text(g),
                selected: selected,
                onSelected: (_) => setState(() => _ageGroup = g),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emergencyName,
            decoration: const InputDecoration(
              labelText: '緊急聯絡人',
              prefixIcon: Icon(Icons.favorite_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emergencyPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '聯絡電話',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

class _RecentCheckInCard extends StatelessWidget {
  final int mood;
  final int loneliness;
  final int socialEnergy;

  const _RecentCheckInCard({
    required this.mood,
    required this.loneliness,
    required this.socialEnergy,
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
            Row(
              children: [
                Icon(Icons.timeline_rounded,
                    size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('最近狀態', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            _StatBar(label: '心情', value: mood),
            const SizedBox(height: 8),
            _StatBar(label: '孤獨感', value: loneliness),
            const SizedBox(height: 8),
            _StatBar(label: '社交能量', value: socialEnergy),
          ],
        ),
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final int value;

  const _StatBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
            width: 80,
            child: Text(label, style: theme.textTheme.bodyLarge)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value / 5),
              duration: const Duration(milliseconds: 500),
              builder: (context, t, _) => LinearProgressIndicator(
                value: t,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$value/5',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            )),
      ],
    );
  }
}

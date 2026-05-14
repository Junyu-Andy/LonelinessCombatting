import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../cognitive_restructure/data/thought_record.dart';
import '../../data/action_plan.dart';

/// M7 — Action Loop, Arm B (rule-based).
///
/// Spec §M7 Arm B flow:
///   1. Fixed form: dropdowns for time-of-day, place, contact, and one
///      of three fallback options.
///   2. Plan saved.
///
/// No LLM. Same persistence target as Arm A (`action_plans/`).
///
/// [seedAction] lets caller modules (M4 hand-off, M6 acceptance) pre-fill
/// the action field.
/// [linkedThoughtRecordId] lets M4 record the cross-link.
class ActionLoopArmBPage extends StatefulWidget {
  final String? seedAction;
  final String? linkedThoughtRecordId;
  const ActionLoopArmBPage({
    super.key,
    this.seedAction,
    this.linkedThoughtRecordId,
  });

  @override
  State<ActionLoopArmBPage> createState() => _ActionLoopArmBPageState();
}

class _ActionLoopArmBPageState extends State<ActionLoopArmBPage> {
  final _actionCtrl = TextEditingController();
  String? _timeOfDay;
  String? _place;
  String? _contact;
  String? _fallback;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.seedAction != null && widget.seedAction!.trim().isNotEmpty) {
      _actionCtrl.text = widget.seedAction!.trim();
    }
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    super.dispose();
  }

  bool get _isComplete =>
      _actionCtrl.text.trim().isNotEmpty &&
      _timeOfDay != null &&
      _place != null &&
      _contact != null &&
      _fallback != null;

  Future<void> _save() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    setState(() => _busy = true);
    if (profile != null) {
      final repo = ActionPlanRepository(available: auth.available);
      final planId = await repo.create(
        profile.uid,
        ActionPlan(
          action: _actionCtrl.text.trim(),
          whenText: _timeOfDay ?? '',
          whereText: _place ?? '',
          whoWith: _contact ?? '',
          fallback: _fallback ?? '',
          armCode: 'B',
          createdAt: DateTime.now(),
        ),
      );
      final linkId = widget.linkedThoughtRecordId;
      if (planId != null && linkId != null) {
        final trRepo = ThoughtRecordRepository(available: auth.available);
        await trRepo.linkActionPlan(profile.uid, linkId, planId);
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final times = isEn
        ? const ['Morning', 'Afternoon', 'Evening']
        : const ['上晝', '下晝', '晚上'];
    final places = isEn
        ? const ['At home', 'Outdoors', 'Somewhere else']
        : const ['屋企', '出街', '其他地方'];
    final contacts = isEn
        ? const ['Family', 'A friend', 'Alone']
        : const ['屋企人', '朋友', '一個人'];
    final fallbacks = isEn
        ? const [
            'Try again later in the day',
            'Try again tomorrow',
            'Let it go for this time',
          ]
        : const [
            '今日遲啲再試',
            '聽日再試',
            '今次算',
          ];

    return Scaffold(
      appBar: AppBar(
          title: Text(isEn ? 'Plan a small step' : '計劃一個小行動')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              isEn
                  ? 'Pick the pieces of your plan.'
                  : '揀返你個計劃嘅資料。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            _Label(text: isEn ? 'What' : '做咩'),
            const SizedBox(height: 6),
            TextField(
              controller: _actionCtrl,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: isEn ? 'e.g. Call my sister' : '例：打電話畀家姐',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'When' : '幾時'),
            _ChipPicker(
              options: times,
              selected: _timeOfDay,
              onChanged: (v) => setState(() => _timeOfDay = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'Where' : '邊度'),
            _ChipPicker(
              options: places,
              selected: _place,
              onChanged: (v) => setState(() => _place = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'Who' : '同邊個'),
            _ChipPicker(
              options: contacts,
              selected: _contact,
              onChanged: (v) => setState(() => _contact = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'If it doesn\'t work out' : '如果唔成功'),
            _ChipPicker(
              options: fallbacks,
              selected: _fallback,
              onChanged: (v) => setState(() => _fallback = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isComplete && !_busy ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isEn ? 'Save plan' : '儲存計劃',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _ChipPicker extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onChanged;
  const _ChipPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((o) {
          final sel = o == selected;
          return ChoiceChip(
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(o, style: const TextStyle(fontSize: 16)),
            ),
            selected: sel,
            onSelected: (_) => onChanged(o),
          );
        }).toList(),
      ),
    );
  }
}

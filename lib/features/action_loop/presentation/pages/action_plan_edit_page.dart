import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../../shared/widgets/keyboard_compact.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/action_plan.dart';
import '../../data/action_plan_copy.dart';

/// 1020e 二.7 (switch actionPlanSimplifiedEnabled): change 做咩 and 幾時 of
/// a plan that is waiting for 「件事點呀」, or delete it.
///
/// One page for both arms, word for word: no model call in either arm.
/// The new text goes through the same safety check as the planners
/// (point `action_plan`).  The reminder time does not move (it was never
/// tied to 幾時); delete is soft (see [ActionPlanRepository.softDelete]).
/// Pops `true` when something was saved or deleted.
class ActionPlanEditPage extends StatefulWidget {
  final ActionPlan plan;
  const ActionPlanEditPage({super.key, required this.plan});

  @override
  State<ActionPlanEditPage> createState() => _ActionPlanEditPageState();
}

class _ActionPlanEditPageState extends State<ActionPlanEditPage> {
  late final _actionCtrl = TextEditingController(text: widget.plan.action);
  late final _whenCtrl = TextEditingController(text: widget.plan.whenText);
  bool _busy = false;
  bool _needBoth = false;

  static const _whenQuick = ['上晝', '下晝', '晚上'];

  @override
  void dispose() {
    _actionCtrl.dispose();
    _whenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final action = _actionCtrl.text.trim();
    final when = _whenCtrl.text.trim();
    if (action.isEmpty || when.isEmpty) {
      setState(() => _needBoth = true);
      return;
    }
    final changes =
        ActionPlanEdits.changes(widget.plan, action: action, whenText: when);
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final analytics = AnalyticsScope.maybeOf(context);
    setState(() => _busy = true);
    if (profile != null) {
      final repo = ActionPlanRepository.forApp(available: auth.available);
      final fields =
          await repo.update(profile.uid, widget.plan, action: action, whenText: when);
      unawaited(analytics?.logM7PlanEdited(fields: fields));
    }
    if (!mounted) return;
    // Same order as the rule arm's planner: save, then the shared safety
    // check (its surface shows before the page closes).
    await SafetyService.of(context).checkAndRoute(
      context,
      changes.values.join('\n'),
      point: SafetyInputPoint.actionPlan,
      uid: profile?.uid,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final deleted = await confirmAndDeletePlan(context, widget.plan, from: 'edit');
    if (deleted && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: keyboardCompactAppBar(context,
          title: const Text(ActionPlanCopy.editTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(ActionPlanCopy.editWhat, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(
              key: const Key('plan_edit_action'),
              controller: _actionCtrl,
              minLines: 1,
              maxLines: 4,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) {
                if (_needBoth) setState(() => _needBoth = false);
              },
            ),
            const SizedBox(height: 18),
            Text(ActionPlanCopy.editWhen, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(
              key: const Key('plan_edit_when'),
              controller: _whenCtrl,
              minLines: 1,
              maxLines: 2,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) {
                if (_needBoth) setState(() => _needBoth = false);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in _whenQuick)
                  ActionChip(
                    key: Key('plan_edit_when_$w'),
                    label: Text(w),
                    onPressed: () => setState(() {
                      _whenCtrl.text = w;
                      _needBoth = false;
                    }),
                  ),
              ],
            ),
            if (_needBoth) ...[
              const SizedBox(height: 12),
              Text(
                ActionPlanCopy.editNeedBoth,
                key: const Key('plan_edit_need_both'),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('plan_edit_save'),
              onPressed: _busy ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(ActionPlanCopy.editSave,
                    style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              key: const Key('plan_edit_delete'),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text(ActionPlanCopy.editDelete),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ask 「刪咗呢個計劃？」; on 「刪除」 soft-delete the plan (its unsent
/// reminders go too), log `m7_plan_deleted` and say 「已經刪咗。」.
/// Returns true when it was deleted.  Same in both arms; no model call.
Future<bool> confirmAndDeletePlan(BuildContext context, ActionPlan plan,
    {required String from}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text(ActionPlanCopy.deleteConfirm),
      content: Text(plan.action,
          style: Theme.of(dialogCtx).textTheme.bodyLarge),
      actions: [
        TextButton(
          key: const Key('plan_delete_no'),
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text(ActionPlanCopy.deleteNo),
        ),
        FilledButton(
          key: const Key('plan_delete_yes'),
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text(ActionPlanCopy.deleteYes),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final profile = AppSettingsScope.read(context).profile;
  final auth = AuthServiceScope.of(context);
  final analytics = AnalyticsScope.maybeOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (profile != null) {
    await ActionPlanRepository.forApp(available: auth.available)
        .softDelete(profile.uid, plan, from: from);
    unawaited(analytics?.logM7PlanDeleted(from: from));
  }
  messenger?.showSnackBar(
      const SnackBar(content: Text(ActionPlanCopy.deleted)));
  return true;
}

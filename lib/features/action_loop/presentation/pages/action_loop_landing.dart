import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/action_plan.dart';
import 'action_loop_arm_a_page.dart';
import 'action_loop_arm_b_page.dart';
import 'action_loop_followup_page.dart';

/// M7 entry surface. Shows two things:
///   - A primary "Plan a small step" button that opens the arm-specific
///     planner.
///   - A list of pending plans (no outcome yet) so the user can mark
///     "did it happen?" — this is the follow-up loop the spec measures.
class ActionLoopLandingPage extends StatelessWidget {
  const ActionLoopLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final auth = AuthServiceScope.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final repo = ActionPlanRepository(available: auth.available);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Small steps' : '小行動'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _IntroCard(isEn: isEn),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openPlanner(context),
              icon: const Icon(Icons.add_circle_outline, size: 26),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isEn ? 'Plan a small step' : '計劃一個小行動',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isEn ? 'Waiting on follow-up' : '等住跟進',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (profile == null)
              Text(
                isEn
                    ? 'Sign in to save plans across sessions.'
                    : '登入之後，計劃可以儲存。',
                style: theme.textTheme.bodyMedium,
              )
            else
              StreamBuilder<List<ActionPlan>>(
                stream: repo.pending(profile.uid),
                builder: (_, snap) {
                  final list = snap.data ?? const <ActionPlan>[];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        isEn
                            ? 'Nothing waiting. Plan something when you\'re '
                                'ready.'
                            : '冇嘢等緊跟進。準備好就計劃一件小事啦。',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
                    children: list
                        .map((p) => _PendingPlanCard(
                              plan: p,
                              onTap: () => _openFollowUp(context, p),
                            ))
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openPlanner(BuildContext context) {
    final builder = Arm.isA(context)
        ? (_) => const ActionLoopArmAPage()
        : (BuildContext _) => const ActionLoopArmBPage();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  void _openFollowUp(BuildContext context, ActionPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActionLoopFollowUpPage(plan: plan),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final bool isEn;
  const _IntroCard({required this.isEn});

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
                Icon(Icons.checklist_rtl_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'One small step at a time' : '由一件小事開始',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'Pick one thing to try. We\'ll ask how it went next '
                      'time you open the app.'
                  : '揀一件你想試嘅小事。下次返嚟，我會問你件事點呀。',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingPlanCard extends StatelessWidget {
  final ActionPlan plan;
  final VoidCallback onTap;
  const _PendingPlanCard({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.hourglass_bottom,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.action, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${plan.whenText} · ${plan.whoWith}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  isEn ? 'How did it go?' : '點呀？',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

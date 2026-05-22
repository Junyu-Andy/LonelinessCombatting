/// Per-session 2-item PPR brief (Dev Req §11).
///
/// Delivered immediately after each reminiscence session (M3) so the
/// "how heard / how present" responsiveness reading is captured while
/// the experience is still acute. 5-point Likert.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/brief_ppr_controller.dart';
import '../../data/ppr_scale.dart';

class PprBriefPage extends StatefulWidget {
  /// Which agent the session was with — recorded so per-agent analysis
  /// is possible.
  final String agentId;

  /// What session this brief is attached to (e.g. `m3_w2`).
  final String sessionTag;

  /// B.6 — when true, the modal renders WITHOUT a 稍後 (Later) button and
  /// without a back-arrow.  Determined by the caller via
  /// [BriefPprController.isMandatoryFor].  First brief PPR per agent is
  /// mandatory; subsequent prompts are skippable.
  final bool mandatory;

  const PprBriefPage({
    super.key,
    required this.agentId,
    required this.sessionTag,
    this.mandatory = false,
  });

  @override
  State<PprBriefPage> createState() => _PprBriefPageState();
}

class _PprBriefPageState extends State<PprBriefPage> {
  final Map<String, int> _responses = {};
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    // B.6 — emit "shown" event so analysts can compute completion rate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AnalyticsScope.of(context).logPprBriefShown(
        agentId: widget.agentId,
        mandatory: widget.mandatory,
      );
    });
  }

  Future<void> _save() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = PprResponseRepository(available: auth.available);
    await repo.submit(
      profile.uid,
      PprResponse(
        agentId: widget.agentId,
        form: 'brief_after_session:${widget.sessionTag}',
        items: Map.from(_responses),
        submittedAt: DateTime.now(),
      ),
    );
    // B.6 — mark first-seen for this agent so subsequent prompts are
    // skippable.  Safe to call repeatedly — Firestore set/merge is idempotent.
    final pprController = BriefPprController(available: auth.available);
    await pprController.markSeen(uid: profile.uid, agentId: widget.agentId);
    if (mounted) {
      await AnalyticsScope.of(context)
          .logPprBriefSubmitted(agentId: widget.agentId);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    // Even on skip, mark the first-seen flag so the user isn't trapped in
    // the mandatory modal forever — they had to see it once.
    if (profile != null) {
      final pprController = BriefPprController(available: auth.available);
      await pprController.markSeen(uid: profile.uid, agentId: widget.agentId);
    }
    if (mounted) {
      await AnalyticsScope.of(context)
          .logPprBriefSkipped(agentId: widget.agentId);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool get _isComplete => _responses.length == pprBriefItems.length;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return PopScope(
      // B.6 — mandatory-first prevents back-swipe / system-back from dismissing.
      canPop: !widget.mandatory,
      child: Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Quick feedback' : '簡短回饋'),
        automaticallyImplyLeading: !widget.mandatory,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn
                      ? 'Two quick questions about the session you just had.'
                      : '兩條短問題，關於你啱啱嘅 session。',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                for (final item in pprBriefItems)
                  _LikertItem(
                    item: item,
                    value: _responses[item.id],
                    onChanged: (v) => setState(() => _responses[item.id] = v),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      !_isComplete || _saving || _saved ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _saved
                          ? (isEn ? 'Thank you' : '多謝')
                          : (isEn ? 'Submit' : '提交'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                if (!widget.mandatory) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving || _saved ? null : _skip,
                    child: Text(isEn ? 'Later' : '稍後'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _LikertItem extends StatelessWidget {
  final PprBriefItem item;
  final int? value;
  final ValueChanged<int> onChanged;
  const _LikertItem({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn ? item.promptEn : item.promptZh,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final v = i + 1;
              final selected = value == v;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onChanged(v),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        '$v',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEn ? item.lowEn : item.lowZh,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                isEn ? item.highEn : item.highZh,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

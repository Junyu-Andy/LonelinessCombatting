import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/rule_submission_flow.dart';
import '../../../rule_replies/data/rule_reply_history_store.dart';
import '../../../rule_replies/data/rule_reply_pool.dart';
import '../../../rule_replies/data/rule_reply_service.dart';
import '../../../rule_replies/presentation/rule_reply_bubble.dart';
import '../../../rule_replies/rule_reply_safety.dart';
import '../../../today/data/mood_recorder.dart';
import 'check_in_shared.dart';

/// M2 — rule-based check-in. No LLM. Six-face mood, three fixed
/// multiple-choice items, optional free-text field that is stored but
/// never sent to the model.
///
/// Decision 0023 (flag RULE_TEMPLATE_REPLIES, default off): when on, a
/// safe submission is answered with one template reply picked by mood,
/// shown in the same bubble style as Siu Yan's Arm A replies.
class CheckInArmB extends StatefulWidget {
  /// Test hook for the template-reply history; defaults to Firestore.
  final RuleReplyHistoryStore? replyHistory;

  const CheckInArmB({super.key, this.replyHistory});

  @override
  State<CheckInArmB> createState() => _CheckInArmBState();
}

class _CheckInArmBState extends State<CheckInArmB> {
  // B14-aligned: no pre-selected face — a prefilled neutral midpoint
  // anchors the mood measurement, so the user must actively pick one.
  MoodFace? _face;
  int? _talkedAnswer;
  int? _socialDayAnswer;
  int? _significantEventAnswer;
  final _noteCtrl = TextEditingController();
  bool _saved = false;
  AnalyticsService? _analytics;

  /// Decision 0023 — template reply shown after saving (flag on, safe
  /// submission only).  Null keeps the original fixed line.
  String? _ruleReply;
  bool _picking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Siu Yan' : '小欣')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              isEn ? 'How are you today?' : '你今日點呀？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            MoodFacePicker(
              value: _face,
              onChanged: (v) => setState(() => _face = v),
            ),
            const SizedBox(height: 24),
            _MultipleChoice(
              prompt: isEn
                  ? 'Did you talk with anyone today?'
                  : '今日有冇同人傾過偈？',
              options: isEn
                  ? const ['Not at all', 'A little', 'Quite a bit', 'A lot']
                  : const ['冇', '少少', '幾多', '好多'],
              selected: _talkedAnswer,
              onChanged: (v) => setState(() => _talkedAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'How would you rate your social day?'
                  : '今日嘅社交時間，你會點評價？',
              options: isEn
                  ? const ['Hard', 'So-so', 'OK', 'Good', 'Great']
                  : const ['辛苦', '麻麻', '可以', '幾好', '好好'],
              selected: _socialDayAnswer,
              onChanged: (v) => setState(() => _socialDayAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'Anything significant today?'
                  : '今日有冇咩特別事？',
              options: isEn
                  ? const ['Nothing', 'A small thing', 'Something big']
                  : const ['冇', '一啲小事', '一件大事'],
              selected: _significantEventAnswer,
              onChanged: (v) => setState(() => _significantEventAnswer = v),
            ),
            const SizedBox(height: 24),
            Text(
              isEn
                  ? 'Anything you want to write down (optional)'
                  : '想寫低啲咩都得（選擇性）',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: isEn
                    ? 'A line or two, only for you to see.'
                    : '一兩句都得，只係你睇到。',
              ),
            ),
            const SizedBox(height: 24),
            AppButton.primary(
              label: isEn ? 'Save check-in' : '儲存今日 Check-in',
              icon: Icons.check_rounded,
              onPressed: _face != null &&
                      _talkedAnswer != null &&
                      _socialDayAnswer != null &&
                      _significantEventAnswer != null &&
                      !_saved &&
                      !_picking
                  ? _save
                  : null,
            ),
            if (_saved && _ruleReply != null) ...[
              const SizedBox(height: 12),
              RuleReplyBubble(
                text: _ruleReply!,
                style: RuleReplyBubbleStyle.checkIn,
              ),
            ] else if (_saved) ...[
              const SizedBox(height: 12),
              Text(
                isEn
                    ? 'Saved. See you tomorrow.'
                    : '收到喇。聽日再見。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final face = _face;
    if (face == null) return;
    final note = _noteCtrl.text.trim();
    final core = CoreServicesScope.of(context);
    // Decision 0023 — read once so one submission never mixes paths.
    final ruleReplies = RuleReplyPool.enabled;
    final profile = AppSettingsScope.read(context).profile;
    final authAvailable = AuthServiceScope.of(context).available;
    final analytics = AnalyticsScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final nav = Navigator.of(context);
    final submittedAt = DateTime.now();
    // T7 — the shared entry point: detect + PI event (arm-invariant).
    // T8 — the classifier is asked only when its switch is on (same rule
    // as Arm A's gateway); off, this stays the synchronous check.
    const point = SafetyInputPoint.checkInNote;
    final DistressMatch distress;
    if (core.safety.classifierActiveFor(point)) {
      setState(() => _picking = true);
      distress = (await core.safety.checkUserTextClassified(note,
              point: point,
              uid: profile?.uid,
              agentId: AgentRegistry.siuYanId))
          .match;
    } else {
      distress = core.safety
          .checkUserText(note,
              point: point,
              uid: profile?.uid,
              agentId: AgentRegistry.siuYanId)
          .match;
    }

    // B04 — before this fix Arm B only fired an analytics event; the
    // answers themselves were never persisted (= lost research data).
    // Now: (1) structured responses → users/{uid}/check_in_responses,
    // (2) mood → users/{uid}/daily_mood via MoodRecorder so the home
    // hero + weekly recap reflect the check-in, (3) analytics events.
    //
    // All writes are fire-and-forget on purpose: offline, Firestore
    // futures don't fail — they wait for server ack — so awaiting them
    // would hang the Save button forever.  The SDK queues the writes
    // locally and syncs when the connection returns.
    if (profile != null) {
      unawaited(_persistResponses(profile.uid, face, note));
      unawaited(_recordMood(profile.uid, face));
    }
    unawaited(_analytics?.logCheckIn(
          mood: face.numericScore,
          // Loneliness + social energy aren't directly captured in Arm B;
          // we proxy them from the social-day rating so the analytics
          // dashboard keeps a comparable column across arms.
          loneliness:
              _socialDayAnswer == null ? 3 : (5 - (_socialDayAnswer ?? 2)),
          socialEnergy: (_socialDayAnswer ?? 2) + 1,
        ) ??
        Future<void>.value());
    // Decision 0023 — template reply only for a safe submission; a safety
    // hit keeps the original line and runs the safety flow below.
    String? ruleReply;
    if (ruleReplies && allowsTemplateReply(distress)) {
      if (mounted) setState(() => _picking = true);
      final entry = await RuleReplyService(
        store: widget.replyHistory ??
            FirestoreRuleReplyHistoryStore(available: authAvailable),
      ).next(
        uid: profile?.uid,
        agentId: AgentRegistry.siuYanId,
        moduleId: 'm2_check_in',
        theme: RuleReplyPool.themeCheckIn,
        mood: face.rank,
        analytics: analytics,
      );
      // T33 — final copy is Cantonese only; English UI shows it too.
      ruleReply = entry?.zh;
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _saved = true;
      _picking = false;
      _ruleReply = ruleReply;
    });

    // Decision 0015 — the submission is one agent session, like a chat.
    // The recorder's Firestore writes are fire-and-forget, so this never
    // blocks offline.
    final rec = await RuleSubmissionFlow.record(
      uid: profile?.uid,
      agentId: AgentRegistry.siuYanId,
      moduleId: 'm2_check_in',
      analytics: analytics,
      available: authAvailable,
      text: note,
      detector: distress,
      userSent: submittedAt,
      replyText:
          ruleReply ?? (isEn ? 'Saved. See you tomorrow.' : '收到喇。聽日再見。'),
    );
    if (!mounted) return;

    // Same safety surfaces as every other page (crisis page for acute,
    // support sheet for moderate) — arm-invariant.
    // T7 already wrote the event (checkUserText above); route only.
    if (distress.level != DistressLevel.none) {
      await core.distressRouter.route(distress, context: context);
      if (distress.level == DistressLevel.acute) return;
    }
    if (profile == null) return;
    await RuleSubmissionFlow.surfaceBriefPr(
      nav,
      rec: rec,
      uid: profile.uid,
      agentId: AgentRegistry.siuYanId,
      agentDisplayName: '小欣',
    );
  }

  Future<void> _persistResponses(
      String uid, MoodFace face, String note) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('check_in_responses')
          .add({
        'arm': 'B',
        'mood': face.numericScore,
        'talked': _talkedAnswer,
        'social_day': _socialDayAnswer,
        'significant_event': _significantEventAnswer,
        'note': note,
        'date_iso': MoodRecorder.dateIsoFor(DateTime.now()),
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Permission/format errors — analytics still captured the event.
    }
  }

  Future<void> _recordMood(String uid, MoodFace face) async {
    try {
      await MoodRecorder().record(
        uid: uid,
        mood: face.numericScore,
        arm: 'B',
        sourceSurface: 'check_in_b',
      );
    } catch (_) {}
  }
}

class _MultipleChoice extends StatelessWidget {
  final String prompt;
  final List<String> options;
  final int? selected;
  final ValueChanged<int> onChanged;
  const _MultipleChoice({
    required this.prompt,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(options.length, (i) {
                final isSel = selected == i;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Text(options[i],
                        style: const TextStyle(fontSize: 16)),
                  ),
                  selected: isSel,
                  onSelected: (_) => onChanged(i),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

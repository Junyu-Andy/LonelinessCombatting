import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/safety/safety_check.dart';
import '../../../../core/session/chat_session_recorder.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/rule_submission_flow.dart';
import '../../../context/presentation/pages/check_in_shared.dart';
import '../../../rule_replies/data/rule_reply_history_store.dart';
import '../../../rule_replies/data/rule_reply_pool.dart';
import '../../../rule_replies/data/rule_reply_service.dart';
import '../../../rule_replies/presentation/rule_reply_bubble.dart';
import '../../../rule_replies/rule_reply_safety.dart';
import '../../data/m3_session_store.dart';
import '../../data/reminiscence_themes.dart';

/// M3 — Reminiscence, Arm B (rule-based).
///
/// Spec §M3 Arm B flow:
///   1. Same themed opening prompt.
///   2. User writes or speaks into a text field.
///   3. No follow-up. End-of-session: user is shown their own text and
///      asked to save it.
///   4. Past entries are accessible as a list — the system never refers
///      back to them mid-session.
///
/// Arm B writes to the same single-doc schema as Arm A so My Story
/// timeline, memories page, and cross-module callbacks (in the arms
/// that have them) can read uniformly. Arm B has no LLM, so:
///   - turns array contains one user-only entry (consent-gated)
///   - end_summary_original = user's raw text
///   - end_summary_edited = null (user did not interact with an editor)
///   - end_summary_user_edited = false
///
/// Decision 0023 (flag RULE_TEMPLATE_REPLIES, default off): when on, an
/// optional mood picker sits under the text field and a safe submission
/// gets one template reply (mood × weekly theme) in the Arm A bubble
/// style; the page then waits for 完成 instead of closing itself.
class ReminiscenceArmBPage extends StatefulWidget {
  final ReminiscenceTheme theme;

  /// Test hook for the template-reply history; defaults to Firestore.
  final RuleReplyHistoryStore? replyHistory;

  const ReminiscenceArmBPage(
      {super.key, required this.theme, this.replyHistory});

  @override
  State<ReminiscenceArmBPage> createState() => _ReminiscenceArmBPageState();
}

class _ReminiscenceArmBPageState extends State<ReminiscenceArmBPage> {
  final _textCtrl = TextEditingController();
  final _voice = VoiceInputController();
  bool _busy = false;
  bool _saved = false;

  /// Decision 0023 — only used when [RuleReplyPool.enabled].
  final bool _ruleReplies = RuleReplyPool.enabled;
  MoodFace? _face; // optional
  String? _ruleReply;
  ChatSessionRecorder? _rec;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // B03 — stop dictation before reading the memory text.
    final (usedVoice, voiceMs) = _voice.takeModality();
    await _voice.stopForSend();
    if (!mounted) return;
    final body = _textCtrl.text.trim();
    if (body.isEmpty) return;
    final submittedAt = DateTime.now();
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final core = CoreServicesScope.of(context);
    final analytics = AnalyticsScope.of(context);
    final nav = Navigator.of(context);
    final agent = AgentRegistry.byId(AgentRegistry.ahJanAhBakId);
    final displayName =
        agent.resolveVariant(profile?.ahJanAhBakVariant).displayNameZh;
    // Decision 0023 — read once so one submission never mixes paths.
    final ruleReplies = _ruleReplies;
    // T7 — same shared safety check + PI event as Arm A (arm-invariant).
    // T8 — the classifier is asked only when its switch is on (same rule
    // as Arm A's gateway); off, this stays the synchronous check.
    const point = SafetyInputPoint.reminiscenceNote;
    final DistressMatch distress;
    if (core.safety.classifierActiveFor(point)) {
      setState(() => _busy = true);
      distress = (await core.safety.checkUserTextClassified(body,
              point: point,
              uid: profile?.uid,
              agentId: AgentRegistry.ahJanAhBakId))
          .match;
    } else {
      distress = core.safety
          .checkUserText(body,
              point: point,
              uid: profile?.uid,
              agentId: AgentRegistry.ahJanAhBakId)
          .match;
    }
    if (mounted) setState(() => _busy = true);
    if (profile != null) {
      final store = M3SessionStore(available: auth.available);
      await store.startSession(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        armCode: 'B',
      );
      await store.appendTurns(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        turns: [
          M3Turn(
            fromAssistant: false,
            text: body,
            timestamp: DateTime.now(),
          ),
        ],
        hasTranscriptConsent: profile.consent
            .transcriptRetentionFor(AgentRegistry.ahJanAhBakId),
      );
      await store.finalizeSession(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        armCode: 'B',
        endSummaryOriginal: body,
        endSummaryEdited: null,
        userEdited: false,
      );
    }
    // Decision 0023 / T33 — a safe submission gets a mood template; a
    // moderate_review hit (grief / past hardship) gets a Z5 template; any
    // other safety hit gets no reply and runs the safety flow below.
    final route = ruleReplyRoute(distress, griefTemplates: true);
    String? ruleReply;
    if (ruleReplies && route != RuleReplyRoute.none) {
      final entry = await RuleReplyService(
        store: widget.replyHistory ??
            FirestoreRuleReplyHistoryStore(available: auth.available),
      ).next(
        uid: profile?.uid,
        agentId: AgentRegistry.ahJanAhBakId,
        moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
        theme: RuleReplyPool.themeForWeek(widget.theme.weekIndex),
        mood: _face?.rank,
        grief: route == RuleReplyRoute.grief,
        analytics: analytics,
      );
      // T33 — final copy is Cantonese only; English UI shows it too.
      ruleReply = entry?.zh;
    }
    // Decision 0015 — the saved memory is one agent session, like a chat.
    final rec = await RuleSubmissionFlow.record(
      uid: profile?.uid,
      agentId: AgentRegistry.ahJanAhBakId,
      moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
      theme: widget.theme.titleZh,
      analytics: analytics,
      available: auth.available,
      text: body,
      detector: distress,
      userSent: submittedAt,
      modality: usedVoice ? InputModality.voice : InputModality.text,
      voiceDurationMs: voiceMs,
      replyText: ruleReply ?? '',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = true;
      _ruleReply = ruleReply;
      _rec = rec;
    });
    // T7 already wrote the event (checkUserText above); route only.
    if (distress.level != DistressLevel.none) {
      await core.distressRouter.route(distress, context: context);
      // Acute pushes the crisis page; leave this page under it.
      if (distress.level == DistressLevel.acute) return;
    }
    // Decision 0023 — leave the reply on screen until the user taps 完成.
    if (ruleReply != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    nav.pop();
    if (profile == null) return;
    await RuleSubmissionFlow.surfaceBriefPr(
      nav,
      rec: rec,
      uid: profile.uid,
      agentId: AgentRegistry.ahJanAhBakId,
      agentDisplayName: displayName,
    );
  }

  /// Decision 0023 — 完成 after a template reply: close, then Brief PR
  /// exactly as the auto-close path does.
  Future<void> _finish() async {
    final nav = Navigator.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final agent = AgentRegistry.byId(AgentRegistry.ahJanAhBakId);
    final displayName =
        agent.resolveVariant(profile?.ahJanAhBakVariant).displayNameZh;
    final rec = _rec;
    nav.pop();
    if (profile == null || rec == null) return;
    await RuleSubmissionFlow.surfaceBriefPr(
      nav,
      rec: rec,
      uid: profile.uid,
      agentId: AgentRegistry.ahJanAhBakId,
      agentDisplayName: displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.theme.titleEn : widget.theme.titleZh;
    final opening =
        isEn ? widget.theme.openingEn : widget.theme.openingZh;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(opening, style: theme.textTheme.bodyLarge),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: VoiceInputButton(
                  controller: _voice,
                  prefix: () => _textCtrl.text,
                  onText: (t) => _textCtrl.text = t,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  maxLines: null,
                  expands: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: isEn
                        ? 'Write whatever you remember, or tap the mic to speak.'
                        : '記得幾多寫幾多，或者撳咪用講嘅。',
                    alignLabelWithHint: true,
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              if (_ruleReplies && _ruleReply != null) ...[
                const SizedBox(height: 12),
                RuleReplyBubble(
                  text: _ruleReply!,
                  style: RuleReplyBubbleStyle.reminiscence,
                ),
              ] else if (_ruleReplies && !_saved) ...[
                const SizedBox(height: 12),
                // Placeholder copy — final wording from the research team
                // (decision 0023; draft in the T15 report).
                Text(
                  isEn
                      ? '[PLACEHOLDER] How do you feel now? (optional)'
                      : '【占位】你而家心情點？（可以唔揀）',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                MoodFacePicker(
                  value: _face,
                  onChanged: (v) => setState(() => _face = v),
                ),
              ],
              const SizedBox(height: 16),
              if (_ruleReplies && _ruleReply != null)
                FilledButton(
                  onPressed: _finish,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Done' : '完成',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                )
              else
                FilledButton(
                  onPressed: _busy || _saved ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _saved
                          ? (isEn ? 'Saved' : '已儲存')
                          : (isEn ? 'Save this memory' : '儲存呢段回憶'),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

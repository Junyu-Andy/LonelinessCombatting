/// T17b (SPEC:C22, decision 0030) — pieces every ADA / day-7 screen
/// shares (docs/spec/instruments/ada.md §6.2, §6.4, §6.5):
///   * [AdaAgentLabel] — companion name with its avatar;
///   * [SurveyHelpButton] — 「唔識填？打俾研究員」, number from config;
///   * [SurveyPartHeader] — 「第 N 部分，共 M 部分」 in the day-7 flow.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/agents/agent_registry.dart';
import '../../../core/config/phase_a_schedule_config.dart';
import '../data/ada_items.dart';

/// Name shown for [agentId].  Ah Jan / Ah Bak follows the participant's
/// pairing; with no pairing on file both names show.
String adaAgentName(String agentId, AgentGenderVariant? variant,
    {required bool isEn, bool forOption = false}) {
  switch (agentId) {
    case AdaAgents.siuYan:
      return isEn ? 'Siu Yan' : '小欣';
    case AdaAgents.tungTung:
      return isEn ? 'Tung Tung' : '通通';
    case AdaAgents.ahJanAhBak:
      if (variant == null) {
        // ada.md §3 C options read 「阿珍（或阿伯）」.
        return isEn
            ? 'Ah Jan (or Ah Bak)'
            : (forOption ? '阿珍（或阿伯）' : '阿珍／阿伯');
      }
      return AgentRegistry.ahJanAhBakName(variant, isEn: isEn);
  }
  return agentId;
}

/// Existing avatar asset for [agentId] (assets/agents/*_avatar.png).
/// Unknown pairing → Ah Jan's picture is not guessed: a neutral icon.
String? adaAgentAvatar(String agentId, AgentGenderVariant? variant) {
  final def = AgentRegistry.tryById(agentId);
  if (def == null) return null;
  if (agentId == AdaAgents.ahJanAhBak && variant == null) return null;
  for (final v in def.variants) {
    if (v.variant == null || v.variant == variant) return v.avatarAsset;
  }
  return null;
}

class AdaAgentAvatar extends StatelessWidget {
  const AdaAgentAvatar(
      {super.key, required this.agentId, this.variant, this.size = 44});
  final String agentId;
  final AgentGenderVariant? variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = adaAgentAvatar(agentId, variant);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      key: ValueKey('ada_avatar_$agentId'),
      width: size,
      height: size,
      child: ClipOval(
        child: asset == null
            ? Container(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.person, size: size * 0.6, color: cs.outline),
              )
            : Image.asset(
                asset,
                key: ValueKey('ada_avatar_asset_$asset'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.person, size: size * 0.6),
                ),
              ),
      ),
    );
  }
}

/// Avatar + name in one row (row headers in A and B).
class AdaAgentLabel extends StatelessWidget {
  const AdaAgentLabel(
      {super.key, required this.agentId, this.variant, required this.isEn});
  final String agentId;
  final AgentGenderVariant? variant;
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AdaAgentAvatar(agentId: agentId, variant: variant),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            adaAgentName(agentId, variant, isEn: isEn),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// ada.md §6.5 — on every screen.  The number comes from
/// `app_config/phaseA_schedule.adaHelpPhone`; nothing is hard-coded.
/// With no number configured the button stays (so the screen looks the
/// same) and says a researcher will call — it never dials a guess.
class SurveyHelpButton extends StatelessWidget {
  const SurveyHelpButton({super.key, required this.isEn, this.phone});

  final bool isEn;

  /// Test hook; defaults to the config value.
  final String? phone;

  String get _number => phone ?? PhaseAScheduleConfig.current.adaHelpPhone;

  Future<void> _onTap(BuildContext context) async {
    final number = _number.trim();
    if (number.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('survey_help_no_number'),
          content: Text(
            // Draft (research team to finalise).
            isEn
                ? 'You can tap "Skip" for now. A researcher will call you '
                    'to help.'
                : '唔緊要，可以先撳「跳過」。研究員之後會打電話俾你，幫你一齊填。',
            style: const TextStyle(fontSize: 18, height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isEn ? 'OK' : '知道'),
            ),
          ],
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri);
    } catch (_) {
      // No dialler (web / tablet): show the number so they can call.
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(number, style: const TextStyle(fontSize: 24)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isEn ? 'OK' : '知道'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('survey_help'),
      onPressed: () => _onTap(context),
      icon: const Icon(Icons.phone_in_talk_outlined, size: 22),
      label: Text(
        isEn ? 'Not sure? Call a researcher' : '唔識填？打俾研究員',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Top strip of every survey screen: part (day-7 flow only), page
/// progress and the help button.
class SurveyTopBar extends StatelessWidget {
  const SurveyTopBar({
    super.key,
    required this.isEn,
    required this.progress,
    this.part,
    this.progressKey,
  });

  final bool isEn;
  final String progress;

  /// (n, m) → 「第 n 部分，共 m 部分」.
  final (int, int)? part;
  final Key? progressKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = part;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p != null)
            Text(
              isEn
                  ? 'Part ${p.$1} of ${p.$2}'
                  : '第 ${p.$1} 部分，共 ${p.$2} 部分',
              key: const ValueKey('survey_part'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  progress,
                  key: progressKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SurveyHelpButton(isEn: isEn),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phone-by-staff answers that hit the safety lexicon: the server has
/// written the safety event (same path as the App's, so acute → PI
/// alert); the researcher on the call is told to follow the study's
/// safety protocol.  Draft wording.
Future<void> showStaffSafetyNotice(BuildContext context,
    {required bool isEn}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('staff_safety_notice'),
      title: Text(isEn ? 'Safety check' : '安全檢測'),
      content: Text(
        isEn
            ? 'This answer matched the safety word list. A safety event has '
                'been recorded. Please follow the study safety protocol now.'
            : '呢段回答觸發咗安全檢測，已經記錄安全事件。請即刻按研究嘅安全流程跟進。',
        style: const TextStyle(fontSize: 17, height: 1.5),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(isEn ? 'OK' : '知道'),
        ),
      ],
    ),
  );
}

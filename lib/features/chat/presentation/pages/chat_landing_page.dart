import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/chat_models.dart';
import '../widgets/persona_avatar.dart';
import 'chat_page.dart';

/// Two big tappable cards — pick a persona to chat with. Casual on the
/// left, "consult" mode on the right.
class ChatLandingPage extends StatelessWidget {
  const ChatLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              Icon(Icons.forum_rounded,
                  size: 30, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.chatTab,
                    style: theme.textTheme.headlineMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.chatSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _PersonaCard(persona: ChatPersona.casual),
          const SizedBox(height: 16),
          _PersonaCard(persona: ChatPersona.consult),
          const SizedBox(height: 18),
          _DisclaimerCard(),
        ],
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final ChatPersona persona;

  const _PersonaCard({required this.persona});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final spec = personaVisual(persona);
    final description = switch (persona) {
      ChatPersona.casual => isEn
          ? 'Daily chit-chat, venting, sharing.\nLight and pressure-free.'
          : '日常嘅吹水、抒發、分享。\n短短幾句，輕鬆無壓力。',
      ChatPersona.consult => isEn
          ? 'Reflect on feelings and organise your thoughts.\nCalm, steady, step by step.'
          : '想認真傾下感受、整理諗法。\n語調穩重，一步一步嚟。',
      _ => '',
    };
    return Material(
      color: spec.bubbleColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 360),
              reverseTransitionDuration: const Duration(milliseconds: 240),
              pageBuilder: (_, animation, __) => FadeTransition(
                opacity: animation,
                child: ChatPage(persona: persona),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonaAvatar(persona: persona, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: spec.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(spec.tagline, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.brown.shade800,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: spec.accent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade700, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 22, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEn
                  ? 'Both companions are AI assistants.\nIf you feel persistently low or in crisis, please contact family or call 999.'
                  : '兩個對話對象都係 AI 助手。\n如果情緒持續低落或有危機，請聯絡屋企人或撥 999。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.brown.shade900,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-turn self-introduction overlay (Dev Req §3.3).
///
/// Drop this widget at the root of any agent's conversation surface
/// (M2 check-in, M3 reminiscence, Tung Tung chat). On first build it
/// checks `profile.firstIntroSeen[agent.id]`; if missing, it shows a
/// dismissable card with the agent's intro line and (on dismiss) writes
/// the timestamp through [FirstIntroHandler.markShown].
///
/// The widget is transparent (passes [child] through unchanged) once
/// the intro has been shown or when running in guest mode.
library;

import 'package:flutter/material.dart';

import '../../app/app_settings_scope.dart';
import '../../features/auth/presentation/auth_service_scope.dart';
import 'agent_avatar.dart';
import 'agent_registry.dart';
import 'first_intro_handler.dart';

class FirstIntroOverlay extends StatefulWidget {
  final String agentId;
  final Widget child;

  const FirstIntroOverlay({
    super.key,
    required this.agentId,
    required this.child,
  });

  @override
  State<FirstIntroOverlay> createState() => _FirstIntroOverlayState();
}

class _FirstIntroOverlayState extends State<FirstIntroOverlay> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted) return;
    final profile = AppSettingsScope.read(context).profile;
    final agent = AgentRegistry.tryById(widget.agentId);
    if (profile == null || agent == null) return;
    final handler = FirstIntroHandler(
      authService: AuthServiceScope.of(context),
    );
    if (!handler.shouldShowFor(profile: profile, agent: agent)) return;

    final localeCode = Localizations.localeOf(context).languageCode;
    final introText = handler.introTextFor(
      agent: agent,
      localeCode: localeCode,
    );

    // 10/19 field test: a participant who chose 阿伯 saw 阿珍's name and
    // face here.  The chosen pairing drives the name, the avatar and the
    // 「阿珍／阿伯」 in the intro line.
    final variant = profile.ahJanAhBakVariant;
    final text = agent.id == AgentRegistry.ahJanAhBakId && variant != null
        ? introText
            .replaceAll('阿珍／阿伯',
                AgentRegistry.ahJanAhBakName(variant))
            .replaceAll('Ah Jan / Ah Bak',
                AgentRegistry.ahJanAhBakName(variant, isEn: true))
        : introText;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return _IntroDialog(agent: agent, text: text, variant: variant);
      },
    );

    if (!mounted) return;
    final updated = await handler.markShown(profile: profile, agent: agent);
    if (!mounted) return;
    AppSettingsScope.read(context).profile = updated;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _IntroDialog extends StatelessWidget {
  final AgentDefinition agent;
  final String text;
  final AgentGenderVariant? variant;
  const _IntroDialog(
      {required this.agent, required this.text, required this.variant});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final shown = agent.resolveVariant(variant);
    // 10/19 field test: at a large font the card grew past the screen and
    // 好，開始 landed off the bottom.  The card is capped at 80% of the
    // screen; the intro text scrolls inside it, the button stays put.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentAvatar(agent: agent, selectedVariant: variant, size: 84),
              const SizedBox(height: 12),
              Text(
                isEn ? shown.displayNameEn : shown.displayNameZh,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: agent.accentColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isEn ? agent.tileSubtitleEn : agent.tileSubtitleZh,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: agent.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('first_intro_start'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'OK, let\'s begin' : '好，開始',
                      style: const TextStyle(fontSize: 17),
                    ),
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

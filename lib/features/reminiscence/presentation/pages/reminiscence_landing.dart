import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/config/usage_copy.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import '../../data/reminiscence_themes.dart';
import '../../data/reminiscence_v2_copy.dart';
import '../../data/reminiscence_v2_models.dart';
import '../../data/reminiscence_v2_store.dart';
import '../reminiscence_router.dart';
import 'reminiscence_chapters_page.dart';
import 'reminiscence_memories_page.dart';

/// M3 entry point. Lists the [ReminiscenceTheme.totalWeeks] weekly themes
/// with a "completed" check per week. Same UI in both arms — only the
/// session experience that opens differs.
///
/// 10/21 (decisions-log 132, 133 (4); both arms), from the v2 week doc
/// only — the old M3 session doc no longer counts:
///   - never entered (or nothing handled yet): no icon on the right;
///   - at least one question answered or 「唔想講」, not finished:
///     「講咗 n／8 條」 under its line, no icon;
///   - all eight handled and 「完成今個禮拜」 pressed: the green check.
///
/// 1020d (switch `reminiscenceV2Enabled`): the weeks open the v2 page,
/// 「我嘅回憶」 becomes 「我嘅人生小篇章」, and a week whose new chapter is
/// ready but not yet saved shows 「第 N 章整理好喇」 under its title.
///
/// 1020o 第四节 (no switch, both arms): the chosen companion's picture
/// with a speech bubble on top (replaces the S3 line); each theme card
/// has a picture tile (`assets/reminiscence/theme_N.png`, the number tile
/// while the picture is missing) and one line on what the theme is about
/// (replaces 「第 N 週」).  The Hybrid-only 「反思傾偈」 entry moved here
/// from the deleted My Story page (decision 0006: not for the rule arm).
class ReminiscenceLandingPage extends StatelessWidget {
  const ReminiscenceLandingPage({super.key});

  static const _weeks = ReminiscenceTheme.totalWeeks;

  /// The bubble text: `app_config/usage_copy.reminiscence_landing_intro_*`
  /// if set (it replaces the whole sentence), else the 1020o default.
  /// `{name}` (阿珍 / 阿伯 by the pairing) and `{weeks}` (theme count) are
  /// filled in either way.
  static String introText(AgentGenderVariant? variant, {required bool isEn}) =>
      UsageCopy.current
          .text(
            UsageCopy.reminiscenceLandingIntro,
            isEn: isEn,
            fallback: isEn
                ? ReminiscenceV2Copy.landingIntroEn
                : ReminiscenceV2Copy.landingIntro,
          )
          .replaceAll('{name}', AgentRegistry.ahJanAhBakName(variant, isEn: isEn))
          .replaceAll('{weeks}', '$_weeks');

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.of(context).profile;
    final auth = AuthServiceScope.of(context);
    final v2 = ReminiscenceRouter.v2;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Life stories' : '人生點滴'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _CompanionIntro(
              variant: profile?.ahJanAhBakVariant,
              text: introText(profile?.ahJanAhBakVariant, isEn: isEn),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: Key(v2 ? 'reminiscence_chapters_entry' : 'reminiscence_memories_entry'),
              onPressed: () => v2 ? _openChapters(context) : _openMemories(context),
              icon: Icon(v2
                  ? Icons.auto_stories_outlined
                  : Icons.collections_bookmark_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  v2
                      ? ReminiscenceV2Copy.chaptersPageTitle
                      : (isEn ? 'My memories' : '我嘅回憶'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final t in ReminiscenceTheme.all)
              _ThemeCard(
                theme: t,
                onOpen: () => _open(context, t),
                progressStream: _progressStream(
                    auth, profile?.uid, t.weekIndex,
                    arm: Arm.isA(context) ? 'A' : 'B'),
                readyStream: v2 && profile != null
                    ? _readyStream(auth, profile.uid, t.weekIndex)
                    : null,
              ),
            // Open-ended reflective chat is LLM-only; Arm B has no
            // rule-based version of it, so the entry isn't shown there.
            if (Arm.isA(context)) ...[
              const SizedBox(height: 4),
              const _ReflectiveChatEntry(),
            ],
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, ReminiscenceTheme theme) {
    // The canonical Arm.isA lookup (FORCE_ARM applies) lives in the router;
    // 1020d: the v2 page when `reminiscenceV2Enabled`.
    final page = ReminiscenceRouter.pageFor(context, theme);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openChapters(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReminiscenceChaptersPage(),
      ),
    );
  }

  /// 1020d — 「第 N 章整理好喇」: the chapter is ready and the elder has not
  /// pressed 儲存 on it yet (a new version after 重新整理 shows it again).
  Stream<bool> _readyStream(AuthService auth, String uid, int weekIndex) =>
      ReminiscenceV2Stores.chapters(available: auth.available)
          .watch(uid, weekIndex)
          .map((ReminiscenceChapterDoc? d) =>
              d != null && d.isReady && d.savedAt == null);

  void _openMemories(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReminiscenceMemoriesPage(),
      ),
    );
  }

  /// 10/21 (decisions-log 131 (3)): from `users/{uid}/reminiscence_v2/
  /// week_N` only.  Null: not started (or no account).
  Stream<ReminiscenceWeekProgress?> _progressStream(
      AuthService auth, String? uid, int weekIndex,
      {required String arm}) {
    if (uid == null) {
      // 1020o: a card scrolled out of the list and back listens again, so
      // this must allow more than one listener (Stream.value does not).
      return Stream<ReminiscenceWeekProgress?>.multi((sink) {
        sink.add(null);
        sink.close();
      });
    }
    return ReminiscenceV2Stores.week(available: auth.available)
        .watch(uid, weekIndex, arm: arm)
        .map(ReminiscenceWeekProgress.of);
  }
}

class _ThemeCard extends StatelessWidget {
  final ReminiscenceTheme theme;
  final VoidCallback onOpen;
  final Stream<ReminiscenceWeekProgress?> progressStream;
  final Stream<bool>? readyStream;

  const _ThemeCard({
    required this.theme,
    required this.onOpen,
    required this.progressStream,
    this.readyStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReminiscenceWeekProgress?>(
      stream: progressStream,
      builder: (context, snap) => _card(context, snap.data),
    );
  }

  Widget _card(BuildContext context, ReminiscenceWeekProgress? progress) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final t = Theme.of(context);
    final done = progress != null && progress.finished;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _ThemeArt(weekIndex: theme.weekIndex),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn ? theme.titleEn : theme.titleZh,
                        style: t.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      // 1020o: what the theme is about (was 「第 N 週」).
                      Text(
                        (isEn
                                ? ReminiscenceV2Copy.themeLinesEn
                                : ReminiscenceV2Copy.themeLines)[
                            theme.weekIndex]!,
                        key: ValueKey(
                            'reminiscence_landing_line_${theme.weekIndex}'),
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      // 10/21: at least one handled, not finished.
                      if (progress != null && !done && progress.handled > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            isEn
                                ? ReminiscenceV2Copy.weekProgressEn(
                                    progress.handled)
                                : ReminiscenceV2Copy.weekProgress(
                                    progress.handled),
                            key: ValueKey(
                                'reminiscence_landing_progress_${theme.weekIndex}'),
                            style: t.textTheme.bodyMedium?.copyWith(
                              color: t.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (readyStream != null)
                        StreamBuilder<bool>(
                          stream: readyStream,
                          builder: (_, snap) => snap.data == true
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    ReminiscenceV2Copy.chapterReady(
                                        theme.weekIndex),
                                    key: ValueKey(
                                        'reminiscence_landing_ready_${theme.weekIndex}'),
                                    style: t.textTheme.bodyMedium?.copyWith(
                                      color: t.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
                if (done)
                  Icon(
                    Icons.check_circle_rounded,
                    key: ValueKey(
                        'reminiscence_landing_done_${theme.weekIndex}'),
                    size: 28,
                    color: Colors.green,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1020o 第四节 (1): the chosen companion (阿珍 or 阿伯) with a speech
/// bubble.  The picture follows the pairing; if it cannot load, that
/// companion's own initial (伯 / 珍).
class _CompanionIntro extends StatelessWidget {
  const _CompanionIntro({required this.variant, required this.text});
  final AgentGenderVariant? variant;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgentAvatar(
          key: const Key('reminiscence_landing_avatar'),
          agent: AgentRegistry.byId(AgentRegistry.ahJanAhBakId),
          selectedVariant: variant,
          size: 56,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(
              text,
              key: const Key('reminiscence_landing_intro'),
              style: t.textTheme.bodyLarge?.copyWith(
                color: cs.onSecondaryContainer,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 1020o 第四节 (3): the theme picture on a rounded tile coloured like the
/// 做啲嘢 cards (`MeToolCard`).  Pictures: `assets/reminiscence/theme_N.png`
/// (N = the theme's week index).  While a picture is missing, the old
/// number tile.
class _ThemeArt extends StatelessWidget {
  const _ThemeArt({required this.weekIndex});
  final int weekIndex;

  static const double size = 72;

  /// Same pastel tiles as 做啲嘢 (`MeToolArt`).
  static const _tileColors = <int, Color>{
    1: Color(0xFFFCEEE0),
    2: Color(0xFFE3F4EC),
    3: Color(0xFFEFE9F8),
    4: Color(0xFFFBE9E4),
  };

  static String asset(int weekIndex) =>
      'assets/reminiscence/theme_$weekIndex.png';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        asset(weekIndex),
        key: ValueKey('reminiscence_landing_art_$weekIndex'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        frameBuilder: (_, child, __, ___) => Container(
          padding: const EdgeInsets.all(size * 0.08),
          decoration: BoxDecoration(
            color: _tileColors[weekIndex] ?? cs.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        ),
        // No picture yet (or a broken one): the number tile.
        errorBuilder: (_, __, ___) => Container(
          key: ValueKey('reminiscence_landing_number_$weekIndex'),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            '$weekIndex',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Open-ended reflective chat entry (Hybrid only).  Moved unchanged from
/// the old My Story page (deleted 1020o), which was its only entry apart
/// from the cross-referral hand-over.
class _ReflectiveChatEntry extends StatelessWidget {
  const _ReflectiveChatEntry();

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      key: const Key('reminiscence_landing_reflective_chat'),
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ReflectiveDialoguePage(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 28,
                  color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn ? 'Reflective chat' : '反思傾偈',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEn
                          ? 'Open-ended chat — not part of the weekly curriculum.'
                          : '隨意傾偈，唔屬於今週嘅 session。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

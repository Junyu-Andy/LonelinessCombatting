import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/config/usage_copy.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/reminiscence_themes.dart';
import '../../data/reminiscence_v2_copy.dart';
import '../../data/reminiscence_v2_models.dart';
import '../../data/reminiscence_v2_store.dart';
import '../reminiscence_router.dart';
import 'reminiscence_chapters_page.dart';
import 'reminiscence_memories_page.dart';

/// M3 entry point. Lists the [ReminiscenceTheme.totalWeeks] weekly themes
/// with a "completed" check per week (any saved entry for that theme counts). Same UI in both
/// arms — only the session experience that opens differs.
///
/// 1020d (switch `reminiscenceV2Enabled`): the weeks open the v2 page,
/// 「我嘅回憶」 becomes 「我嘅人生小篇章」, and a week whose new chapter is
/// ready but not yet saved shows 「第 N 章整理好喇」 under its title.
class ReminiscenceLandingPage extends StatelessWidget {
  const ReminiscenceLandingPage({super.key});

  static const _weeks = ReminiscenceTheme.totalWeeks;

  /// T33 — S3 (`docs/spec/copy/short-texts.md`): only the count sentence
  /// changes; the rest of the line is the T13 text.
  static String s3(int weeks) => '一共 $weeks 個主題，每個禮拜一個。';

  /// The Chinese intro shown when `app_config/usage_copy` has no override.
  static String introZh(int weeks) =>
      '每星期一節，15-25 分鐘。${s3(weeks)}冇標準答案，記得幾多都得。';

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
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
            // SPEC:C06 — the count follows the real theme list (4), not a
            // hard-coded 6.  T33: the count sentence is S3 (final copy).
            // T20: `app_config/usage_copy` may replace this line; `{weeks}`
            // in the configured text becomes the theme count.
            Text(
              UsageCopy.current
                  .text(
                    UsageCopy.reminiscenceLandingIntro,
                    isEn: isEn,
                    fallback: isEn
                        ? 'A weekly 15–25 minute session. $_weeks themes across '
                            '$_weeks weeks. There\'s no right answer — just what '
                            'you remember.'
                        : introZh(_weeks),
                  )
                  .replaceAll('{weeks}', '$_weeks'),
              style: theme.textTheme.bodyLarge,
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
                completedStream:
                    _completedStream(auth, profile?.uid, t.weekIndex),
                readyStream: v2 && profile != null
                    ? _readyStream(auth, profile.uid, t.weekIndex)
                    : null,
              ),
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

  Stream<bool> _completedStream(
      AuthService auth, String? uid, int weekIndex) {
    if (!auth.available || uid == null) {
      return Stream<bool>.value(false);
    }
    // P2.2 schema: single doc per (uid, weekIndex). The week counts as
    // completed once status flips to 'completed'.
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('memory')
        .doc('m3_reminiscence')
        .collection('sessions')
        .doc('week_$weekIndex')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return false;
      final status = snap.data()?['status'] as String?;
      return status == 'completed';
    });
  }
}

class _ThemeCard extends StatelessWidget {
  final ReminiscenceTheme theme;
  final VoidCallback onOpen;
  final Stream<bool> completedStream;
  final Stream<bool>? readyStream;

  const _ThemeCard({
    required this.theme,
    required this.onOpen,
    required this.completedStream,
    this.readyStream,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final t = Theme.of(context);
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
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${theme.weekIndex}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: t.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
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
                      Text(
                        isEn
                            ? 'Week ${theme.weekIndex}'
                            : '第 ${theme.weekIndex} 週',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
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
                StreamBuilder<bool>(
                  stream: completedStream,
                  builder: (_, snap) {
                    final done = snap.data == true;
                    return Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      size: 28,
                      color: done
                          ? Colors.green
                          : t.colorScheme.primary,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

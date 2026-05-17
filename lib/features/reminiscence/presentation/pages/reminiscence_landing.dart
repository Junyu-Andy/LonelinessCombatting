import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/reminiscence_themes.dart';
import 'reminiscence_arm_a_page.dart';
import 'reminiscence_arm_b_page.dart';
import 'reminiscence_memories_page.dart';

/// M3 entry point. Lists the 6 weekly themes with a "completed" check
/// per week (any saved entry for that theme counts). Same UI in both
/// arms — only the session experience that opens differs.
class ReminiscenceLandingPage extends StatelessWidget {
  const ReminiscenceLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final auth = AuthServiceScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Life stories' : '人生點滴'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'A weekly 15–25 minute session. Six themes across six '
                      'weeks. There\'s no right answer — just what you '
                      'remember.'
                  : '每星期一節，15-25 分鐘。6 個主題、6 個禮拜。冇標準答案，記得幾多都得。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openMemories(context),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  isEn ? 'My memories' : '我嘅回憶',
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
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, ReminiscenceTheme theme) {
    // Use the canonical Arm.isA lookup so FORCE_ARM dart-define applies
    // (the previous direct `profile?.arm` read bypassed it).
    final isArmA = Arm.isA(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => isArmA
            ? ReminiscenceArmAPage(theme: theme)
            : ReminiscenceArmBPage(theme: theme),
      ),
    );
  }

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

  const _ThemeCard({
    required this.theme,
    required this.onOpen,
    required this.completedStream,
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
